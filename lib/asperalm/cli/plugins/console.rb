require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Console < Plugin
        def opt_names; [:url,:username,:password]; end

        def command_list; [:transfers];end

        def set_options
          self.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
        end

        def dojob(command,argv)
          api_console=Rest.new(self.get_option_mandatory(:url),{:basic_auth=>{:user=>self.get_option_mandatory(:username), :password=>self.get_option_mandatory(:password)}})
          case command
          when :transfers
            default_fields=['id','contact','name','status']
            command=self.class.get_next_arg_from_list(argv,'command',[ :list ])
            resp=api_console.call({:operation=>'GET',:subpath=>'transfers',:headers=>{'Accept'=>'application/json'},:url_params=>{'from'=>(Time.now - 3600).strftime("%Y-%m-%d %H:%M:%S")}})
            return {:fields=>default_fields,:values=>resp[:data]}
          end
        end
      end
    end
  end # Cli
end # Asperalm
