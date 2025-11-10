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
        AUTH_OPTIONS = %i[url auth client_id client_secret scope redirect_uri private_key passphrase username password].freeze
        def initialize(**_)
          super
          options.declare(:auth, 'OAuth type of authentication', allowed: AUTH_TYPES, default: :jwt)
          options.declare(:client_id, 'OAuth client identifier')
          options.declare(:client_secret, 'OAuth client secret')
          options.declare(:redirect_uri, 'OAuth (Web) redirect URI for web authentication')
          options.declare(:private_key, 'OAuth (JWT) RSA private key PEM value (prefix file path with @file:)')
          options.declare(:passphrase, 'OAuth (JWT) RSA private key passphrase')
          options.declare(:scope, 'OAuth scope for API calls')
        end

        # Get all options specified by AUTH_OPTIONS and add.keys
        # Adds those not nil to the `base`.
        # Instantiate the provided `klass` with those kwargs.
        # `add` can specify a default value (not `nil`)
        # @param klass [Class] API object to create
        # @param base  [Hash] The base options for creation
        # @param add   [Hash] Additional options, key=symbol, value:default value or nil
        def new_with_options(klass, base: {}, add: {})
          klass.new(**
            (AUTH_OPTIONS + add.keys).each_with_object(base) do |i, m|
              v = options.get_option(i)
              m[i] = v unless v.nil?
              m[i] = add[i] unless !m[i].nil? || add[i].nil?
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
