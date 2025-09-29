# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/nagios'
require 'aspera/cli/basic_auth_plugin'

module Aspera
  module Cli
    module Plugins
      class Faspio < BasicAuthPlugin
        class << self
          def application_name
            'faspio Gateway'
          end

          def detect(base_url)
            api = Rest.new(base_url: base_url)
            ping_result = api.call(operation: 'GET', subpath: 'ping', headers: {'Accept' => Rest::MIME_JSON})
            server_type = ping_result[:http]['Server']
            return unless ping_result[:data].is_a?(Hash) && ping_result[:data].empty?
            return unless server_type.is_a?(String) && server_type.include?('faspio')
            return {
              version: server_type.gsub(%r{^.*/}, ''),
              url:     base_url
            }
          end

          # @param object [Plugin] An instance of this class
          # @return [Hash] :preset_value, :test_args
          def wizard(object:)
            options = object.options
            return {
              preset_value: {
                url: options.get_option(:url, mandatory: true)
              },
              test_args:    'info'
            }
          end
        end
        ACTIONS = %i[health bridges].freeze

        def initialize(**_)
          super
          options.declare(:auth, 'OAuth type of authentication', values: %i[jwt basic])
          options.declare(:client_id, 'OAuth client identifier')
          options.declare(:private_key, 'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.declare(:passphrase, 'OAuth JWT RSA private key passphrase')
          options.parse_options!
        end

        def execute_action
          base_url = options.get_option(:url, mandatory: true)
          api =
            case options.get_option(:auth, mandatory: true)
            when :basic
              basic_auth_api
            when :jwt
              app_client_id = options.get_option(:client_id, mandatory: true)
              Rest.new(
                base_url: base_url,
                auth:     {
                  type:            :oauth2,
                  grant_method:    :jwt,
                  base_url:        "#{base_url}/auth",
                  client_id:       app_client_id,
                  use_query:       true,
                  payload:         {
                    iss: app_client_id, # issuer
                    sub: app_client_id  # subject
                  },
                  private_key_obj: OpenSSL::PKey::RSA.new(options.get_option(:private_key, mandatory: true), options.get_option(:passphrase)),
                  headers:         {typ: 'JWT'}
                }
              )
            end
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              result = api.read('ping')
              if result.is_a?(Hash) && result.empty?
                nagios.add_ok('api', 'answered ok')
              else
                nagios.add_critical('api', 'not expected answer')
              end
            rescue StandardError => e
              nagios.add_critical('api', e.to_s)
            end
            return nagios.result
          when :bridges
            return entity_execute(api: api, entity: 'bridges')
          end
        end
      end
    end
  end
end
