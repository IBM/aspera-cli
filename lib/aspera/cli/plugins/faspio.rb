# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/nagios'
require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      class Faspio < BasicAuth
        class << self
          def application_name
            'faspio Gateway'
          end

          # @return [Hash,NilClass]
          def detect(base_url)
            api = Rest.new(base_url: base_url)
            data, http = api.read('ping', ret: :both)
            server_type = http['Server']
            return unless data.is_a?(Hash) && data.empty?
            return unless server_type.is_a?(String) && server_type.include?('faspio')
            return {
              version: server_type.gsub(%r{^.*/}, ''),
              url:     base_url
            }
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [String] Tested URL
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          return {
            preset_value: {
              url: app_url
            },
            test_args:    'info'
          }
        end

        ACTIONS = %i[health bridges].freeze

        def initialize(**_)
          super
          options.declare(:auth, 'OAuth type of authentication', allowed: %i[jwt basic])
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
            Main.result_object_list(nagios.status_list)
          when :bridges
            return entity_execute(api: api, entity: 'bridges')
          end
        end
      end
    end
  end
end
