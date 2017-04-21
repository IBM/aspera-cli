require 'asperalm/cli/plugin'
require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      class Shares < Plugin
        attr_accessor :faspmanager
        def set_options
          @option_parser.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          @option_parser.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          @option_parser.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
        end

        def execute_action
          api_shares=Rest.new(@option_parser.get_option_mandatory(:url)+'/node_api',{:basic_auth=>{:user=>@option_parser.get_option_mandatory(:username), :password=>@option_parser.get_option_mandatory(:password)}})
          command=@option_parser.get_next_arg_from_list('command',Node.common_actions.clone.concat([ ]))
          case command
          when :browse; return Node.execute_common(command,api_shares,@option_parser,@faspmanager)
          when :delete; return Node.execute_common(command,api_shares,@option_parser,@faspmanager)
          when :upload; return Node.execute_common(command,api_shares,@option_parser,@faspmanager)
          when :download; return Node.execute_common(command,api_shares,@option_parser,@faspmanager)
          else
            raise "ERROR, unknown command: [#{command}]"
          end
        end
      end
    end
  end # Cli
end # Asperalm
