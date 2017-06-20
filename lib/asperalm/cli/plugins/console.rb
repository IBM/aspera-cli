require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        alias super_declare_options declare_options
        def declare_options
          super_declare_options
          Main.tool.options.set_option(:filter_from,OptParser.time_to_string(Time.now - 3*3600))
          Main.tool.options.set_option(:filter_to,OptParser.time_to_string(Time.now))
          Main.tool.options.add_opt_date(:filter_from,"--filter-from=DATE","only after date")
          Main.tool.options.add_opt_date(:filter_to,"--filter-to=DATE","only before date")
        end

        def action_list; [:transfers];end

        def execute_action
          api_console=Rest.new(Main.tool.options.get_option_mandatory(:url)+'/api',{:basic_auth=>{:user=>Main.tool.options.get_option_mandatory(:username), :password=>Main.tool.options.get_option_mandatory(:password)}})
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :transfers
            command=Main.tool.options.get_next_arg_from_list('command',[ :list ])
            resp=api_console.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>{'from'=>Main.tool.options.get_option_mandatory(:filter_from),'to'=>Main.tool.options.get_option_mandatory(:filter_to)}})
            return {:data=>resp[:data],:type=>:hash_array,:columns=>['id','contact','name','status']}
          end
        end
      end # Console
    end # Plugins
  end # Cli
end # Asperalm
