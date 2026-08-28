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
              api = Rest.new(base_url: base_url)
              data, http = api.read(TEST_ENDPOINT, query: {format: :json}, ret: :both)
              next unless data['remote_orchestrator_info']
              url = http.uri.to_s
              return {
                version: data['remote_orchestrator_info']['orchestrator-version'],
                url:     url[0..url.index(TEST_ENDPOINT) - 2]
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
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

        option :result, "Specify result value as: 'work_step:parameter'"
        option :synchronous, 'Wait for completion', allowed: Allowed::TYPES_BOOLEAN, default: false
        option :ret_style,  'How return type is requested in api', allowed: %i[header arg ext], default: :arg
        option :auth_style, 'Authentication type', allowed: %i[arg_pass head_basic apikey], default: :head_basic

        def initialize(**_)
          super
          @api_orch = nil
          options.parse_options!
        end

        # Call orchestrator API, it's a bit special
        # @param endpoint   [String]  the endpoint to call
        # @param ret_style  [Symbol]  the return style, :header, :arg, :ext(extension)
        # @param format     [String]  the format to request, 'json', 'xml', nil
        # @param args       [Hash]    the arguments to pass
        # @param xml_arrays [Boolean] if true, force arrays in xml parsing
        # @param http       [Boolean] if true, returns the HttpResponse, else
        def call_ao(endpoint, ret_style: nil, format: 'json', args: nil, xml_arrays: true, http: false)
          # calls are all GET
          call_args = {operation: 'GET', subpath: "api/#{endpoint}", ret: :both, query: {}}
          ret_style = options.get_option(:ret_style, mandatory: true) if ret_style.nil?
          call_args[:query].merge!(args) unless args.nil?
          unless format.nil?
            case ret_style
            when :header
              call_args[:headers] = {'Accept' => "application/#{format}"}
            when :arg
              call_args[:query][:format] = format
            when :ext
              call_args[:subpath] = "#{call_args[:subpath]}.#{format}"
            else Aspera.error_unexpected_value(ret_style)
            end
          end
          add_query = options.get_option(:query)
          call_args[:query].merge!(add_query.symbolize_keys) unless add_query.nil?
          data, resp = @api_orch.call(**call_args)
          return resp if http
          result = format.eql?('xml') ? XmlSimple.xml_in(resp.body, {'ForceArray' => xml_arrays}) : data
          Log.dump(:data, result)
          return result
        end

        private :call_ao

        # --- DSL ---

        command :health,     description: 'Check Orchestrator API health',               setup: :setup_api
        command :info,       description: 'Ping the remote Orchestrator instance',       setup: :setup_api, handler: ->{Result::SingleObject.new(call_ao('remote_node_ping', format: 'xml', xml_arrays: false))}
        command :processes,  description: 'Show Orchestrator background process status', setup: :setup_api, handler: ->{Result::ObjectList.new(call_ao('processes_status', format: 'xml')['process'])}
        command :monitors,   description: 'Show Orchestrator monitor snapshot',          setup: :setup_api, handler: ->{Result::SingleObject.new(call_ao('monitor_snapshot')['monitor'])}
        command :plugins,    description: 'Show Orchestrator plugin versions',           setup: :setup_api, handler: ->{Result::ObjectList.new(call_ao('plugin_version')['Plugin'])}
        command :workflows,  description: 'Manage workflows',                            setup: :setup_api
        command :workorders, description: 'Manage work orders',                          setup: :setup_api
        command :workstep,   description: 'Manage work steps',                           setup: :setup_api

        commands_under(:workflows) do
          command(:list, description: 'List all workflows', handler: lambda do
            Result::ObjectList.new(
              call_ao('workflows_list')['workflows']['workflow'],
              fields: %w[id portable_id name published_status published_revision_id latest_revision_id last_modification]
            )
          end)
          command(:status, description: 'Check running status of workflow(s)', handler: lambda do
            wf_id = options.instance_identifier
            Result::ObjectList.new(call_ao(wf_id.eql?(SpecialValues::ALL) ? 'workflows_status' : "workflows_status/#{wf_id}")['workflows']['workflow'])
          end)
          command :inputs,     description: 'Fetch input specification for a workflow',          handler: lambda{Result::SingleObject.new(call_ao("workflow_inputs_spec/#{options.instance_identifier}")['workflow_inputs_spec'])}
          command :details,    description: 'Check detailed running status of a workflow',       handler: lambda{Result::ObjectList.new(call_ao("workflow_details/#{options.instance_identifier}")['workflows']['workflow']['statuses'])}
          command :start,      description: 'Initiate a work order (sync or async)'
          command :export,     description: 'Export a workflow',                                 handler: lambda{Result::Text.new(call_ao("export_workflow/#{options.instance_identifier}", format: nil, http: true).body)}
          command :workorders, description: 'Fetch all work orders from a workflow',             handler: lambda{Result::ObjectList.new(call_ao("work_orders_list/#{options.instance_identifier}")['work_orders'])}
          command :outputs,    description: 'Fetch output specification for a workflow',         handler: lambda{Result::ObjectList.new(call_ao("workflow_outputs_spec/#{options.instance_identifier}")['workflow_outputs_spec']['output'])}
        end

        commands_under(:workorders) do
          command :status, description: 'Check the status of a work order', handler: lambda{Result::SingleObject.new(call_ao("work_order_status/#{options.instance_identifier}")['work_order'])}
          command :cancel, description: 'Cancel a work order',              handler: lambda{Result::SingleObject.new(call_ao("work_order_cancel/#{options.instance_identifier}")['work_order'])}
          command :reset,  description: 'Reset a work order',               handler: lambda{Result::SingleObject.new(call_ao("work_order_reset/#{options.instance_identifier}")['work_order'])}
          command :output, description: 'Fetch output of a work order',     handler: lambda{Result::ObjectList.new(call_ao("work_order_output/#{options.instance_identifier}", format: 'xml')['variable'])}
        end

        commands_under(:workstep) do
          command :status, description: 'Check the status of a work step', handler: lambda{Result::SingleObject.new(call_ao("work_step_status/#{options.instance_identifier}"))}
          command :cancel, description: 'Cancel a work step',              handler: lambda{Result::SingleObject.new(call_ao("work_step_cancel/#{options.instance_identifier}"))}
        end

        # --- setup ---

        # Build the Orchestrator REST API from CLI options.
        # @return [Hash] ctx with no extra keys (stores api in @api_orch instance var)
        def setup_api
          auth_params =
            case options.get_option(:auth_style, mandatory: true)
            when :arg_pass
              {
                type:      :url,
                url_query: {
                  'login'    => options.get_option(:username, mandatory: true),
                  'password' => options.get_option(:password, mandatory: true)
                }
              }
            when :head_basic
              {
                type:     :basic,
                username: options.get_option(:username, mandatory: true),
                password: options.get_option(:password, mandatory: true)
              }
            when :apikey
              Aspera.error_not_implemented
            end
          @api_orch = Rest.new(
            base_url: options.get_option(:url, mandatory: true),
            auth: auth_params
          )
          {}
        end

        def handle_health
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
        def handle_workflows_start
          call_params = {format: :json}
          wf_id = options.instance_identifier
          # get external parameters if any
          options.get_next_argument('external_parameters', mandatory: false, validation: Hash, default: {}).each do |name, value|
            call_params["external_parameters[#{name}]"] = value
          end
          # synchronous call ?
          call_params['synchronous'] = true if options.get_option(:synchronous, mandatory: true)
          # expected result for synchro call ?
          result_location = options.get_option(:result)
          unless result_location.nil?
            fields = result_location.split(':')
            raise Cli::BadArgument, "Expects: work_step:result_name : #{result_location}" if fields.length != 2
            call_params['explicit_output_step'] = fields[0]
            call_params['explicit_output_variable'] = fields[1]
            # implicitly, call is synchronous
            call_params['synchronous'] = true
          end
          result_data = call_ao("initiate/#{wf_id}", args: call_params)
          call_params['synchronous'] ? Result::Text.new(result_data) : Result::SingleObject.new(result_data)
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
