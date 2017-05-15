module Asperalm
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Plugin
      def set_options
        self.options.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
        self.options.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
        self.options.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
      end
    end # BasicAuthPlugin
  end # Cli
end # Asperalm
