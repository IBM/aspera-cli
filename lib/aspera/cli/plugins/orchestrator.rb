require 'aspera/cli/plugins/node'
require 'xmlsimple'

module Aspera
  module Cli
    module Plugins
      class Orchestrator < BasicAuthPlugin
        def initialize(env)
          super(env)
          self.options.add_opt_simple(:params,"parameters hash table, use @json:{\"param\":\"value\"}")
          self.options.add_opt_simple(:result,"specify result value as: 'work step:parameter'")
          self.options.add_opt_boolean(:synchronous,"work step:parameter expected as result")
          self.options.add_opt_list(:ret_style,[:header,:arg,:ext],'how return type is requested in api')
          self.options.add_opt_list(:auth_style,[:arg_pass,:head_basic,:apikey],'authentication type')
          self.options.set_option(:params,{})
          self.options.set_option(:synchronous,:no)
          self.options.set_option(:ret_style,:arg)
          self.options.set_option(:auth_style,:head_basic)
          self.options.parse_options!
        end

        ACTIONS=[:info, :workflow, :plugins, :processes]

        # for JSON format: add extension ".json" or add url parameter: format=json or Accept: application/json
        # id can be: a parameter id=x, or at the end of url /id, for workflows: work_order[workflow_id]=wf_id
        def call_API_orig(endpoint,id=nil,url_params={:format=>:json},accept=nil)
          # calls are GET
          call_args={:operation=>'GET',:subpath=>endpoint}
          # specify id if necessary
          call_args[:subpath]=call_args[:subpath]+'/'+id unless id.nil?
          unless url_params.nil?
            if url_params.has_key?(:format)
              call_args[:headers]={'Accept'=>'application/'+url_params[:format].to_s}
            end
            call_args[:headers]={'Accept'=>accept} unless accept.nil?
            # add params if necessary
            call_args[:url_params]=url_params
          end
          return @api_orch.call(call_args)
        end

        def call_API(endpoint,opt={})
          opt[:prefix]='api' unless opt.has_key?(:prefix)
          # calls are GET
          call_args={:operation=>'GET',:subpath=>endpoint}
          # specify prefix if necessary
          call_args[:subpath]="#{opt[:prefix]}/#{call_args[:subpath]}" unless opt[:prefix].nil?
          # specify id if necessary
          call_args[:subpath]="#{call_args[:subpath]}/#{opt[:id]}" if opt.has_key?(:id)
          call_type=self.options.get_option(:ret_style,:mandatory)
          call_type=opt[:ret_style] if opt.has_key?(:ret_style)
          format='json'
          format=opt[:format] if opt.has_key?(:format)
          call_args[:url_params]=opt[:args] unless opt[:args].nil?
          unless format.nil?
            case call_type
            when :header
              call_args[:headers]={'Accept'=>'application/'+format}
            when :arg
              call_args[:url_params]||={}
              call_args[:url_params][:format]=format
            when :ext
              call_args[:subpath]="#{call_args[:subpath]}.#{format}"
            else raise "unexpected"
            end
          end
          result=@api_orch.call(call_args)
          result[:data]=XmlSimple.xml_in(result[:http].body, opt[:xml_opt]||{"ForceArray" => true}) if format.eql?('xml')
          return result
        end

        def execute_action
          rest_params={:base_url       => self.options.get_option(:url,:mandatory)}
          case self.options.get_option(:auth_style,:mandatory)
          when :arg_pass
            rest_params[:auth]={
              :type      => :url,
              :url_creds => {
              'login'      =>self.options.get_option(:username,:mandatory),
              'password'   =>self.options.get_option(:password,:mandatory) }}
          when :head_basic
            rest_params[:auth]={
              :type      => :basic,
              :username  =>self.options.get_option(:username,:mandatory),
              :password  =>self.options.get_option(:password,:mandatory) }
          when :apikey
            raise "Not implemented"
          end

          @api_orch=Rest.new(rest_params)

          command1=self.options.get_next_command(ACTIONS)
          case command1
          when :info
            result=call_API('remote_node_ping',format: 'xml', xml_opt: {"ForceArray" => false})
            return {:type=>:single_object,:data=>result[:data]}
            #            result=call_API('workflows',prefix: nil,format: nil)
            #            version='unknown'
            #            if m=result[:http].body.match(/\(Orchestrator v([1-9]+\.[\.0-9a-f\-]+)\)/)
            #              version=m[1]
            #            end
            #            return {:type=>:single_object,:data=>{'version'=>version}}
          when :processes
            # TODO: Jira ? API has only XML format
            result=call_API('processes_status',format: 'xml')
            return {:type=>:object_list,:data=>result[:data]['process']}
          when :plugins
            # TODO: Jira ? only json format on url
            result=call_API('plugin_version')[:data]
            return {:type=>:object_list,:data=>result['Plugin']}
          when :workflow
            command=self.options.get_next_command([:list, :status, :inputs, :details, :start, :export])
            unless [:list, :status].include?(command)
              wf_id=self.options.get_option(:id,:mandatory)
            end
            case command
            when :status
              result=call_API('workflows_status')[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow']}
            when :list
              result=call_API('workflows_list',id: 0)[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow'],:fields=>["id","portable_id","name","published_status","published_revision_id","latest_revision_id","last_modification"]}
            when :details
              result=call_API('workflow_details',id: wf_id)[:data]
              return {:type=>:object_list,:data=>result['workflows']['workflow']['statuses']}
            when :inputs
              result=call_API('workflow_inputs_spec',id: wf_id)[:data]
              return {:type=>:single_object,:data=>result['workflow_inputs_spec']}
            when :export
              result=call_API('export_workflow',id: wf_id,format: nil)[:http]
              return {:type=>:text,:data=>result.body}
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
              result[:data]=call_API('initiate',id: wf_id,args: call_params,accept: override_accept)[:data]
              return result
            end # wf command
          else raise "ERROR, unknown command: [#{command}]"
          end # case command
        end # execute_action
      end # Orchestrator
    end # Plugins
  end # Cli
end # Aspera
