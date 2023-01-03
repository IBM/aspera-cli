# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/cli/plugin'

module Aspera
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Plugin
      class << self
        def register_options(env)
          env[:options].add_opt_simple(:url, 'URL of application, e.g. https://org.asperafiles.com')
          env[:options].add_opt_simple(:username, 'username to log in')
          env[:options].add_opt_simple(:password, "user's password")
          env[:options].parse_options!
        end
      end

      def initialize(env)
        super(env)
        return if env[:skip_basic_auth_options]
        self.class.register_options(env)
      end

      # returns a Rest object with basic auth
      def basic_auth_api(subpath=nil)
        api_url = options.get_option(:url, is_type: :mandatory)
        api_url = api_url + '/' + subpath unless subpath.nil?
        return Rest.new({
          base_url: api_url,
          auth:     {
            type:     :basic,
            username: options.get_option(:username, is_type: :mandatory),
            password: options.get_option(:password, is_type: :mandatory)
          }})
      end
    end # BasicAuthPlugin
  end # Cli
end # Aspera
