require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'
require 'xmlsimple'

module Asperalm
  module Cli
    module Plugins
      class Orchestrator < BasicAuthPlugin
        SYNCHRONOUS_VALUES=[:yes,:no]

        alias super_declare_options declare_options

        def declare_options
          super_declare_options
          Main.tool.options.set_option(:params,{})
          Main.tool.options.set_option(:synchronous,:no)
          Main.tool.options.add_opt_simple(:params,"parameters hash table, use @json:{\"param\":\"value\"}")
          Main.tool.options.add_opt_simple(:result,"specify result value as: 'work step:parameter'")
          Main.tool.options.add_opt_list(:synchronous,SYNCHRONOUS_VALUES,"work step:parameter expected as result")
        end

        def action_list; [:info, :workflow, :plugins, :processes];end

        # one can either add extnsion ".json" or add url parameter: format=json
        # id can be a parameter id=x, or at the end of url, for workflows: work_order[workflow_id]=wf_id
        def call_API(endpoint,id=nil,url_params=nil,format=:json)
          # calls are GET
          call_definition={:operation=>'GET',:subpath=>endpoint}
          # specify id if necessary
          call_definition[:subpath]=call_definition[:subpath]+'/'+id if !id.nil?
          # set format if necessary
          if !format.nil?
            url_params={} if url_params.nil?
            url_params['format']=format
            # needs a patch to work ...
            #call_definition[:subpath]=call_definition[:subpath]+'.'+format.to_s
            call_definition[:headers]={'Accept'=>'application/'+format.to_s}
          end
          # add params if necessary
          call_definition[:url_params]=url_params if !url_params.nil?
          return @api_orch.call(call_definition)
        end

        def execute_action
          @api_orch=Rest.new(Main.tool.options.get_option(:url,:mandatory),{:auth=>{:type=>:url,:url_creds=>{
            'login'=>Main.tool.options.get_option(:username,:mandatory),
            'password'=>Main.tool.options.get_option(:password,:mandatory) }}})

          # auth can be in url or basic
          #          @api_orch=Rest.new(Main.tool.options.get_option(:url,:mandatory),{:auth=>{
          #            :type=>:basic,
          #            :username=>Main.tool.options.get_option(:username,:mandatory),
          #            :password=>Main.tool.options.get_option(:password,:mandatory)}})

          command1=Main.tool.options.get_next_argument('command',action_list)
          case command1
          when :info
            result=call_API("logon",nil,nil,nil)
            version='unknown'
            if m=result[:http].body.match(/\(v([0-9.-]+)\)/)
              version=m[1]
            end
            return {:type=>:key_val_list,:data=>{'version'=>version}}
          when :processes
            # TODO: json format is not respected in AO
            result=call_API("api/processes_status",nil,nil,:xml)
            res_s=XmlSimple.xml_in(result[:http].body, {"ForceArray" => true})
            return {:type=>:hash_array,:data=>res_s["process"]}
          when :plugins
            result=call_API("api/plugin_version")[:data]
            return {:type=>:hash_array,:data=>result['Plugin']}
          when :workflow
            command=Main.tool.options.get_next_argument('command',[:list, :status, :id])
            case command
            when :status
              result=call_API("api/workflows_status")[:data]
              return {:type=>:hash_array,:data=>result['workflows']['workflow']}
            when :list
              result=call_API("workflow_reporter/workflows_list/0")[:data]
              return {:type=>:hash_array,:data=>result['workflows']['workflow'],:fields=>["id","portable_id","name","published_status","published_revision_id","latest_revision_id","last_modification"]}
            when :id
              wf_id=Main.tool.options.get_next_argument('workflow id')
              command=Main.tool.options.get_next_argument('command',[:inputs,:status,:start])
              case command
              when :status
                result=call_API("api/workflow_details",wf_id)[:data]
                return {:type=>:hash_array,:data=>result['workflows']['workflow']['statuses']}
              when :inputs
                result=call_API("api/workflow_inputs_spec",wf_id)[:data]
                return {:type=>:key_val_list,:data=>result['workflow_inputs_spec']}
              when :start
                result={
                  :type=>:key_val_list,
                  :data=>nil
                }
                call_params={}
                # set external parameters if any
                Main.tool.options.get_option(:params,:mandatory).each do |name,value|
                  call_params["external_parameters[#{name}]"] = value
                end
                # synchronous call ?
                call_params["synchronous"]=true if Main.tool.options.get_option(:synchronous,:mandatory).eql?(:yes)
                # expected result for synchro call ?
                expected=Main.tool.options.get_option(:result,:optional)
                if !expected.nil?
                  result[:type] = :status
                  fields=expected.split(/:/)
                  raise "Expects: work_step:result_name format, but got #{expected}" if fields.length != 2
                  call_params["explicit_output_step"]=fields[0]
                  call_params["explicit_output_variable"]=fields[1]
                  # implicitely, call is synchronous
                  call_params["synchronous"]=true
                end
                result[:data]=call_API("api/initiate",wf_id,call_params)[:data]
                return result
              end
            else
              raise "ERROR, unknown command: [#{command}]"
            end
          end
        end # execute_action
      end # Orchestrator
    end # Plugins
  end # Cli
end # Asperalm
