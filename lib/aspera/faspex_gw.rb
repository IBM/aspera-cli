# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/mime'
require 'aspera/servlet_helpers'
require 'webrick'
require 'json'

module Aspera
  # Simulate the Faspex 4 /send API and creates a package on Aspera on Cloud or Faspex 5
  class Faspex4GWServlet < WEBrick::HTTPServlet::AbstractServlet
    include ServletHelpers

    AOC_API = 'Aspera::Api::AoC'
    FX_API = 'Aspera::Api::Faspex'
    # @param app_api     [Rest::Client]   API object
    # @param app_context [String] workspace id (aoc only)
    def initialize(server, app_api, app_context)
      Aspera.assert_values(app_api.class.name, [AOC_API, FX_API])
      super(server)
      @app_api = app_api
      @app_context = app_context
    end

    # Map Faspex 4 /send API to AoC package create
    # parameters from user to Faspex API call
    # https://developer.ibm.com/apis/catalog/aspera--aspera-faspex-client-sdk/Sending%20Packages%20(API%20v.3)
    def faspex4_send_to_aoc(faspex_pkg_parameters)
      faspex_pkg_delivery = faspex_pkg_parameters['delivery']
      package_data = {
        # 'file_names'   => faspex_pkg_delivery['sources'][0]['paths'],
        'name'         => faspex_pkg_delivery['title'],
        'note'         => faspex_pkg_delivery['note'],
        'recipients'   => faspex_pkg_delivery['recipients'],
        'workspace_id' => @app_context
      }
      created_package = @app_api.create_package_simple(package_data, true, nil)
      # but we place it in a Faspex package creation response
      return {
        'links'         => {'status' => 'unused'},
        'xfer_sessions' => [created_package[:spec]]
      }
    end

    def faspex4_send_to_faspex5(faspex_pkg_parameters)
      faspex_pkg_delivery = faspex_pkg_parameters['delivery']
      package_data = {
        'title'      => faspex_pkg_delivery['title'],
        'note'       => faspex_pkg_delivery['note'],
        'recipients' => faspex_pkg_delivery['recipients'].map { |name| {'name'=>name} }
      }
      package = @app_api.create('packages', package_data)
      # TODO: option to send from remote source or httpgw
      transfer_spec = @app_api.call(
        operation:    'POST',
        subpath:      "packages/#{package['id']}/transfer_spec/upload",
        query:        {transfer_type: Api::Faspex::TRANSFER_CONNECT},
        content_type: Mime::JSON,
        body:         {paths: [{'destination'=>'/'}]},
        headers:      {'Accept' => Mime::JSON}
      )
      transfer_spec.delete('authentication')
      # but we place it in a Faspex package creation response
      return {
        'links'         => {'status' => 'unused'},
        'xfer_sessions' => [transfer_spec]
      }
    end

    def do_POST(request, response)
      # Refuse requests of web pages
      check_request(request, json: true)
      return json_error(response, 400, 'Unsupported endpoint') unless request.path.eql?('/aspera/faspex/send')
      Aspera.assert(!request.body.nil?, 'payload missing')
      faspex_pkg_parameters = JSON.parse(request.body)
      Log.dump(:faspex_pkg_parameters, faspex_pkg_parameters)
      # compare string, as class is not yet known here
      faspex_package_create_result =
        case @app_api.class.name
        when AOC_API
          faspex4_send_to_aoc(faspex_pkg_parameters)
        when FX_API
          faspex4_send_to_faspex5(faspex_pkg_parameters)
        else Aspera.error_unexpected_value(@app_api.class.name)
        end
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
  end
end
