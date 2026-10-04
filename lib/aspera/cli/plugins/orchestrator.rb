# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/special_values'
require 'aspera/nagios'
require 'aspera/log'
require 'aspera/assert'
require 'xmlsimple'

module Aspera
  module Cli
    module Plugins
      # Aspera Orchestrator
      class Orchestrator < BasicAuth
        STANDARD_PATH = '/aspera/orchestrator'
        TEST_ENDPOINT = 'api/remote_node_ping'
        private_constant :STANDARD_PATH, :TEST_ENDPOINT

        class << self
          # @return [Hash,NilClass]
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)
            error = nil
            urls.each do |base_url|
              next unless base_url.match?(%r{^https?://})
              api = Rest::Client.new(base_url: base_url)
              data, http = api.read(TEST_ENDPOINT, query: {format: :json}, ret: :both)
              next unless data['remote_orchestrator_info']
              url = http.uri.to_s
              return {
                version: data['remote_orchestrator_info']['orchestrator-version'],
                url:     url[0..url.index(TEST_ENDPOINT) - 2]
              }
            rescue StandardError => e
              error = e
              Log.log.debug { "detect error: #{e}" }
            end
            raise error if error
            return
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
            test_args:    'workflow list'
          }
        end

        option :apikey,      description: 'API key (exclusive with username/password)'
        option :auth_style,  description: 'Authentication style', allowed: %i[basic query token], default: :token
        option :ret_style,   description: 'Method to specify the expected response format ("Accept")', allowed: %i[header query path], default: :query
        option :result,      description: "Specify result value as: 'work_step:parameter'", deprecation: {last: '4.27.2', message: 'use keys `step` and `variable` of argument `execution` of `workflows start`'}
        option :synchronous, description: 'Wait for completion', allowed: Type::BOOLEAN, deprecation: {last: '4.27.2', message: 'use key `synchronous` of argument `execution` of `workflows start`'}

        # Call orchestrator API (handles ret_style negotiation and XML parsing)
        # @param endpoint   [String]  the endpoint to call
        # @param body       [Hash]    the body to pass (JSON); also implies POST
        # @param format     [String]  the format to request, 'json', 'xml', nil
        # @param query      [Hash]    the arguments to pass as query parameters
        # @param xml_arrays [Boolean] if true, force arrays in xml parsing
        # @param http       [Boolean] if true, returns the HttpResponse, else
        def call_ao(endpoint, body: nil, format: 'json', query: nil, xml_arrays: true, http: false)
          call_args = {operation: body.nil? ? 'GET' : 'POST', subpath: "api/#{endpoint}", ret: :both, query: {}}
          call_args.merge!(body: body, content_type: Mime::JSON) unless body.nil?
          ret_style = options.get_option(:ret_style, mandatory: true)
          call_args[:query].merge!(query) unless query.nil?
          unless format.nil?
            case ret_style
            when :header
              call_args[:headers] = {'Accept' => "application/#{format}"}
            when :query
              call_args[:query][:format] = format
            when :path
              call_args[:subpath] = "#{call_args[:subpath]}.#{format}"
            else Aspera.error_unexpected_value(ret_style) { 'ret_style' }
            end
          end
          add_query = query_read_delete
          call_args[:query].merge!(add_query.symbolize_keys) unless add_query.nil?
          data, resp = api_orch.call(**call_args)
          return resp if http
          result = format.eql?('xml') ? XmlSimple.xml_in(resp.body, {'ForceArray' => xml_arrays}) : data
          Log.dump(:data, result)
          return result
        end

        private :call_ao

        # --- DSL ---

        command :health,     description: 'Check Orchestrator API health'
        command :info,       description: 'Check that Orchestrator responds (ping)', action: ->(**) { Result::SingleObject.new(call_ao('remote_node_ping', format: 'xml', xml_arrays: false)) }
        command :processes,  description: 'Show Orchestrator background process status', action: ->(**) { Result::ObjectList.new(call_ao('processes_status', format: 'xml')['node'].flat_map { |n| n['process'] }) }
        command :monitors,   description: 'Show Orchestrator monitor snapshot', action: ->(**) { Result::SingleObject.new(call_ao('monitor_snapshot')['monitor']) }
        command :workorders, description: 'Manage work orders'
        command :workstep,   description: 'Manage work steps'

        commands_under :plugins do
          command :list,       description: 'Show Orchestrator plugin versions', action: ->(**) { Result::ObjectList.new(call_ao('plugin_version')['Plugin']) }
          command :reload_set, description: 'Reload a set of plugins',
            arguments: [{name: :plugin_set, type: Hash, schema: 'opts:components.schemas.OrchestratorReloadPluginSet'}],
            action: ->(plugin_set:, **) { Result::SingleObject.new(call_ao('reload_plugin_set', body: plugin_set.transform_keys(&:to_sym))) }
        end

        commands_under :workflows do
          command :list, description: 'List all workflows'
          command :status,     description: 'Show running status of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao(workflow_id.eql?(SpecialValues::ALL) ? 'workflows_status' : "workflows_status/#{workflow_id}")['workflows']['workflow']) }
          command :inputs,     description: 'Show input specification of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::SingleObject.new(call_ao("workflow_inputs_spec/#{workflow_id}")['workflow_inputs_spec']) }
          command :details,    description: 'Show detailed running status of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao("workflow_details/#{workflow_id}")['workflows']['workflow']['statuses']) }
          command :start,      description: 'Start a workflow: create a work order (sync or async)',
            arguments: [
              {name: :workflow_id, type: :identifier},
              {name: :parameters, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.OrchestratorInitiateParameters'},
              {name: :execution, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.OrchestratorWorkflowStart'}
            ]
          command :import,     description: 'Import a workflow',
            arguments: [{name: :workflow, type: Hash, schema: 'opts:components.schemas.OrchestratorImportWorkflow'}],
            action: ->(workflow:, **) { Result::SingleObject.new(call_ao('import_workflow', body: workflow.transform_keys(&:to_sym))) }
          command :publish,    description: 'Publish a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::SingleObject.new(call_ao('publish_workflow', body: {workflow_id: workflow_id.to_i})) }
          command :import_with_constraints, description: 'Import a workflow with constraint resolution',
            arguments: [{name: :payload, type: Hash, schema: 'opts:components.schemas.OrchestratorImportWithConstraints'}],
            action: ->(payload:, **) { Result::SingleObject.new(call_ao('import_with_constraints', body: payload.transform_keys(&:to_sym))) }
          command :export,     description: 'Export a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::Text.new(call_ao("export_workflow/#{workflow_id}", format: nil, http: true).body) }
          command :workorders, description: 'List work orders of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao("work_orders_list/#{workflow_id}")['work_orders']) }
          command :outputs,    description: 'Show output specification of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao("workflow_outputs_spec/#{workflow_id}")['workflow_outputs_spec']['output']) }
        end

        commands_under :workorders do
          command :status, description: 'Show status of a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::SingleObject.new(call_ao("work_order_status/#{workorder_id}")['work_order']) }
          command :cancel, description: 'Cancel a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::SingleObject.new(call_ao("work_order_cancel/#{workorder_id}")['work_order']) }
          command :reset,  description: 'Reset a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::SingleObject.new(call_ao("work_order_reset/#{workorder_id}")['work_order']) }
          command :output, description: 'Show output of a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::ObjectList.new(call_ao("work_order_output/#{workorder_id}", format: 'xml')['variable']) }
        end

        commands_under :workstep do
          command :status, description: 'Show status of a work step',
            arguments: [{name: :workstep_id, type: :identifier}],
            action: ->(workstep_id:, **) { Result::SingleObject.new(call_ao("work_step_status/#{workstep_id}")) }
          command :cancel, description: 'Cancel a work step',
            arguments: [{name: :workstep_id, type: :identifier}],
            action: ->(workstep_id:, **) { Result::SingleObject.new(call_ao("work_step_cancel/#{workstep_id}")) }
        end

        # --- API ---

        # Orchestrator REST API, built from CLI options on first use.
        # @return [Rest::Client]
        def api_orch
          return @api_orch if @api_orch
          base_url = options.get_option(:url, mandatory: true)
          style = options.get_option(:auth_style, mandatory: true)
          apikey = options.get_option(:apikey)
          username = options.get_option(:username)
          password = options.get_option(:password)
          Aspera.assert(apikey.nil? || (username.nil? && password.nil?), type: Cli::BadArgument) { 'apikey and username/password are mutually exclusive' }
          Aspera.assert(!apikey.nil? || (!username.nil? && !password.nil?), type: Cli::BadArgument) { 'provide either apikey or username and password' }

          auth_params =
            case style
            when :basic
              Aspera.assert(apikey.nil?, type: Cli::BadArgument) { 'basic auth style cannot be used with apikey, use token or query' }
              {
                type:     :basic,
                username: username,
                password: password
              }
            when :query
              if apikey
                {type: :url, url_query: {'apikey' => apikey}}
              else
                {type: :url, url_query: {'login' => username, 'password' => password}}
              end
            when :token
              {
                type:         :oauth2,
                grant_method: :json_credentials,
                base_url:     base_url,
                path_token:   'api/login',
                token_field:  'token',
                json:         apikey ? {apikey: apikey} : {username: username, password: password}
              }
            else Aspera.error_unexpected_value(style)
            end
          @api_orch = Rest::Client.new(
            base_url: base_url,
            auth:     auth_params
          )
        end

        def action_health(**)
          nagios = Nagios.new
          begin
            info = call_ao('remote_node_ping', format: 'xml', xml_arrays: false)
            nagios.add_ok('api', 'accessible')
            nagios.check_product_version('api', 'orchestrator', info['orchestrator-version'])
          rescue StandardError => e
            nagios.add_critical('node api', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        # 2.1/2.2 Initiate a workorder (async / synchronous)
        def action_workflows_list(**)
          Result::ObjectList.new(
            call_ao('workflows_list')['workflows']['workflow'],
            fields: %w[id portable_id name published_status published_revision_id latest_revision_id last_modification]
          )
        end

        # Keys of argument `execution` of `workflows start`
        WORKFLOW_START_KEYS = %w[synchronous step variable].freeze
        private_constant :WORKFLOW_START_KEYS

        def action_workflows_start(workflow_id:, parameters:, execution:, **)
          execution = execution.transform_keys(&:to_s)
          unknown = execution.keys - WORKFLOW_START_KEYS
          Aspera.assert(unknown.empty?, type: Cli::BadArgument) { "Unknown keys in execution: #{unknown.join(', ')}, expected: #{WORKFLOW_START_KEYS.join(', ')}" }
          # Deprecated options, used when key not provided
          execution['synchronous'] = options.get_option(:synchronous) unless execution.key?('synchronous')
          result_location = options.get_option(:result)
          unless result_location.nil? || execution.key?('step') || execution.key?('variable')
            fields = result_location.split(':')
            Aspera.assert(fields.length == 2, type: Cli::BadArgument) { "Expects: work_step:result_name : #{result_location}" }
            execution['step'], execution['variable'] = fields
          end
          # POST /api/initiate with JSON body {workflow_id:, external_parameters:}
          json_body = {workflow_id: workflow_id.to_i, external_parameters: parameters}
          # control params passed as query string (not part of the spec requestBody)
          query_params = {}
          Aspera.assert_type(execution['synchronous'], NilClass, *BoolValue::TYPES, type: Cli::BadArgument) { 'synchronous' }
          query_params[:synchronous] = true if execution['synchronous'].eql?(true)
          # expected result for synchro call ?
          if execution.key?('step') || execution.key?('variable')
            Aspera.assert(execution['step'].is_a?(String) && execution['variable'].is_a?(String), type: Cli::BadArgument) { 'Both step and variable are required' }
            query_params[:explicit_output_step] = execution['step']
            query_params[:explicit_output_variable] = execution['variable']
            # implicitly, call is synchronous
            query_params[:synchronous] = true
          end
          result_data = call_ao('initiate', body: json_body, query: query_params.empty? ? nil : query_params)
          query_params[:synchronous] ? Result::Text.new(result_data) : Result::SingleObject.new(result_data)
        end
      end
    end
  end
end

# 17.Persist custom data
# 18.Fetch queued items from queue
# 20.List Task for a User
# 21. Fetch Task details
# 22. Submit Task
# 23. Control Process
# engine monitor worker
# 24. Lookup Queued Item
# 25. Reorder Queued Items
# 26. Bulk Reorder Queued Items
# 27. Queue Item (Add an item to a Queue)
#
# Required Input:
# Optional Input:
# 28.List all queues
# 29. Portlet Version
# 30. Plugin Version
# 31. Restart Work Order from a Step
# 32. Delete element from a Managed Queue
#
