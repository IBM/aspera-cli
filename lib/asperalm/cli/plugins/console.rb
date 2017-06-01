require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < BasicAuthPlugin
        alias super_set_options set_options
        def set_options
          super_set_options
          self.options.set_option(:filter_from,OptParser.time_to_string(Time.now - 3*3600))
          self.options.set_option(:filter_to,OptParser.time_to_string(Time.now))
          self.options.add_opt_date(:filter_from,"--filter-from=DATE","only after date")
          self.options.add_opt_date(:filter_to,"--filter-to=DATE","only before date")
        end

        def execute_action
          api_console=Rest.new(self.options.get_option_mandatory(:url)+'/api',{:basic_auth=>{:user=>self.options.get_option_mandatory(:username), :password=>self.options.get_option_mandatory(:password)}})
          command=self.options.get_next_arg_from_list('command',[:transfers])
          case command
          when :transfers
            command=self.options.get_next_arg_from_list('command',[ :list ])
            resp=api_console.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>{'from'=>self.options.get_option_mandatory(:filter_from),'to'=>self.options.get_option_mandatory(:filter_to)}})
            return {:data=>resp[:data],:type=>:hash_array,:columns=>['id','contact','name','status']}
          end
        end
      end # Console
    end # Plugins
  end # Cli
end # Asperalm
