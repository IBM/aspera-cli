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
          # @return [Hash,NilClass]
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)
            error = nil
            urls.each do |base_url|
              next unless base_url.start_with?('https://')
              api = Rest.new(base_url: base_url, redirect_max: 2)
              test_endpoint = 'login'
              http = api.call(
                operation: 'GET',
                subpath:   test_endpoint,
                query:     {local: true},
                ret:       :resp
              )
              next unless http.body.include?('Aspera Console')
              version = 'unknown'
              if (m = http.body.match(/\(v([1-9]\..*)\)/))
                version = m[1]
              end
              url = http.uri.to_s
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
        # @param app_url [String] Tested URL
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

        # --- DSL ---

        command :health,   description: 'Check Console API health', setup: :setup_api
        command :transfer, description: 'Manage transfers',         setup: :setup_api

        commands_under(:transfer) do
          command :current, description: 'Manage current transfers'
          command :smart,   description: 'Manage smart transfers'
        end

        commands_under(%i[transfer current]) do
          command :list,          description: 'List current transfers'
          command :show,          description: 'Show a transfer',          instance_arg: :transfer_id,
            action: ->(api_console:, transfer_id:, **){Result::SingleObject.new(api_console.read("transfers/#{transfer_id}"))}
          command :files,         description: 'List files in a transfer', instance_arg: :transfer_id
          command :start,         description: 'Start a transfer',         instance_arg: :transfer_id
          command :pause,         description: 'Pause a transfer',         instance_arg: :transfer_id
          command :cancel,        description: 'Cancel a transfer',        instance_arg: :transfer_id
          command :resume,        description: 'Resume a transfer',        instance_arg: :transfer_id
          command :rerun,         description: 'Rerun a transfer',         instance_arg: :transfer_id
          command :change_rate,   description: 'Change transfer rate',     instance_arg: :transfer_id
          command :change_policy, description: 'Change transfer policy',   instance_arg: :transfer_id
          command :move_forwards, description: 'Move transfer forwards',   instance_arg: :transfer_id
          command :move_back,     description: 'Move transfer backwards',  instance_arg: :transfer_id
        end

        # Generate one handler per transfer/current action.
        # Convention: handle_transfer_current_<verb>
        # All share the same REST pattern: PATCH transfers/<id>/<verb>.
        %i[start pause cancel resume rerun change_rate change_policy move_forwards move_back].each do |verb|
          define_method(:"handle_transfer_current_#{verb}") do |api_console:, transfer_id:, **|
            Result::SingleObject.new(api_console.update("transfers/#{transfer_id}/#{verb}", query_read_delete))
          end
        end

        commands_under(%i[transfer smart]) do
          command :list,   description: 'List smart transfers', action: ->(api_console:){Result::ObjectList.new(api_console.read('smart_transfers'))}
          command :submit, description: 'Submit a smart transfer'
        end

        # --- setup ---

        # Build the Console REST API.
        # @return [Hash] ctx with :api_console
        def setup_api(**)
          {api_console: basic_auth_api('api')}
        end

        # --- health ---

        def handle_health(api_console:)
          nagios = Nagios.new
          begin
            api_console.read('ssh_keys')
            nagios.add_ok('console api', 'accessible')
          rescue StandardError => e
            nagios.add_critical('console api', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        # --- transfer current ---

        def handle_transfer_current_list(api_console:)
          query = query_read_delete(default: {})
          if query['from'].nil? && query['to'].nil?
            time_now = Time.now
            query['from'] = self.class.time_to_string(time_now - DEFAULT_FILTER_AGE_SECONDS)
            query['to'] = self.class.time_to_string(time_now)
          end
          parse_extended_filter(query.delete('filter'), query) if query['filter']
          Result::ObjectList.new(
            api_console.read('transfers', query),
            fields: %w[id contact name status]
          )
        end

        def handle_transfer_current_files(api_console:, transfer_id:, **)
          query = query_read_delete(default: {})
          query['limit'] ||= 100
          Result::ObjectList.new(api_console.read("transfers/#{transfer_id}/files", query))
        end

        # --- transfer smart ---

        def handle_transfer_smart_submit(api_console:)
          smart_id = options.get_next_argument('smart_id')
          params = options.get_next_argument('transfer parameters', validation: Hash)
          Result::ObjectList.new(api_console.create("smart_transfers/#{smart_id}", params))
        end

        private

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
      end
    end
  end
end
