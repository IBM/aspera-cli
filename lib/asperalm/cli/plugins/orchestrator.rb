require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      class Orchestrator < BasicAuthPlugin
        def declare_options; end

        def action_list; [:workflow,:plugins];end

        def execute_action
          inlinecreds={'login'=>Main.tool.options.get_option_mandatory(:username), 'password'=>Main.tool.options.get_option_mandatory(:password), 'format'=>'json'}
          api_orch=Rest.new(Main.tool.options.get_option_mandatory(:url),{:auth=>{:type=>:url,:url_creds=>inlinecreds}})
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :plugins
            wf_list=api_orch.list("api/plugin_version")[:data]
            return {:type=>:hash_array,:data=>wf_list['Plugin']}
          when :workflow
            command=Main.tool.options.get_next_arg_from_list('command',[:list, :status, :id])
            puts "CCCC=#{command}"
            case command
            when :status
              wf_list=api_orch.list("api/workflows_status")[:data]
              return {:type=>:hash_array,:data=>wf_list['workflows']['workflow']}
            when :list
              wf_list=api_orch.list("workflow_reporter/workflows_list/0")[:data]
              return {:type=>:hash_array,:data=>wf_list['workflows']['workflow'],:fields=>["id","name","published_status","published_revision_id","latest_revision_id","last_modification"]}
            when :id
              wf_id=Main.tool.options.get_next_arg_value('workflow id')
              command=Main.tool.options.get_next_arg_from_list('command',[:inputs,:status])
              case command
              when :status
                inputs=api_orch.list("api/workflow_details/#{wf_id}")[:data]
                return {:type=>:hash_array,:data=>inputs['workflows']['workflow']['statuses']}
              when :inputs
                inputs=api_orch.list("api/workflow_inputs_spec/#{wf_id}")[:data]
                return {:type=>:key_val_list,:data=>inputs['workflow_inputs_spec']}
              end
            else
              raise "ERROR, unknown command: [#{command}]"
            end
          end
        end
      end
    end
  end # Cli
end # Asperalm
