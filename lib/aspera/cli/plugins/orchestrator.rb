# frozen_string_literal: true

require 'aspera/cli/plugins/node'
require 'xmlsimple'

module Aspera
  module Cli
    module Plugins
      class Orchestrator < Aspera::Cli::BasicAuthPlugin
        class << self
          STANDARD_PATH = '/aspera/orchestrator'
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)

            urls.each do |base_url|
              next unless base_url.match?('https?://')
              api = Rest.new(base_url: base_url)
              test_endpoint = 'api/remote_node_ping'
              result = api.read(test_endpoint, {format: :json})
              next unless result[:data]['remote_orchestrator_info']
              url = result[:http].uri.to_s
              return {
                version: result[:data]['remote_orchestrator_info']['orchestrator-version'],
                url:     url[0..url.index(test_endpoint) - 2]
              }
            rescue StandardError => e
              Log.log.debug{"detect error: #{e}"}
            end
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
              test_args:    'workflow list'
            }
          end
        end

        def initialize(env)
          super(env)
          options.declare(:result, "Specify result value as: 'work_step:parameter'")
          options.declare(:synchronous, 'Wait for completion', values: :bool, default: :no)
          options.declare(:ret_style, 'How return type is requested in api', values: %i[header arg ext], default: :arg)
          options.declare(:auth_style, 'Authentication type', values: %i[arg_pass head_basic apikey], default: :head_basic)
          options.parse_options!
        end

        ACTIONS = %i[health info workflow plugins processes].freeze

        # for JSON format: add extension ".json" or add url parameter: format=json or Accept: application/json
        # id can be: a parameter id=x, or at the end of url /id, for workflows: work_order[workflow_id]=wf_id
        #        def call_API_orig(endpoint,id=nil,url_params={format: :json},accept=nil)
        #          # calls are GET
        #          call_args={operation: 'GET',subpath: endpoint}
        #          # specify id if necessary
        #          call_args[:subpath]=call_args[:subpath]+'/'+id unless id.nil?
        #          unless url_params.nil?
        #            if url_params.has_key?(:format)
        #              call_args[:headers]={'Accept'=>'application/'+url_params[:format].to_s}
        #            end
        #            call_args[:headers]={'Accept'=>accept} unless accept.nil?
        #            # add params if necessary
        #            call_args[:url_params]=url_params
        #          end
        #          return @api_orch.call(call_args)
        #        end

        def call_ao(endpoint, opt={})
          opt[:prefix] = 'api' unless opt.key?(:prefix)
          # calls are GET
          call_args = {operation: 'GET', subpath: endpoint}
          # specify prefix if necessary
          call_args[:subpath] = "#{opt[:prefix]}/#{call_args[:subpath]}" unless opt[:prefix].nil?
          # specify id if necessary
          call_args[:subpath] = "#{call_args[:subpath]}/#{opt[:id]}" if opt.key?(:id)
          call_type = options.get_option(:ret_style, mandatory: true)
          call_type = opt[:ret_style] if opt.key?(:ret_style)
          format = 'json'
          format = opt[:format] if opt.key?(:format)
          call_args[:url_params] = opt[:args] unless opt[:args].nil?
          unless format.nil?
            case call_type
            when :header
              call_args[:headers] = {'Accept' => 'application/' + format}
            when :arg
              call_args[:url_params] ||= {}
              call_args[:url_params][:format] = format
            when :ext
              call_args[:subpath] = "#{call_args[:subpath]}.#{format}"
            else raise 'unexpected'
            end
          end
          result = @api_orch.call(call_args)
          result[:data] = XmlSimple.xml_in(result[:http].body, opt[:xml_opt] || {'ForceArray' => true}) if format.eql?('xml')
          Log.dump(:data, result[:data])
          return result
        end

        def execute_action
          rest_params = {base_url: options.get_option(:url, mandatory: true)}
          case options.get_option(:auth_style, mandatory: true)
          when :arg_pass
            rest_params[:auth] = {
              type:      :url,
              url_creds: {
                'login'    => options.get_option(:username, mandatory: true),
                'password' => options.get_option(:password, mandatory: true) }}
          when :head_basic
            rest_params[:auth] = {
              type:     :basic,
              username: options.get_option(:username, mandatory: true),
              password: options.get_option(:password, mandatory: true) }
          when :apikey
            raise 'Not implemented'
          end

          @api_orch = Rest.new(rest_params)

          command1 = options.get_next_command(ACTIONS)
          case command1
          when :health
            nagios = Nagios.new
            begin
              info = call_ao('remote_node_ping', format: 'xml', xml_opt: {'ForceArray' => false})[:data]
              nagios.add_ok('api', 'accessible')
              nagios.check_product_version('api', 'orchestrator', info['orchestrator-version'])
            rescue StandardError => e
              nagios.add_critical('node api', e.to_s)
            end
            return nagios.result
          when :info
            result = call_ao('remote_node_ping', format: 'xml', xml_opt: {'ForceArray' => false})[:data]
            return {type: :single_object, data: result}
          when :processes
            # TODO: Jira ? API has only XML format
            result = call_ao('processes_status', format: 'xml')[:data]
            return {type: :object_list, data: result['process']}
          when :plugins
            # TODO: Jira ? only json format on url
            result = call_ao('plugin_version')[:data]
            return {type: :object_list, data: result['Plugin']}
          when :workflow
            command = options.get_next_command(%i[list status inputs details start export])
            unless [:list].include?(command)
              wf_id = instance_identifier
            end
            case command
            when :status
              call_opts = {}
              call_opts[:id] = wf_id unless wf_id.eql?(ExtendedValue::ALL)
              result = call_ao('workflows_status', call_opts)[:data]
              return {type: :object_list, data: result['workflows']['workflow']}
            when :list
              result = call_ao('workflows_list', id: 0)[:data]
              return {
                type:   :object_list,
                data:   result['workflows']['workflow'],
                fields: %w[id portable_id name published_status published_revision_id latest_revision_id last_modification]
              }
            when :details
              result = call_ao('workflow_details', id: wf_id)[:data]
              return {type: :object_list, data: result['workflows']['workflow']['statuses']}
            when :inputs
              result = call_ao('workflow_inputs_spec', id: wf_id)[:data]
              return {type: :single_object, data: result['workflow_inputs_spec']}
            when :export
              result = call_ao('export_workflow', id: wf_id, format: nil)[:http]
              return {type: :text, data: result.body}
            when :start
              result = {
                type: :single_object,
                data: nil
              }
              call_params = {format: :json}
              override_accept = nil
              # get external parameters if any
              options.get_next_argument('external_parameters', mandatory: false, type: Hash, default: {}).each do |name, value|
                call_params["external_parameters[#{name}]"] = value
              end
              # synchronous call ?
              call_params['synchronous'] = true if options.get_option(:synchronous, mandatory: true)
              # expected result for synchro call ?
              result_location = options.get_option(:result)
              unless result_location.nil?
                result[:type] = :status
                fields = result_location.split(':')
                raise CliBadArgument, "Expects: work_step:result_name : #{result_location}" if fields.length != 2
                call_params['explicit_output_step'] = fields[0]
                call_params['explicit_output_variable'] = fields[1]
                # implicitly, call is synchronous
                call_params['synchronous'] = true
              end
              if call_params['synchronous']
                result[:type] = :text
                override_accept = 'text/plain'
              end
              result[:data] = call_ao('initiate', id: wf_id, args: call_params, accept: override_accept)[:data]
              return result
            end # wf command
          else raise "ERROR, unknown command: [#{command}]"
          end # case command
        end # execute_action
      end # Orchestrator
    end # Plugins
  end # Cli
end # Aspera
