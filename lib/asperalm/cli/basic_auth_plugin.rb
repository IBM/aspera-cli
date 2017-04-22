module Asperalm
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Plugin
      def set_options
        @option_parser.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
        @option_parser.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
        @option_parser.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
      end
    end # BasicAuthPlugin
  end # Cli
end # Asperalm
