# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      class Console < Cli::BasicAuthPlugin
        STANDARD_PATH = '/aspera/console'
        class << self
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)
            error = nil
            urls.each do |base_url|
              next unless base_url.start_with?('https://')
              api = Rest.new(base_url: base_url, redirect_max: 2)
              test_endpoint = 'login'
              test_page = api.call(operation: 'GET', subpath: test_endpoint, url_params: {local: true})
              next unless test_page[:http].body.include?('Aspera Console')
              version = 'unknown'
              if (m = test_page[:http].body.match(/\(v([1-9]\..*)\)/))
                version = m[1]
              end
              url = test_page[:http].uri.to_s
              return {
                version: version,
                url:     url[0..url.index(test_endpoint) - 2]
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return nil
          end

          def wizard(object:, private_key_path: nil, pub_key_pem: nil)
            options = object.options
            return {
              preset_value: {
                url:      options.get_option(:url, mandatory: true),
                username: options.get_option(:username, mandatory: true),
                password: options.get_option(:password, mandatory: true)
              },
              test_args:    'transfer list'
            }
          end
        end
        DEFAULT_FILTER_AGE_SECONDS = 3 * 3600
        private_constant :DEFAULT_FILTER_AGE_SECONDS
        def initialize(**env)
          super
          time_now = Time.now
          options.declare(:filter_from, 'Only after date', values: :date, default: Manager.time_to_string(time_now - DEFAULT_FILTER_AGE_SECONDS))
          options.declare(:filter_to, 'Only before date', values: :date, default: Manager.time_to_string(time_now))
          options.parse_options!
        end

        ACTIONS = %i[transfer health].freeze

        def execute_action
          api_console = basic_auth_api('api')
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              api_console.read('ssh_keys')
              nagios.add_ok('console api', 'accessible')
            rescue StandardError => e
              nagios.add_critical('console api', e.to_s)
            end
            return nagios.result
          when :transfer
            command = options.get_next_command(%i[current smart])
            case command
            when :smart
              command = options.get_next_command(%i[list submit])
              case command
              when :list
                return {type: :object_list, data: api_console.read('smart_transfers')[:data]}
              when :submit
                smart_id = options.get_next_argument('smart_id')
                params = options.get_next_argument('transfer parameters')
                return {type: :object_list, data: api_console.create("smart_transfers/#{smart_id}", params)[:data]}
              end
            when :current
              command = options.get_next_command([:list])
              case command
              when :list
                return {
                  type:   :object_list,
                  data:   api_console.read('transfers', {
                    'from' => options.get_option(:filter_from, mandatory: true),
                    'to'   => options.get_option(:filter_to, mandatory: true)
                  })[:data],
                  fields: %w[id contact name status]}
              end
            end
          end
        end
      end
    end
  end
end
