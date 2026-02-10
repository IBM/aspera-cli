# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      # base class for applications supporting OAuth 2.0 authentication
      class Oauth < BasicAuth
        class << self
          # Get command line options specified by `AUTH_OPTIONS` and `defaults.keys` (value is default).
          # Adds those not nil to the `kwargs`.
          # Instantiate the provided `klass` with those `kwargs`.
          # `defaults` can specify a default value (not `nil`)
          # @param options  [Cli::Manager] Object to get command line options.
          # @param kwargs   [Hash]  Object creation arguments
          # @param defaults [Hash]  Additional options, key=symbol, value=default value or nil
          # @return [Object] instance of `klass`
          # @raise [Cli::Error] if a required option is missing
          def args_from_options(options, defaults: nil, **kwargs)
            defaults ||= {}
            (AUTH_OPTIONS + defaults.keys).each_with_object(kwargs) do |i, m|
              v = options.get_option(i)
              m[i] = v unless v.nil?
              m[i] = defaults[i] if m[i].nil? && !defaults[i].nil?
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
        def initialize(**_)
          super
          options.declare(:auth, 'OAuth type of authentication', allowed: AUTH_TYPES, default: :jwt)
          options.declare(:client_id, 'OAuth client identifier')
          options.declare(:client_secret, 'OAuth client secret')
          options.declare(:redirect_uri, 'OAuth (Web) redirect URI for web authentication')
          options.declare(:private_key, 'OAuth (JWT) RSA private key PEM value (prefix file path with @file:)')
          options.declare(:passphrase, 'OAuth (JWT) RSA private key passphrase')
        end
      end
    end
  end
end
