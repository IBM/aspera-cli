# frozen_string_literal: true

require 'aspera/assert'
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
              Log.log.debug { "detect error: #{e}" }
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
        command :endpoint, description: 'Manage endpoints',         setup: :setup_api
        command :ssh_key,  description: 'Manage SSH keys',          setup: :setup_api
        command :admin,    description: 'Administration',           setup: :setup_api

        commands_under :transfer do
          command :current, description: 'Manage current transfers'
          command :smart,   description: 'Manage smart transfers'
          command :queue,   description: 'Manage transfers of a queue',
            arguments: [{name: :queue_id, type: :identifier}]
        end

        commands_under :endpoint do
          command :list, description: operation_description(:list, 'endpoint'),
            action: ->(api_console:, **) { Result::ObjectList.new(api_console.read('endpoints')) }
        end

        # Payload is not documented in the API: optional
        # command => name of argument
        ADMIN_UPDATES = {email_server_update: :email_server, nodeapi_credentials_update: :credentials}.freeze
        private_constant :ADMIN_UPDATES

        commands_under :admin do
          command :email_server_update,        description: 'Update email server configuration',
            arguments: [{name: ADMIN_UPDATES[:email_server_update], type: Hash, mandatory: false, default: {}}]
          command :nodeapi_credentials_update, description: 'Update Node API credentials',
            arguments: [{name: ADMIN_UPDATES[:nodeapi_credentials_update], type: Hash, mandatory: false, default: {}}]
        end

        # POST <verb>
        ADMIN_UPDATES.each do |verb, arg|
          define_action_method([:admin, verb]) do |api_console:, **kwargs|
            api_console.create(verb.to_s, kwargs.fetch(arg))
            Result::Success.new
          end
        end

        commands_under :ssh_key do
          command :list, description: operation_description(:list, 'SSH key'),
            action: ->(api_console:, **) { Result::ObjectList.new(api_console.read('ssh_keys')) }
        end

        commands_under %i[transfer current] do
          command :list,          description: 'List current transfers'
          command :submit,        description: 'Submit a simple transfer',
            arguments: [{name: :transfer, type: Hash, schema: Schema::Registry.req_body(Schema::Registry::CONSOLE, 'transfers.post')}],
            action: ->(api_console:, transfer:, **) { Result::SingleObject.new(api_console.create('transfers', transfer)) }
          command :show,          description: 'Show a transfer',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: ->(api_console:, transfer_id:, **) { Result::SingleObject.new(api_console.read("transfers/#{transfer_id}")) }
          command :files,         description: 'List files in a transfer',
            arguments: [{name: :transfer_id, type: :identifier}]
          command :start,         description: 'Start a transfer',
            arguments: [{name: :transfer_id, type: :identifier}]
          command :pause,         description: 'Pause a transfer',
            arguments: [{name: :transfer_id, type: :identifier}]
          command :cancel,        description: 'Cancel a transfer',
            arguments: [{name: :transfer_id, type: :identifier}]
          command :resume,        description: 'Resume a transfer',
            arguments: [{name: :transfer_id, type: :identifier}]
          command :rerun,         description: 'Rerun a transfer',
            arguments: [{name: :transfer_id, type: :identifier}]
          command :change_rate,   description: 'Change transfer rate',
            arguments: [{name: :transfer_id, type: :identifier},
                        {name: :rate, type: Hash, schema: Schema::Registry.req_body(Schema::Registry::CONSOLE, 'transfers/{id}/change_rate.put')}]
          command :change_policy, description: 'Change transfer policy',
            arguments: [{name: :transfer_id, type: :identifier},
                        {name: :policy, type: Hash, schema: Schema::Registry.req_body(Schema::Registry::CONSOLE, 'transfers/{id}/change_policy.put')}]
        end

        commands_under %i[transfer queue] do
          command :list,          description: 'List transfers in queue, frontmost first',
            action: ->(api_console:, queue_id:, **) { Result::ObjectList.new(api_console.read("queues/#{queue_id}/items")) }
          command :move_forwards, description: 'Move transfer forwards in queue',
            arguments: [{name: :transfer_id, type: :identifier}]
          command :move_back,     description: 'Move transfer backwards in queue',
            arguments: [{name: :transfer_id, type: :identifier}]
        end

        # PUT queues/<queue_id>/items/<id>/<verb>
        %i[move_forwards move_back].each do |verb|
          define_action_method([:transfer, :queue, verb]) do |api_console:, queue_id:, transfer_id:, **|
            Result::SingleObject.new(api_console.update("queues/#{queue_id}/items/#{transfer_id}/#{verb}", {}))
          end
        end

        # Generate one handler per transfer/current action.
        # Convention: action_transfer_current_<verb>
        # All share the same REST pattern: PUT transfers/<id>/<verb>.
        %i[start pause cancel resume].each do |verb|
          define_action_method([:transfer, :current, verb]) do |api_console:, transfer_id:, **|
            Result::SingleObject.new(api_console.update("transfers/#{transfer_id}/#{verb}", {}))
          end
        end

        # PUT transfers/<id>/<verb> with request body
        {change_rate: :rate, change_policy: :policy}.each do |verb, arg|
          define_action_method([:transfer, :current, verb]) do |api_console:, transfer_id:, **kwargs|
            Result::SingleObject.new(api_console.update("transfers/#{transfer_id}/#{verb}", kwargs.fetch(arg)))
          end
        end

        commands_under %i[transfer smart] do
          command :list,   description: 'List smart transfers', action: ->(api_console:, **) { Result::ObjectList.new(api_console.read('smart_transfers')) }
          command :submit, description: 'Submit a smart transfer',
            arguments: [{name: :smart_id}, {name: :transfer, type: Hash, schema: Schema::Registry.req_body(Schema::Registry::CONSOLE, 'smart_transfers/{id}.post')}]
          command :pause,  description: 'Pause a smart transfer',
            arguments: [{name: :smart_id}],
            action: ->(api_console:, smart_id:, **) { Result::SingleObject.new(api_console.update("smart_transfers/#{smart_id}/pause", {})) }
        end

        # --- setup ---

        # Build the Console REST API.
        # @return [Hash] ctx with :api_console
        def setup_api(**)
          {api_console: basic_auth_api('api')}
        end

        # --- health ---

        def action_health(api_console:, **)
          nagios = Nagios.new
          begin
            # Unauthenticated, outside of the API prefix
            Rest.new(base_url: options.get_option(:url, mandatory: true)).read('health/up')
            nagios.add_ok('console process', 'up')
          rescue StandardError => e
            nagios.add_critical('console process', e.to_s)
          end
          begin
            api_console.read('ssh_keys')
            nagios.add_ok('console api', 'accessible')
          rescue StandardError => e
            nagios.add_critical('console api', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        # --- transfer current ---

        def action_transfer_current_list(api_console:, **)
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

        def action_transfer_current_rerun(api_console:, transfer_id:, **)
          Result::SingleObject.new(api_console.create("transfers/#{transfer_id}/rerun", {}))
        end

        def action_transfer_current_files(api_console:, transfer_id:, **)
          query = query_read_delete(default: {})
          query['limit'] ||= 100
          Result::ObjectList.new(api_console.read("transfers/#{transfer_id}/files", query))
        end

        # --- transfer smart ---

        def action_transfer_smart_submit(api_console:, smart_id:, transfer:, **)
          Result::ObjectList.new(api_console.create("smart_transfers/#{smart_id}", transfer))
        end

        private

        def parse_extended_filter(filter, query)
          Aspera.assert(filter.start_with?('(') && filter.end_with?(')'), type: BadArgument) { "Invalid filter syntax: #{filter}, shall be (field op val)and(field op val)..." }
          filter[1..-2].split(')and(').each_with_index do |expr, i|
            m = expr.match(EXPR_RE)
            Aspera.assert(m, type: BadArgument) { "Invalid expression: #{expr}, shall be: <field> <op> <val>" }
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
