require 'asperalm/cli/plugins/node'
require 'xmlsimple'

module Asperalm
  module Cli
    module Plugins
      class Orchestrator < BasicAuthPlugin

        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.instance.options.add_opt_simple(:params,"parameters hash table, use @json:{\"param\":\"value\"}")
          Main.instance.options.add_opt_simple(:result,"specify result value as: 'work step:parameter'")
          Main.instance.options.add_opt_simple(:id,"workflow identifier")
          Main.instance.options.add_opt_boolean(:synchronous,"work step:parameter expected as result")
          Main.instance.options.set_option(:params,{})
          Main.instance.options.set_option(:synchronous,:no)
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
          @api_orch=Rest.new({
            :base_url       => Main.instance.options.get_option(:url,:mandatory),
            :auth_type      => :url,
            :auth_url_creds => {
            'login'   =>Main.instance.options.get_option(:username,:mandatory),
            'password'=>Main.instance.options.get_option(:password,:mandatory) }})

          # auth can be in url or basic
          #          @api_orch=Rest.new({
          #            :base_url=>Main.instance.options.get_option(:url,:mandatory),
          #            :auth_type=>:basic,
          #            :basic_username=>Main.instance.options.get_option(:username,:mandatory),
          #            :basic_password=>Main.instance.options.get_option(:password,:mandatory)})

          command1=Main.instance.options.get_next_argument('command',action_list)
          case command1
          when :info
            result=call_API("logon",nil,nil,nil)
            version='unknown'
            if m=result[:http].body.match(/\(v([0-9.-]+)\)/)
              version=m[1]
            end
            return {:type=>:single_object,:data=>{'version'=>version}}
          when :processes
            # TODO: json format is not respected in AO
            result=call_API("api/processes_status",nil,nil,:xml)
            res_s=XmlSimple.xml_in(result[:http].body, {"ForceArray" => true})
            return {:type=>:object_list,:data=>res_s["process"]}
          when :plugins
            result=call_API("api/plugin_version")[:data]
            return {:type=>:object_list,:data=>result['Plugin']}
          when :workflow
            command=Main.instance.options.get_next_argument('command',[:list, :status, :inputs, :details, :start])
            unless [:list, :status].include?(command)
              wf_id=Main.instance.options.get_option(:id,:mandatory)
            end
            case command
            when :status
              result=call_API("api/workflows_status")[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow']}
            when :list
              result=call_API("workflow_reporter/workflows_list/0")[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow'],:fields=>["id","portable_id","name","published_status","published_revision_id","latest_revision_id","last_modification"]}
            when :details
              result=call_API("api/workflow_details",wf_id)[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow']['statuses']}
            when :inputs
              result=call_API("api/workflow_inputs_spec",wf_id)[:data]
              return {:type=>:single_object,:data=>result['workflow_inputs_spec']}
            when :start
              result={
                :type=>:single_object,
                :data=>nil
              }
              call_params={}
              # set external parameters if any
              Main.instance.options.get_option(:params,:mandatory).each do |name,value|
                call_params["external_parameters[#{name}]"] = value
              end
              # synchronous call ?
              call_params["synchronous"]=true if Main.instance.options.get_option(:synchronous,:mandatory)
              # expected result for synchro call ?
              expected=Main.instance.options.get_option(:result,:optional)
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
        end # execute_action
      end # Orchestrator
    end # Plugins
  end # Cli
end # Asperalm
