# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/cli/plugins/base'

module Aspera
  module Cli
    module Plugins
      # base class for applications supporting basic authentication
      class BasicAuth < Base
        option :url,      'URL of application, e.g. https://app.example.com/aspera/app'
        option :username, "User's identifier"
        option :password, "User's password"

        # Declare url/username/password on an arbitrary Options object.
        # Still needed for ad-hoc callers that are not plugin instances
        # (e.g. PresetActions#handle_config_lookup).
        class << self
          def declare_options(options)
            options.declare(:url,      'URL of application, e.g. https://app.example.com/aspera/app') unless options.option_declared?(:url)
            options.declare(:username, "User's identifier") unless options.option_declared?(:username)
            options.declare(:password, "User's password") unless options.option_declared?(:password)
            options.parse_options!
          end
        end

        def initialize(context:, basic_options: true)
          super(context: context)
          # DSL options (url, username, password) are auto-declared by Base#initialize
          # via the ancestor chain. parse_options! is still needed here when basic_options
          # is true so callers that rely on parsing at construction time keep working.
          options.parse_options! if basic_options
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
end
