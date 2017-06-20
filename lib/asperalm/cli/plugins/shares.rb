require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      class Shares < BasicAuthPlugin
        attr_accessor :faspmanager
        def action_list; Node.common_actions.clone.concat([ ]);end

        def execute_action
          api_shares=Rest.new(self.options.get_option_mandatory(:url)+'/node_api',{:basic_auth=>{:user=>self.options.get_option_mandatory(:username), :password=>self.options.get_option_mandatory(:password)}})
          command=self.options.get_next_arg_from_list('command',action_list)
          case command
          when *Node.common_actions; return Node.execute_common(command,api_shares,self.options,@faspmanager)
          else
            raise "ERROR, unknown command: [#{command}]"
          end
        end
      end
    end
  end # Cli
end # Asperalm
