# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/cli/plugin'

module Aspera
  module Cli
    # base class for applications supporting basic authentication
    class BasicAuthPlugin < Cli::Plugin
      class << self
        def declare_options(options)
          options.declare(:url, 'URL of application, e.g. https://app.example.com/aspera/app')
          options.declare(:username, "User's identifier")
          options.declare(:password, "User's password")
          options.parse_options!
        end
      end

      def initialize(context:, basic_options: true)
        super(context: context)
        BasicAuthPlugin.declare_options(options) if basic_options
      end

      # returns a Rest object with basic auth
      def basic_auth_params(subpath = nil)
        api_url = options.get_option(:url, mandatory: true)
        api_url = "#{api_url}/#{subpath}" unless subpath.nil?
        return {
          base_url: api_url,
          auth:     {
            type:     :basic,
            username: options.get_option(:username, mandatory: true),
            password: options.get_option(:password, mandatory: true)
          }
        }
      end

      def basic_auth_api(subpath = nil)
        return Rest.new(**basic_auth_params(subpath))
      end
    end
  end
end
