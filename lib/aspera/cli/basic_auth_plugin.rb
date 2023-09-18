# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/cli/plugin'

module Aspera
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Aspera::Cli::Plugin
      class << self
        def register_options(env)
          env[:options].declare(:url, 'URL of application, e.g. https://org.asperafiles.com')
          env[:options].declare(:username, 'Username to log in')
          env[:options].declare(:password, "User's password")
          env[:options].parse_options!
        end
      end

      def initialize(env)
        super(env)
        self.class.register_options(env) unless env[:skip_basic_auth_options]
      end

      # returns a Rest object with basic auth
      def basic_auth_params(subpath=nil)
        api_url = options.get_option(:url, mandatory: true)
        api_url = api_url + '/' + subpath unless subpath.nil?
        return {
          base_url: api_url,
          auth:     {
            type:     :basic,
            username: options.get_option(:username, mandatory: true),
            password: options.get_option(:password, mandatory: true)
          }}
      end

      def basic_auth_api(subpath=nil)
        return Rest.new(basic_auth_params(subpath))
      end
    end # BasicAuthPlugin
  end # Cli
end # Aspera
