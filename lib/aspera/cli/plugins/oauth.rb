# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      # base class for applications supporting OAuth 2.0 authentication
      class Oauth < BasicAuth
        class << self
          # Get command line `options` specified by `AUTH_OPTIONS`
          # @param options [Cli::Options] Object to get command line options.
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
        option :client_id,     description: 'OAuth client identifier'
        option :client_secret, description: 'OAuth client secret'
        option :redirect_uri,  description: 'OAuth (Web) redirect URI for web authentication'
        option :private_key,   description: 'OAuth (JWT) RSA private key PEM value (prefix file path with @file:)'
        option :passphrase,    description: 'OAuth (JWT) RSA private key passphrase'
      end
    end
  end
end
