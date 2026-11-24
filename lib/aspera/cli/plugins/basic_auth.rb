# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../rest'
require_relative 'base'

module Aspera
  module Cli
    module Plugins
      # Module for plugins of applications supporting basic authentication: `include Cli::Plugins::BasicAuth` in a plugin class.
      # Its `included` hook gives the options of the module to the plugin class (`use_options`); `Oauth` includes this module and adds the options itself.
      module BasicAuth
        extend Option::Declarator

        class << self
          # @param base [Class] Plugin class that includes the module
          def included(base)
            super
            base.use_options(self) if base.is_a?(Class)
          end
        end

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
