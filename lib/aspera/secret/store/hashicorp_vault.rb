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
        APPROLE_KEYS = %i[mount role_id secret_id].freeze
        APPROLE_MOUNT = 'approle'
        # The AppRole token is renewed after this part of its lease
        RENEW_RATIO = 2.0 / 3
        HTTP_FORBIDDEN = 403
        # Invalid segments of path of reference
        INVALID_SEGMENTS = ['', '.', '..'].freeze

        private_constant :STORE_PATH, :APPROLE_KEYS, :APPROLE_MOUNT, :RENEW_RATIO, :HTTP_FORBIDDEN, :INVALID_SEGMENTS

        # Reference: `secret://<store>/<mount>/<path>#<field>` in a KV v2 secrets engine, options: `version=<n>`, `mount=<mount>` (when the mount contains `/`).
        # Authentication by `token` or `approle`: secrets are the value, or `@file:<path>` (`Bootstrap`).
        PARAMETERS = %i[url token approle namespace ca_file allowed_prefixes].freeze
        REFERENCE_OPTIONS = %w[version mount].freeze

        class << self
          # Errors of gem `vault`: code and errors of response, or address of server
          def error_reason(error)
            case error
            when ::Vault::HTTPError then "Vault: #{error.code}#{" #{error.errors.join(', ')}" unless error.errors.empty?}"
            when ::Vault::HTTPConnectionError then "Vault: cannot connect to #{error.address}: #{error.original_exception.message}"
            end
          end
        end

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

        # One of `token` or `approle` authenticates the client
        # @param url       [String]      URL of Vault server
        # @param token     [String, nil] Token: the value, or `@file:<path>` (e.g. written by Vault Agent), read again when it is modified
        # @param approle   [Hash, nil]   AppRole: `role_id`, `secret_id` (the value, or `@file:<path>`), `mount` (default: `approle`)
        # @param namespace [String, nil] Namespace (Vault Enterprise)
        # @param ca_file   [String, nil] File with CA certificates of server
        # @param allowed_prefixes [Array<String>, nil] Allowed prefixes of `<mount>/<path>` of references, `nil`: all
        def initialize(url:, token: nil, approle: nil, namespace: nil, ca_file: nil, allowed_prefixes: nil)
          super()
          Aspera.assert_type(url, String, type: ParameterError) { 'vault url' }
          Aspera.assert([token, approle].compact.size.eql?(1), type: ParameterError) { 'vault: one of token or approle is required' }
          Aspera.assert(allowed_prefixes.nil? || (allowed_prefixes.is_a?(Array) && allowed_prefixes.all?(String)), type: ParameterError) { 'vault allowed_prefixes: list of strings' }
          @allowed_prefixes = allowed_prefixes
          @token = Bootstrap.new('token', token) unless token.nil?
          # Modification time of file of token when read, `nil` before
          @token_mtime = nil
          @approle = approle.nil? ? nil : approle_parameters(approle)
          # Monotonic time of renewal of the AppRole token, `nil` before login
          @renew_at = nil
          @auth_lock = Mutex.new
          options = {address: url}
          options[:token] = @token.value unless @token.nil? || @token.file?
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

        def check_reference(ref)
          super
          mount, path = mount_and_path(ref)
          full_path = "#{mount}/#{path}"
          raise Error, "invalid path: #{full_path}" if full_path.split('/', -1).any? { |s| INVALID_SEGMENTS.include?(s) }
          raise Error, "path not allowed: #{full_path}" unless allowed?(full_path)
          reference_version(ref)
          nil
        end

        # The field is required
        def read_reference(ref)
          mount, path = mount_and_path(ref)
          secret = read(path: path, mount: mount, version: reference_version(ref))
          raise Error, 'not found' if secret.nil?
          {value: field_value(secret[:data], ref), version: secret[:version], updated_time: secret[:created_time]}
        end

        # Write a new secret (KV v2, check-and-set: refuses if the path already exists)
        # @param ref    [Reference]          Reference without field
        # @param fields [Hash<String,String>] Field name → value
        # @return [Hash] `version` (`Integer`), `updated_time` (`Time`)
        # @raise [Error] Path already exists ("secret exists: <mount>/<path>"), or Vault error
        def write_reference(ref, fields)
          mount, path = mount_and_path(ref)
          symbol_fields = fields.transform_keys(&:to_sym)
          response = call do |client|
            client.logical.write(
              "#{mount}/data/#{path}",
              options: {cas: 0},
              data:    symbol_fields
            )
          end
          metadata = response.data[:metadata] || response.data
          version = metadata[:version]
          created_time = metadata[:created_time]
          {version: version, updated_time: created_time.nil? ? nil : Time.iso8601(created_time)}
        rescue ::Vault::HTTPClientError => e
          raise Error, "secret exists: #{mount}/#{path}" if e.code == 400
          raise
        end

        private

        def path(label)
          "#{STORE_PATH}#{label}"
        end

        # @return [Array<String>] Mount and path in mount of reference
        def mount_and_path(ref)
          mount = ref.options['mount']
          if mount.nil?
            mount, path = ref.path.split('/', 2)
            raise Error, "path shall be <mount>/<path>: #{ref.path}" if path.nil?
            return [mount, path]
          end
          raise Error, "path shall start with mount #{mount}/" unless ref.path.start_with?("#{mount}/")
          [mount, ref.path.delete_prefix("#{mount}/")]
        end

        # @return [Integer, nil] Version of secret of reference, `nil` for current
        def reference_version(ref)
          value = ref.options['version']
          return if value.nil?
          raise Error, "version shall be a positive integer: #{value}" unless value.match?(/\A[1-9][0-9]*\z/)
          value.to_i
        end

        # A prefix ending with `/` is a folder, else it is a path or folder
        # @param full_path [String] `<mount>/<path>`
        def allowed?(full_path)
          return true if @allowed_prefixes.nil?
          @allowed_prefixes.any? do |prefix|
            prefix.end_with?('/') ? full_path.start_with?(prefix) : full_path.eql?(prefix) || full_path.start_with?("#{prefix}/")
          end
        end

        # @return [String] Authentication method
        def auth_method
          return 'approle' unless @approle.nil?
          @token.file? ? 'token file' : 'token'
        end

        # @param approle [Hash] AppRole parameters, keys String or Symbol
        # @return [Hash] AppRole parameters with Symbol keys, and default mount
        def approle_parameters(approle)
          Aspera.assert_type(approle, Hash, type: ParameterError) { 'vault approle' }
          approle = approle.transform_keys(&:to_sym)
          unsupported = approle.keys - APPROLE_KEYS
          Aspera.assert(unsupported.empty?, type: ParameterError) { "vault approle: unsupported keys: #{unsupported.join(', ')}, use #{APPROLE_KEYS.join(', ')}" }
          Aspera.assert_type(approle[:role_id], String, type: ParameterError) { 'vault approle role_id' }
          approle[:secret_id] = Bootstrap.new('approle secret_id', approle[:secret_id]) unless approle[:secret_id].nil?
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
          if @token&.file?
            mtime = @token.mtime
            return if mtime.eql?(@token_mtime)
            @client.token = @token.value
            @token_mtime = mtime
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
          if @token&.file?
            previous = @client.token
            @token_mtime = nil
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
          secret_id = @approle[:secret_id]&.value
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
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
