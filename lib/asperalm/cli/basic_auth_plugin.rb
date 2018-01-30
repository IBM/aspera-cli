require 'asperalm/cli/main'
require 'asperalm/rest'
module Asperalm
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Plugin
      # returns a Rest object with basic auth
      def basic_auth_api(subpath=nil)
        api_url=Main.tool.options.get_option(:url,:mandatory)
        api_url=api_url+'/'+subpath if !subpath.nil?
        return Rest.new(api_url,{:auth=>{:type=>:basic,:username=>Main.tool.options.get_option(:username,:mandatory), :password=>Main.tool.options.get_option(:password,:mandatory)}})
      end
      def declare_options
        Main.tool.options.add_opt_simple(:url,"URI","-wURI","URL of application, e.g. https://org.asperafiles.com")
        Main.tool.options.add_opt_simple(:username,"STRING","-uSTRING","username to log in")
        Main.tool.options.add_opt_simple(:password,"STRING","-pSTRING","user's password")
      end
    end # BasicAuthPlugin
  end # Cli
end # Asperalm
