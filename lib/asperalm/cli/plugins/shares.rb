require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      class Shares < BasicAuthPlugin
        def declare_options; end

        def action_list; Node.common_actions.clone.concat([ ]);end

        def execute_action
          api_shares=Rest.new(Main.tool.options.get_option_mandatory(:url)+'/node_api',{:auth=>{:type=>:basic,:user=>Main.tool.options.get_option_mandatory(:username), :password=>Main.tool.options.get_option_mandatory(:password)}})
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when *Node.common_actions; return Node.execute_common(command,api_shares)
          else
            raise "ERROR, unknown command: [#{command}]"
          end
        end
      end
    end
  end # Cli
end # Asperalm
