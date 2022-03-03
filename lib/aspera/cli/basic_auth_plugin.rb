require 'aspera/rest'
require 'aspera/cli/plugin'

module Aspera
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Plugin
      def initialize(env)
        super(env)
        unless env[:skip_basic_auth_options]
          options.add_opt_simple(:url,'URL of application, e.g. https://org.asperafiles.com')
          options.add_opt_simple(:username,'username to log in')
          options.add_opt_simple(:password,"user's password")
          options.parse_options!
        end
      end
      ACTIONS=[]

      def execute_action
        raise 'do not execute action on this generic plugin'
      end

      # returns a Rest object with basic auth
      def basic_auth_api(subpath=nil)
        api_url=options.get_option(:url,:mandatory)
        api_url=api_url+'/'+subpath unless subpath.nil?
        return Rest.new({
          base_url:  api_url,
          auth:      {
          type:      :basic,
          username:  options.get_option(:username,:mandatory),
          password:  options.get_option(:password,:mandatory)
          }})
      end
    end # BasicAuthPlugin
  end # Cli
end # Aspera
