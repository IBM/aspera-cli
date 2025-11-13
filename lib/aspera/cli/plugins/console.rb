# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      class Console < BasicAuth
        STANDARD_PATH = '/aspera/console'
        DEFAULT_FILTER_AGE_SECONDS = 24 * 3600
        EXPR_RE = /\A(\S+) (\S+) (.*)\z/
        private_constant :STANDARD_PATH, :DEFAULT_FILTER_AGE_SECONDS, :EXPR_RE

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
              test_page = api.call(
                operation: 'GET',
                subpath:   test_endpoint,
                query:     {local: true}
              )
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
            return
          end

          def time_to_string(time)
            return time.strftime('%Y-%m-%d %H:%M:%S')
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [Wizard] The wizard object
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          return {
            preset_value: {
              url:      app_url,
              username: options.get_option(:username, mandatory: true),
              password: options.get_option(:password, mandatory: true)
            },
            test_args:    'transfer list'
          }
        end

        def initialize(**_)
          super
        end

        def parse_extended_filter(filter, query)
          raise BadArgument, "Invalid filter syntax: #{filter}, shall be (field op val)and(field op val)..." unless filter.start_with?('(') && filter.end_with?(')')
          filter[1..-2].split(')and(').each_with_index do |expr, i|
            m = expr.match(EXPR_RE)
            raise BadArgument, "Invalid expression: #{expr}, shall be: <field> <op> <val>" unless m
            t = m.captures
            i += 1
            query["filter#{i}"] = t[0]
            query["comp#{i}"]   = t[1]
            query["val#{i}"]    = t[2]
          end
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
            Main.result_object_list(nagios.status_list)
          when :transfer
            command = options.get_next_command(%i[current smart])
            case command
            when :smart
              command = options.get_next_command(%i[list submit])
              case command
              when :list
                return Main.result_object_list(api_console.read('smart_transfers'))
              when :submit
                smart_id = options.get_next_argument('smart_id')
                params = options.get_next_argument('transfer parameters', validation: Hash)
                return Main.result_object_list(api_console.create("smart_transfers/#{smart_id}", params))
              end
            when :current
              command = options.get_next_command(%i[list show files start pause cancel resume rerun change_rate change_policy move_forwards move_back])
              case command
              when :list
                # https://developer.ibm.com/apis/catalog/aspera--aspera-console-rest-api/Developer+Guides#transfer-list
                query = query_read_delete(default: {})
                if query['from'].nil? && query['to'].nil?
                  time_now = Time.now
                  query['from'] = self.class.time_to_string(time_now - DEFAULT_FILTER_AGE_SECONDS)
                  query['to'] = self.class.time_to_string(time_now)
                end
                if (filter = query.delete('filter'))
                  parse_extended_filter(filter, query)
                end
                return Main.result_object_list(
                  api_console.read('transfers', query),
                  fields: %w[id contact name status]
                )
              when :show
                transfer_id = instance_identifier(description: 'transfer ID')
                return Main.result_single_object(api_console.read("transfers/#{transfer_id}"))
              when :files
                transfer_id = instance_identifier(description: 'transfer ID')
                query = query_read_delete(default: {})
                query['limit'] ||= 100
                return Main.result_object_list(api_console.read("transfers/#{transfer_id}/files", query))
              when :start, :pause, :cancel, :resume, :rerun, :change_rate, :change_policy, :move_forwards, :move_back
                transfer_id = instance_identifier(description: 'transfer ID')
                return Main.result_single_object(api_console.update("transfers/#{transfer_id}/#{command}", query_read_delete))
              end
            end
          end
        end
      end
    end
  end
end
