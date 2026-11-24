# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../log'
require_relative '../../assert'
require_relative '../../hash_ext'
require_relative '../../secret/strength'
require_relative '../../servlet_helpers'
require_relative '../../web_server_simple'
require 'webrick'
require 'json'

module Aspera
  module Plugins
    module Faspex4
      # Simulate the Faspex 4 /send API; the package is created by the product that starts the gateway (Aspera on Cloud, Faspex 5), see `serve`
      #
      # Security notes:
      # - Packages are created as the user of the application, to any recipient, and the caller receives an upload transfer spec.
      # - Clients authenticate with HTTP Basic, as on Faspex 4, when `username` and `password` are set:
      #   they are required when the server listens on an address that is not loopback (checked by `serve`).
      # - Requests that a web page could send are refused (see ServletHelpers#check_request): the body shall be `application/json`.
      class GWServlet < WEBrick::HTTPServlet::AbstractServlet
        include ServletHelpers

        ALLOWED_PARAMETERS = %i[username password password_min_bits].freeze
        REALM = 'Faspex 4 Gateway'
        private_constant :REALM

        class << self
          # Check parameters and set defaults
          # Called at startup, so that errors are reported before the first request
          # @param parameters [Hash] Parameters of the servlet
          # @return [Hash] Parameters with defaults
          def normalize_parameters(parameters)
            Aspera.assert_type(parameters, Hash)
            parameters = parameters.symbolize_keys
            not_allowed = parameters.keys - ALLOWED_PARAMETERS
            Aspera.assert(not_allowed.empty?, type: ParameterError) { "unsupported parameters: #{not_allowed.join(', ')}" }
            Aspera.assert(parameters[:username].nil? == parameters[:password].nil?, type: ParameterError) { 'Parameters username and password must be set together' }
            parameters[:password_min_bits] ||= Secret::Strength::DEFAULT_MIN_BITS
            Secret::Strength.assert_strong(parameters[:password], name: 'password', min_bits: parameters[:password_min_bits]) unless parameters[:password].nil?
            parameters
          end

          # Start the gateway, until signal INT or TERM
          # @param parameters [Hash]      Parameters of the server (see `WebServerSimple.url`) and of the servlet (see `normalize_parameters`)
          # @param type       [Exception] Exception raised when the server is not protected
          # @yieldreturn [#call] Creates the package in the application, see `initialize`: called once parameters are checked
          def serve(parameters, type: ParameterError)
            servlet_parameters = normalize_parameters(WebServerSimple.servlet_parameters(parameters))
            # Packages can be sent to anyone by anyone who can reach the server
            WebServerSimple.serve(parameters, self, protected: !servlet_parameters[:username].nil?, what: 'username and password', type: type) { [servlet_parameters, yield] }
          end
        end

        # @param server         [WEBrick::HTTPServer] Server
        # @param parameters     [Hash]                Parameters from `normalize_parameters`
        # @param package_sender [#call]               Creates the package in the application: receives the parameters of the Faspex 4 package creation (with `delivery`),
        #                                             returns the transfer spec to upload the package files
        def initialize(server, parameters, package_sender)
          Aspera.assert(package_sender.respond_to?(:call), type: ParameterError) { 'package_sender shall be callable' }
          super(server)
          @expected_auth = "#{parameters[:username]}:#{parameters[:password]}" unless parameters[:username].nil?
          @package_sender = package_sender
        end

        def do_POST(request, response)
          # Refuse requests of web pages
          check_request(request, json: true)
          return json_error(response, 401, 'Invalid or missing credentials', headers: {'WWW-Authenticate' => %Q(Basic realm="#{REALM}")}) unless authorized?(request)
          return json_error(response, 400, 'Unsupported endpoint') unless request.path.eql?('/aspera/faspex/send')
          faspex_pkg_parameters = package_parameters(request.body)
          Log.dump(:faspex_pkg_parameters, faspex_pkg_parameters)
          # the transfer spec is placed in a Faspex package creation response
          faspex_package_create_result = {
            'links'         => {'status' => 'unused'},
            'xfer_sessions' => [@package_sender.call(faspex_pkg_parameters)]
          }
          Log.dump(:faspex_package_create_result, faspex_package_create_result)
          json_response(response, 200, faspex_package_create_result)
        rescue WEBrick::HTTPStatus::Error => e
          Log.log.warn { "Rejected request: #{e.message}" }
          json_error(response, e.code, e.message)
        rescue StandardError => e
          # The stack trace is logged only: it is not for the caller
          Log.log.error(e.message)
          Log.log.debug { e.backtrace.join("\n") }
          json_error(response, 500, e.message)
        end

        private

        # @param request [WEBrick::HTTPRequest]
        # @return [Boolean] `true` if the request has the expected Basic credentials, or if none are expected
        def authorized?(request)
          @expected_auth.nil? || basic_authorized?(request, @expected_auth)
        end

        # @param body [String, nil] Body of the request
        # @return [Hash] Parameters of Faspex 4 package creation, with `delivery` and its `recipients`
        # @raise [WEBrick::HTTPStatus::BadRequest] if the body is not a valid package creation request
        def package_parameters(body)
          raise WEBrick::HTTPStatus::BadRequest, 'Empty request' if body.nil?
          parameters =
            begin
              JSON.parse(body)
            rescue JSON::ParserError
              nil
            end
          raise WEBrick::HTTPStatus::BadRequest, 'Request body shall be a JSON object' unless parameters.is_a?(Hash)
          raise WEBrick::HTTPStatus::BadRequest, 'Missing object: delivery' unless parameters['delivery'].is_a?(Hash)
          recipients = parameters['delivery']['recipients']
          raise WEBrick::HTTPStatus::BadRequest, 'delivery.recipients shall be a non-empty list of names' unless recipients.is_a?(Array) && !recipients.empty? && recipients.all?(String)
          parameters
        end
      end
    end
  end
end
