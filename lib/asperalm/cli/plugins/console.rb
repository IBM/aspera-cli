require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        alias super_set_options set_options
        def set_options
          super_set_options
          @option_parser.set_option(:filter_from,OptParser.time_to_string(Time.now - 3*3600))
          @option_parser.set_option(:filter_to,OptParser.time_to_string(Time.now))
          @option_parser.add_opt_date(:filter_from,"--filter-from=DATE","only after date")
          @option_parser.add_opt_date(:filter_to,"--filter-to=DATE","only before date")
        end

        def execute_action
          api_console=Rest.new(@option_parser.get_option_mandatory(:url)+'/api',{:basic_auth=>{:user=>@option_parser.get_option_mandatory(:username), :password=>@option_parser.get_option_mandatory(:password)}})
          command=@option_parser.get_next_arg_from_list('command',[:transfers])
          case command
          when :transfers
            default_fields=['id','contact','name','status']
            command=@option_parser.get_next_arg_from_list('command',[ :list ])
            resp=api_console.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>{'from'=>@option_parser.get_option_mandatory(:filter_from),'to'=>@option_parser.get_option_mandatory(:filter_to)}})
            return {:fields=>default_fields,:values=>resp[:data]}
          end
        end
      end # Console
    end # Plugins
  end # Cli
end # Asperalm
