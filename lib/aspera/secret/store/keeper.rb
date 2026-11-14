# frozen_string_literal: true

require_relative '../../log'
require_relative '../../assert'
require_relative '../reference'
require_relative 'base'
require 'logger'
begin
  require 'keeper_secrets_manager'
rescue LoadError
  raise Aspera::Secret::Error, 'type keeper requires gem keeper_secrets_manager: gem install keeper_secrets_manager'
end

module Aspera
  module Secret
    module Store
      # Manage secrets in Keeper Secrets Manager (Keeper Vault), using the Ruby SDK
      # https://docs.keeper.io/keeperpam/secrets-manager/overview
      #
      # A secret is a record of the Keeper vault shared with the application: its label is its title (or its UID).
      # Reference: `secret://<store>/<title or uid>#<field>`, field `password` by default.
      # Fields are those of the record: standard fields by type (`login`, `password`, `url`...), custom fields by label, and `notes`.
      # `username` is an alias of `login`.
      class Keeper < Base
        # `config`: configuration of the client device (base64 or JSON), the value, or `@file:<path>` (`Bootstrap`)
        # `folder_uid`: shared folder where `set` creates records (not needed to read)
        PARAMETERS = %i[config folder_uid].freeze

        class << self
          def arguments(params)
            params.merge(config: Bootstrap.new('config', params[:config]))
          end
        end

        # @param config     [String, Bootstrap] Configuration of the client device, from the one-time access token (`ksm profile export`)
        # @param folder_uid [String, nil]       UID of the shared folder where `set` creates records
        def initialize(config:, folder_uid: nil)
          super()
          Aspera.assert_type(folder_uid, String, type: ParameterError) { 'keeper folder_uid' } unless folder_uid.nil?
          config = Bootstrap.new('config', config) unless config.is_a?(Bootstrap)
          @folder_uid = folder_uid
          # The SDK logs on STDOUT by default: do not mix with results
          @client = ::KeeperSecretsManager.from_config(config.value, logger: ::Logger.new($stderr))
        end

        def info
          {
            hostname:   @client.hostname,
            folder_uid: @folder_uid
          }.compact
        end

        def all
          @client.get_secrets.map { |record| secret(record) }
        end

        def ids
          @client.get_secrets.map { |record| {id: record.uid, label: record.title} }
        end

        # Create a record of type `login` in the shared folder `folder_uid`
        # @param options [Hash] with keys :label, :username, :password, :url, :description
        def set(options)
          validate_set(options)
          Aspera.assert(!@folder_uid.nil?, type: ParameterError) { 'keeper: parameter folder_uid is required to create a secret' }
          assert_new_label(options[:label])
          fields = {login: :username, password: :password, url: :url}.filter_map do |type, key|
            {type: type.to_s, value: [options[key]]} if options[key]
          end
          record = {type: 'login', title: options[:label], fields: fields}
          record[:notes] = options[:description] if options[:description]
          @client.create_secret(record, ::KeeperSecretsManager::Dto::CreateOptions.new(folder_uid: @folder_uid))
          nil
        end

        def get(label:, id: nil, exception: true)
          record = find(id || label, exception: exception)
          return if record.nil?
          secret(record)
        end

        def delete(label:, id: nil)
          @client.delete_secret(find(id || label).uid)
          nil
        end

        # The record is found by title or UID, the field is `password` by default
        def read_reference(ref)
          record = find(ref.path)
          {value: field_value(record_values(record), ref, default: DEFAULT_FIELD), version: record.revision, updated_time: nil}
        end

        def read_fields(ref)
          record = find(ref.path)
          {fields: field_names(record_values(record).except('title')), version: record.revision, updated_time: nil}
        end

        private

        # @param identifier [String] UID or title of record
        # @return [KeeperSecretsManager::Dto::KeeperRecord, nil] Record, `nil` if not found and not `exception`
        def find(identifier, exception: true)
          records = @client.get_secrets
          matches = records.select { |record| record.uid.eql?(identifier) }
          matches = records.select { |record| record.title.eql?(identifier) } if matches.empty?
          raise "Multiple secrets found with label '#{identifier}': use id to disambiguate" if matches.size > 1
          raise "Secret '#{identifier}' not found" if matches.empty? && exception
          matches.first
        end

        # @return [Hash<String,Object>] Name of field → first value: `title`, `notes`, standard fields by type, custom fields by label, `username` for `login`
        def record_values(record)
          values = {'title' => record.title, 'notes' => record.notes}
          (record.fields + record.custom).each do |field|
            name = field['label'].to_s.empty? ? field['type'] : field['label']
            value = field['value']
            value = value.first if value.is_a?(Array)
            values[name] = value unless value.nil? || values.key?(name)
          end
          values['username'] = values['login'] if values.key?('login')
          values
        end

        # @return [Hash] Secret as in other stores
        def secret(record)
          values = record_values(record)
          {
            label:       record.title,
            id:          record.uid,
            username:    values['login'],
            password:    values['password'],
            url:         values['url'],
            description: values['notes']
          }.select { |_, value| value.is_a?(String) && !value.empty? }
        end
      end
    end
  end
end
