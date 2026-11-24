# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'basic_auth'
require_relative '../error'

module Aspera
  module Cli
    module Plugins
      # Options of OAuth web authentication (authorization code): client and redirect URI.
      # For a plugin that uses only this flow: `use_options OauthWebOptions` (without the options of `Oauth`)
      module OauthWebOptions
        extend Option::Declarator
        option :client_id,     description: 'OAuth client identifier'
        option :client_secret, description: 'OAuth client secret'
        option :redirect_uri,  description: 'OAuth (Web) redirect URI for web authentication'
      end

      # Options of OAuth JWT authentication: private key
      module OauthJwtOptions
        extend Option::Declarator
        option :private_key,   description: 'OAuth (JWT) RSA private key PEM value (prefix file path with @file:)'
        option :passphrase,    description: 'OAuth (JWT) RSA private key passphrase'
      end

      # Module for plugins of applications supporting OAuth 2.0 authentication: `include Cli::Plugins::Oauth` in a plugin class.
      # Includes `BasicAuth`. Its `included` hook gives the options of the module, `OauthWebOptions`, `OauthJwtOptions` and `BasicAuth` to the plugin class.
      module Oauth
        extend Option::Declarator
        include BasicAuth

        class << self
          # @param base [Class] Plugin class that includes the module
          def included(base)
            super
            # A module that includes `Oauth` has no options to declare
            return unless base.is_a?(Class)
            base.use_options(self)
            base.use_options(OauthWebOptions)
            base.use_options(OauthJwtOptions)
            base.use_options(BasicAuth)
          end

          # Get command line `options` specified by `AUTH_OPTIONS`
          # @param options [Cli::Parser] Object to get command line options.
          # @return [Hash{Symbol => Object}] Options
          # @raise [Cli::Error] if a required option is missing
          def kwargs_from_options(options)
            AUTH_OPTIONS.each_with_object({}) do |i, m|
              v = options.get_option(i)
              m[i] = v unless v.nil?
            end
          rescue ::ArgumentError => e
            if (m = e.message.match(/missing keyword: :(.*)$/))
              raise Cli::Error, "Missing option: #{m[1]}"
            end
            raise
          end
        end
        # OAuth methods supported (web, jwt)
        AUTH_TYPES = %i[web jwt boot].freeze
        # Options used for authentication (url, auth, client_id, etc...)
        AUTH_OPTIONS = %i[url auth client_id client_secret redirect_uri private_key passphrase username password].freeze
        option :auth,          description: 'OAuth type of authentication', allowed: AUTH_TYPES, default: :jwt
      end
    end
  end
end
