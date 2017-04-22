require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        def execute_action
          api_console=Rest.new(@option_parser.get_option_mandatory(:url)+'/api',{:basic_auth=>{:user=>@option_parser.get_option_mandatory(:username), :password=>@option_parser.get_option_mandatory(:password)}})
          command=@option_parser.get_next_arg_from_list('command',[:transfers])
          case command
          when :transfers
            default_fields=['id','contact','name','status']
            command=@option_parser.get_next_arg_from_list('command',[ :list ])
            date_from=(Time.now - 3*3600).strftime("%Y-%m-%d %H:%M:%S")
            date_to=Time.now.strftime("%Y-%m-%d %H:%M:%S")
            resp=api_console.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>{'from'=>date_from,'to'=>date_to}})
            return {:fields=>default_fields,:values=>resp[:data]}
          end
        end
      end # Console
    end # Plugins
  end # Cli
end # Asperalm
