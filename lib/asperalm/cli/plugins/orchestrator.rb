require 'asperalm/cli/plugins/node'
require 'xmlsimple'

module Asperalm
  module Cli
    module Plugins
      class Orchestrator < BasicAuthPlugin
        def initialize(env)
          super(env)
          self.options.add_opt_simple(:params,"parameters hash table, use @json:{\"param\":\"value\"}")
          self.options.add_opt_simple(:result,"specify result value as: 'work step:parameter'")
          self.options.add_opt_boolean(:synchronous,"work step:parameter expected as result")
          self.options.set_option(:params,{})
          self.options.set_option(:synchronous,:no)
          self.options.parse_options!
        end

        def action_list; [:info, :workflow, :plugins, :processes];end

        # one can either add extnsion ".json" or add url parameter: format=json
        # id can be a parameter id=x, or at the end of url, for workflows: work_order[workflow_id]=wf_id
        def call_API(endpoint,id=nil,url_params={:format=>:json},accept=nil)
          # calls are GET
          call_definition={:operation=>'GET',:subpath=>endpoint}
          # specify id if necessary
          call_definition[:subpath]=call_definition[:subpath]+'/'+id unless id.nil?
          unless url_params.nil?
            if url_params.has_key?(:format)
              call_definition[:headers]={'Accept'=>'application/'+url_params[:format].to_s}
            end
            call_definition[:headers]={'Accept'=>accept} unless accept.nil?
            # add params if necessary
            call_definition[:url_params]=url_params
          end
          return @api_orch.call(call_definition)
        end

        def execute_action
          @api_orch=Rest.new({
            :base_url       => self.options.get_option(:url,:mandatory),
            # auth can be :url or :basic
            :auth => {
            :type      => :url,
            :url_creds => {
            'login'   =>self.options.get_option(:username,:mandatory),
            'password'=>self.options.get_option(:password,:mandatory) }}})

          command1=self.options.get_next_command(action_list)
          case command1
          when :info
            result=call_API('logon',nil,nil)
            version='unknown'
            if m=result[:http].body.match(/\(v([0-9.-]+)\)/)
              version=m[1]
            end
            return {:type=>:single_object,:data=>{'version'=>version}}
          when :processes
            # TODO: json format is not respected in AO
            result=call_API('api/processes_status',nil,{:format=>:xml})
            res_s=XmlSimple.xml_in(result[:http].body, {"ForceArray" => true})
            return {:type=>:object_list,:data=>res_s["process"]}
          when :plugins
            result=call_API('api/plugin_version')[:data]
            return {:type=>:object_list,:data=>result['Plugin']}
          when :workflow
            command=self.options.get_next_command([:list, :status, :inputs, :details, :start])
            unless [:list, :status].include?(command)
              wf_id=self.options.get_option(:id,:mandatory)
            end
            case command
            when :status
              result=call_API('api/workflows_status')[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow']}
            when :list
              result=call_API('workflow_reporter/workflows_list/0')[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow'],:fields=>["id","portable_id","name","published_status","published_revision_id","latest_revision_id","last_modification"]}
            when :details
              result=call_API('api/workflow_details',wf_id)[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow']['statuses']}
            when :inputs
              result=call_API('api/workflow_inputs_spec',wf_id)[:data]
              return {:type=>:single_object,:data=>result['workflow_inputs_spec']}
            when :start
              result={
                :type=>:single_object,
                :data=>nil
              }
              call_params={:format=>:json}
              override_accept=nil
              # set external parameters if any
              self.options.get_option(:params,:mandatory).each do |name,value|
                call_params["external_parameters[#{name}]"] = value
              end
              # synchronous call ?
              call_params['synchronous']=true if self.options.get_option(:synchronous,:mandatory)
              # expected result for synchro call ?
              expected=self.options.get_option(:result,:optional)
              unless expected.nil?
                result[:type] = :status
                fields=expected.split(/:/)
                raise "Expects: work_step:result_name format, but got #{expected}" if fields.length != 2
                call_params['explicit_output_step']=fields[0]
                call_params['explicit_output_variable']=fields[1]
                # implicitely, call is synchronous
                call_params['synchronous']=true
              end
              if call_params['synchronous']
                result[:type]=:text
                override_accept='text/plain'
              end
              result[:data]=call_API('api/initiate',wf_id,call_params,override_accept)[:data]
              return result
            end # wf command
          else raise "ERROR, unknown command: [#{command}]"
          end # case command
        end # execute_action
      end # Orchestrator
    end # Plugins
  end # Cli
end # Asperalm
