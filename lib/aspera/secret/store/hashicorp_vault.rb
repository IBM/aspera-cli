# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/secret/hider'
require 'aspera/secret/reference'
require 'aspera/secret/store/base'
require 'vault'
require 'time'

module Aspera
  module Secret
    module Store
      # Manage secrets in a Hashicorp Vault
      class HashicorpVault < Base
        STORE_PATH = 'secret/data/'
        APPROLE_KEYS = %i[mount role_id secret_id secret_id_file].freeze
        APPROLE_MOUNT = 'approle'
        # The AppRole token is renewed after this part of its lease
        RENEW_RATIO = 2.0 / 3
        HTTP_FORBIDDEN = 403

        private_constant :STORE_PATH, :APPROLE_KEYS, :APPROLE_MOUNT, :RENEW_RATIO, :HTTP_FORBIDDEN

        # `Vault::Client` (gem `vault` 0.20.1) gives the options of `JSON.parse` as a positional Hash,
        # refused by gem `json` 3 (`ArgumentError`), with option `create_additions` (removed, `false` by default in gem `json` 2):
        # responses are parsed here with keyword arguments.
        class Client < ::Vault::Client
          PARSE_OPTIONS = {max_nesting: false, symbolize_names: true}.freeze

          def success(response)
            return super unless json?(response)
            JSON.parse(response.body, **PARSE_OPTIONS)
          end

          # Same errors as `Vault::Client#error`
          def error(response)
            return super unless json?(response)
            klass =
              if response.body.include?('missing client token') then ::Vault::HTTPClientError
              else
                case response
                when Net::HTTPPreconditionFailed then raise ::Vault::MissingRequiredStateError
                when Net::HTTPClientError then ::Vault::HTTPClientError
                when Net::HTTPServerError then ::Vault::HTTPServerError
                else ::Vault::HTTPError
                end
              end
            errors = JSON.parse(response.body, **PARSE_OPTIONS)[:errors] rescue nil
            raise klass.new(address, response, errors.is_a?(Array) ? errors : [response.body])
          end

          private

          def json?(response)
            !response.body.nil? && (response.content_type || '').include?('json')
          end
        end
        private_constant :Client

        # One of `token`, `token_file` or `approle` authenticates the client
        # @param url        [String]      URL of Vault server
        # @param token      [String, nil] Token
        # @param token_file [String, nil] File with token (e.g. written by Vault Agent): read again when it is modified
        # @param approle    [Hash, nil]   AppRole: `role_id`, `secret_id` or `secret_id_file`, `mount` (default: `approle`)
        # @param namespace  [String, nil] Namespace (Vault Enterprise)
        # @param ca_file    [String, nil] File with CA certificates of server
        def initialize(url:, token: nil, token_file: nil, approle: nil, namespace: nil, ca_file: nil)
          super()
          Aspera.assert_type(url, String, type: ParameterError) { 'vault url' }
          Aspera.assert([token, token_file, approle].compact.size.eql?(1), type: ParameterError) { 'vault: one of token, token_file or approle is required' }
          @token_file = token_file
          @token_file_mtime = nil
          @approle = approle.nil? ? nil : approle_parameters(approle)
          # Monotonic time of renewal of the AppRole token, `nil` before login
          @renew_at = nil
          @auth_lock = Mutex.new
          options = {address: url, token: token}
          options[:namespace] = namespace unless namespace.nil?
          options[:ssl_ca_cert] = ca_file unless ca_file.nil?
          @client = Client.new(options)
        end

        def info
          {
            url:       @client.address,
            namespace: @client.namespace,
            auth:      auth_method
          }.compact
        end

        def all
          metadata_path = STORE_PATH.sub('/data/', '/metadata/')
          labels = call { |client| client.logical.list(metadata_path) }
          return labels.filter_map do |label|
            # KV v2: deleted secrets are still listed in metadata
            get(label: label, exception: false)&.merge(label: label)
          end
        end

        # Set a secret
        # @param options [Hash] with keys :label, :username, :password, :url, :description
        def set(options)
          validate_set(options)
          label = options.fetch(:label)
          assert_new_label(label)
          data = {
            username:    options[:username],
            password:    options[:password],
            url:         options[:url],
            description: options[:description]
          }.compact
          call { |client| client.logical.write(path(label), data: data) }
        end

        def get(label:, exception: true)
          # KV v2: a deleted secret may have metadata but no data
          data = call { |client| client.logical.read(path(label)) }&.data&.[](:data)
          if data.nil?
            raise "Secret '#{label}' not found" if exception
            return
          end
          return data
        end

        def delete(label:)
          path = path(label)
          call { |client| client.logical.delete(path) }
        end

        # Read a secret of a KV v2 secrets engine
        # @param path    [String]       Path of secret in the mount
        # @param mount   [String]       Mount of the secrets engine
        # @param version [Integer, nil] Version of secret, `nil` for current
        # @return [Hash, nil] `data` (fields with Symbol keys), `version`, `created_time` (`Time`), or `nil` if not found (or deleted)
        def read(path:, mount: 'secret', version: nil)
          secret = call { |client| client.kv(mount).read(path, version) }
          return if secret.nil? || secret.data.nil?
          metadata = secret.metadata || {}
          return {
            data:         secret.data,
            version:      metadata[:version],
            created_time: metadata[:created_time].nil? ? nil : Time.iso8601(metadata[:created_time])
          }
        end

        private

        def path(label)
          "#{STORE_PATH}#{label}"
        end

        # @return [String] Authentication method
        def auth_method
          return 'approle' unless @approle.nil?
          return 'token_file' unless @token_file.nil?
          'token'
        end

        # @param approle [Hash] AppRole parameters, keys String or Symbol
        # @return [Hash] AppRole parameters with Symbol keys, and default mount
        def approle_parameters(approle)
          Aspera.assert_type(approle, Hash, type: ParameterError) { 'vault approle' }
          approle = approle.transform_keys(&:to_sym)
          unsupported = approle.keys - APPROLE_KEYS
          Aspera.assert(unsupported.empty?, type: ParameterError) { "vault approle: unsupported keys: #{unsupported.join(', ')}, use #{APPROLE_KEYS.join(', ')}" }
          Aspera.assert_type(approle[:role_id], String, type: ParameterError) { 'vault approle role_id' }
          Aspera.assert(approle[:secret_id].nil? || approle[:secret_id_file].nil?, type: ParameterError) { 'vault approle: either secret_id or secret_id_file' }
          Secret::Hider.instance.add_secret_values(approle[:secret_id])
          {mount: APPROLE_MOUNT}.merge(approle)
        end

        # Call the API with an authenticated client.
        # On `403`, the call is done again once if credentials could change: new token in file, new AppRole login.
        # @yieldparam client [Vault::Client]
        # @return [Object] Value of block
        def call
          retried = false
          begin
            @auth_lock.synchronize { authenticate }
            yield(@client)
          rescue ::Vault::HTTPClientError => e
            raise if retried || !e.code.eql?(HTTP_FORBIDDEN)
            retried = true
            raise unless @auth_lock.synchronize { reauthenticate }
            Log.log.debug { "vault: #{e.code}, call again with new credentials (#{auth_method})" }
            retry
          end
        end

        # Set the token of client, if needed
        def authenticate
          if !@token_file.nil?
            mtime = File.mtime(@token_file)
            return if mtime.eql?(@token_file_mtime)
            @client.token = Secret.read_file(@token_file)
            @token_file_mtime = mtime
          elsif !@approle.nil?
            if @renew_at.nil?
              login
            elsif monotonic_time >= @renew_at
              renew
            end
          end
        end

        # After a `403`
        # @return [Boolean] `true` if credentials changed
        def reauthenticate
          if !@token_file.nil?
            previous = @client.token
            @token_file_mtime = nil
            authenticate
            return !@client.token.eql?(previous)
          elsif !@approle.nil?
            login
            return true
          end
          false
        end

        # AppRole login: sets the token of client
        def login
          secret_id = @approle[:secret_id]
          secret_id = Secret.read_file(@approle[:secret_id_file]) unless @approle[:secret_id_file].nil?
          @renew_at = nil
          # Sets the token of client
          auth = @client.auth.approle(@approle[:role_id], secret_id, mount: @approle[:mount]).auth
          Secret::Hider.instance.add_secret_values(auth.client_token)
          schedule_renewal(auth)
          Log.log.debug { "vault: AppRole login, lease: #{auth.lease_duration} s" }
        end

        # Renew the AppRole token, or new login if renewal fails
        def renew
          schedule_renewal(@client.auth_token.renew_self.auth)
          Log.log.debug('vault: token renewed')
        rescue ::Vault::HTTPError => e
          Log.log.debug { "vault: token renewal failed (#{e.code}), new login" }
          login
        end

        # @param auth [Vault::SecretAuth] Authentication information with lease
        def schedule_renewal(auth)
          # A lease duration of 0 never expires
          lease = auth.lease_duration.to_i
          @renew_at = lease.positive? ? monotonic_time + (lease * RENEW_RATIO) : Float::INFINITY
        end

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
