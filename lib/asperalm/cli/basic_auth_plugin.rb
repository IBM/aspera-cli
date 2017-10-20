require 'asperalm/cli/main'
module Asperalm
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Plugin
      def declare_options
        Main.tool.options.add_opt_simple(:url,"URI","-wURI","URL of application, e.g. https://org.asperafiles.com")
        Main.tool.options.add_opt_simple(:username,"STRING","-uSTRING","username to log in")
        Main.tool.options.add_opt_simple(:password,"STRING","-pSTRING","password")
      end
    end # BasicAuthPlugin
  end # Cli
end # Asperalm
