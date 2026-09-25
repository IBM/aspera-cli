# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/cli/plugins/base'

module Aspera
  module Cli
    module Plugins
      # base class for applications supporting basic authentication
      class BasicAuth < Base
        option :url,      description: 'URL of application, e.g. https://app.example.com/aspera/app'
        option :username, description: "User's identifier"
        option :password, description: "User's password"

        # returns a Rest::Client object with basic auth
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
          return Rest::Client.new(**basic_auth_params(subpath))
        end
      end
    end
  end
end
