# frozen_string_literal: true

require 'aspera/secret/ref_store/base'
require 'aspera/secret/store/hashicorp_vault'

module Aspera
  module Secret
    module RefStore
      # Secrets in a KV v2 secrets engine of HashiCorp Vault.
      # Reference: `secret://<store>/<mount>/<path>#<field>`, options: `version=<n>`, `mount=<mount>` (when the mount contains `/`).
      # Authentication by `token_file` or `approle` (with `secret_id_file`): no secret in configuration.
      class Vault < Base
        OPTIONS = %w[version mount].freeze
        # Invalid segments of path
        INVALID_SEGMENTS = ['', '.', '..'].freeze
        private_constant :INVALID_SEGMENTS

        # @param name             [String]             Name of store in configuration
        # @param url              [String]             URL of Vault server
        # @param token_file       [String, nil]        File with token, read again when modified (e.g. by Vault Agent)
        # @param approle          [Hash, nil]          AppRole: `role_id`, `secret_id_file`, `mount` (default: `approle`)
        # @param namespace        [String, nil]        Namespace (Vault Enterprise)
        # @param ca_file          [String, nil]        File with CA certificates of server
        # @param allowed_prefixes [Array<String>, nil] Allowed prefixes of `<mount>/<path>`, `nil`: all
        def initialize(name:, url:, token_file: nil, approle: nil, namespace: nil, ca_file: nil, allowed_prefixes: nil)
          super(name: name)
          raise Error, 'either token_file or approle' unless [token_file, approle].compact.size.eql?(1)
          raise Error, 'approle: secret_id_file instead of secret_id' if approle.is_a?(Hash) && approle.transform_keys(&:to_sym).key?(:secret_id)
          raise Error, 'allowed_prefixes: list of strings' unless allowed_prefixes.nil? || (allowed_prefixes.is_a?(Array) && allowed_prefixes.all?(String))
          @allowed_prefixes = allowed_prefixes
          @vault = Secret::Store::HashicorpVault.new(url: url, token_file: token_file, approle: approle, namespace: namespace, ca_file: ca_file)
        end

        def check!(ref)
          super
          mount, path = mount_and_path(ref)
          full_path = "#{mount}/#{path}"
          raise Error, "invalid path: #{full_path}" if full_path.split('/', -1).any? { |s| INVALID_SEGMENTS.include?(s) }
          raise Error, "path not allowed in store #{name}: #{full_path}" unless allowed?(full_path)
          version(ref)
          nil
        end

        private

        def read(ref)
          mount, path = mount_and_path(ref)
          secret = @vault.read(path: path, mount: mount, version: version(ref))
          raise Error, 'not found' if secret.nil?
          {value: field_value(secret[:data], ref), version: secret[:version], updated_time: secret[:created_time]}
        end

        # @return [Array<String>] Mount and path of secret in mount
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

        # @return [Integer, nil] Version of secret, `nil` for current
        def version(ref)
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
      end
    end
  end
end
