# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      # base class for applications supporting OAuth 2.0 authentication
      class Oauth < BasicAuth
        # OAuth methods supported
        AUTH_TYPES = %i[web jwt boot].freeze
        # Options used for authentication
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

        # Get command line options specified by `AUTH_OPTIONS` and `option.keys` (value is default).
        # Adds those not nil to the `kwargs`.
        # Instantiate the provided `klass` with those kwargs.
        # `option` can specify a default value (not `nil`)
        # @param klass   [Class] API object to create
        # @param kwargs  [Hash] The fixed keyword arguments for creation
        # @param option [Hash] Additional options, key=symbol, value:default value or nil
        # @return [Object] instance of `klass`
        # @raise [Cli::Error] if a required option is missing
        def new_with_options(klass, kwargs: {}, option: {})
          klass.new(**
            (AUTH_OPTIONS + option.keys).each_with_object(kwargs) do |i, m|
              v = options.get_option(i)
              m[i] = v unless v.nil?
              m[i] = option[i] unless !m[i].nil? || option[i].nil?
            end)
        rescue ::ArgumentError => e
          if (m = e.message.match(/missing keyword: :(.*)$/))
            raise Cli::Error, "Missing option: #{m[1]}"
          end
          raise
        end
      end
    end
  end
end
