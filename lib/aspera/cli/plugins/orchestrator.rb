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
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)
            error = nil
            urls.each do |base_url|
              next unless base_url.match?('https?://')
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
        # @param app_url [Wizard] The wizard object
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

        def initialize(**_)
          super
          @api_orch = nil
          options.declare(:result, "Specify result value as: 'work_step:parameter'")
          options.declare(:synchronous, 'Wait for completion', allowed: Allowed::TYPES_BOOLEAN, default: false)
          options.declare(:ret_style, 'How return type is requested in api', allowed: %i[header arg ext], default: :arg)
          options.declare(:auth_style, 'Authentication type', allowed: %i[arg_pass head_basic apikey], default: :head_basic)
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
          call_args = {operation: 'GET', subpath: "api/#{endpoint}", ret: :both}
          ret_style = options.get_option(:ret_style, mandatory: true) if ret_style.nil?
          call_args[:query] = args unless args.nil?
          unless format.nil?
            case ret_style
            when :header
              call_args[:headers] = {'Accept' => "application/#{format}"}
            when :arg
              call_args[:query] ||= {}
              call_args[:query][:format] = format
            when :ext
              call_args[:subpath] = "#{call_args[:subpath]}.#{format}"
            else Aspera.error_unexpected_value(ret_style)
            end
          end
          data, resp = @api_orch.call(**call_args)
          return resp if http
          result = format.eql?('xml') ? XmlSimple.xml_in(resp.body, {'ForceArray' => xml_arrays}) : data
          Log.dump(:data, result)
          return result
        end

        ACTIONS = %i[health info workflows workorders workstep plugins processes monitors].freeze

        def execute_action
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

          command1 = options.get_next_command(ACTIONS)
          case command1
          when :health
            nagios = Nagios.new
            begin
              info = call_ao('remote_node_ping', format: 'xml', xml_arrays: false)
              nagios.add_ok('api', 'accessible')
              nagios.check_product_version('api', 'orchestrator', info['orchestrator-version'])
            rescue StandardError => e
              nagios.add_critical('node api', e.to_s)
            end
            Main.result_object_list(nagios.status_list)
          # 14. Ping the remote Instance
          when :info
            result = call_ao('remote_node_ping', format: 'xml', xml_arrays: false)
            return Main.result_single_object(result)
          # 12. Orchestrator Background Process status
          when :processes
            # TODO: Bug ? API has only XML format
            result = call_ao('processes_status', format: 'xml')
            return Main.result_object_list(result['process'])
          # 13. Orchestrator Monitor
          when :monitors
            result = call_ao('monitor_snapshot')
            return Main.result_single_object(result['monitor'])
          when :plugins
            # TODO: Bug ? only json format on url
            result = call_ao('plugin_version')
            return Main.result_object_list(result['Plugin'])
          when :workflows
            command = options.get_next_command(%i[list status inputs details start export workorders outputs])
            case command
            # 1. List all available workflows on the system
            when :list
              result = call_ao('workflows_list')
              return Main.result_object_list(result['workflows']['workflow'], fields: %w[id portable_id name published_status published_revision_id latest_revision_id last_modification])
            # 2.1 Initiate a workorder - Asynchronous
            # 2.2 Initiate a workorder - Synchronous
            when :start
              result = {
                type: :single_object,
                data: nil
              }
              call_params = {format: :json}
              wf_id = instance_identifier
              # get external parameters if any
              options.get_next_argument('external_parameters', mandatory: false, validation: Hash, default: {}).each do |name, value|
                call_params["external_parameters[#{name}]"] = value
              end
              # synchronous call ?
              call_params['synchronous'] = true if options.get_option(:synchronous, mandatory: true)
              # expected result for synchro call ?
              result_location = options.get_option(:result)
              unless result_location.nil?
                result[:type] = :status
                fields = result_location.split(':')
                raise Cli::BadArgument, "Expects: work_step:result_name : #{result_location}" if fields.length != 2
                call_params['explicit_output_step'] = fields[0]
                call_params['explicit_output_variable'] = fields[1]
                # implicitly, call is synchronous
                call_params['synchronous'] = true
              end
              result[:type] = :text if call_params['synchronous']
              result[:data] = call_ao("initiate/#{wf_id}", args: call_params)
              return result
            # 3. Fetch input specification for a workflow
            when :inputs
              result = call_ao("workflow_inputs_spec/#{instance_identifier}")
              return Main.result_single_object(result['workflow_inputs_spec'])
            # 4. Check the running status for all workflows
            # 5. Check the running status for a particular workflow
            when :status
              wf_id = instance_identifier
              result = call_ao(wf_id.eql?(SpecialValues::ALL) ? 'workflows_status' : "workflows_status/#{wf_id}")
              return Main.result_object_list(result['workflows']['workflow'])
            # 6. Check the detailed running status for a particular workflow
            when :details
              result = call_ao("workflow_details/#{instance_identifier}")
              return Main.result_object_list(result['workflows']['workflow']['statuses'])
            # 15. Fetch output specification for a particular work flow
            when :outputs
              result = call_ao("workflow_outputs_spec/#{instance_identifier}")
              return Main.result_object_list(result['workflow_outputs_spec']['output'])
            # 19.Fetch all workorders from a workflow
            when :workorders
              result = call_ao("work_orders_list/#{instance_identifier}")
              return Main.result_object_list(result['work_orders'])
            when :export
              result = call_ao("export_workflow/#{instance_identifier}", format: nil, http: true)
              return Main.result_text(result.body)
            end
          when :workorders
            command = options.get_next_command(%i[status cancel reset output])
            case command
            # 7. Check the status for a particular work order
            when :status
              wo_id = instance_identifier
              result = call_ao("work_order_status/#{wo_id}")
              return Main.result_single_object(result['work_order'])
            # 9. Cancel a Work Order
            when :cancel
              wo_id = instance_identifier
              result = call_ao("work_order_cancel/#{wo_id}")
              return Main.result_single_object(result['work_order'])
            # 11. Reset a Work order
            when :reset
              wo_id = instance_identifier
              result = call_ao("work_order_reset/#{wo_id}")
              return Main.result_single_object(result['work_order'])
            # 16. Fetch output of a work order
            when :output
              wo_id = instance_identifier
              result = call_ao("work_order_output/#{wo_id}", format: 'xml')
              return Main.result_object_list(result['variable'])
            end
          when :workstep
            command = options.get_next_command(%i[status cancel])
            case command
            # 8. Check the status of a Step
            when :status
              ws_id = instance_identifier
              result = call_ao("work_step_status/#{ws_id}")
              return Main.result_single_object(result)
            # 10. Cancel a Work Step
            when :cancel
              ws_id = instance_identifier
              result = call_ao("work_step_cancel/#{ws_id}")
              return Main.result_single_object(result)
            end
          else Aspera.error_unexpected_value(command)
          end
        end
        private :call_ao
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
