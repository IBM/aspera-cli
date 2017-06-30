require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      class Orchestrator < BasicAuthPlugin
        def declare_options; end

        def action_list; [:workflow];end

        def execute_action
          inlinecreds={'login'=>Main.tool.options.get_option_mandatory(:username), 'password'=>Main.tool.options.get_option_mandatory(:password)}
          api_orch=Rest.new(Main.tool.options.get_option_mandatory(:url),{:auth=>{:type=>:url,:url_creds=>inlinecreds}})
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :workflow
            command=Main.tool.options.get_next_arg_from_list('command',[:list])
            case command
            when :list
              wf_list_resp=api_orch.call({:operation=>'GET',:subpath=>"workflow_reporter/workflows_list/0",:headers=>{'Accept'=>'application/xml'}})
              wf_list=XmlSimple.xml_in(wf_list_resp[:http].body, {"ForceArray" => true})
              # TODO: parse xml
              return {:type=>:hash_array,:data=>wf_list['workflow'],:fields=>["id","name","published_status","published_revision_id","latest_revision_id","last_modification"]}
            end
          else
            raise "ERROR, unknown command: [#{command}]"
          end
        end
      end
    end
  end # Cli
end # Asperalm
