# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/keychain/one_password_base'
require 'json'

module Aspera
  module Keychain
    # Manage secrets using the 1Password CLI (`op`)
    # https://developer.1password.com/docs/cli/
    class OnePasswordCli < Base
      include OnePasswordBase

      OP_EXECUTABLE = 'op'
      private_constant :OP_EXECUTABLE

      # @param vault   [String, nil] Name or ID of the 1Password vault (optional, uses default vault if omitted)
      # @param account [String, nil] Account shorthand for `op` (optional, uses default account if omitted)
      def initialize(vault: nil, account: nil)
        super()
        @vault   = vault
        @account = account
      end

      def info
        h = {}
        h[:vault]   = @vault   unless @vault.nil?
        h[:account] = @account unless @account.nil?
        h
      end

      def all
        items = op_json('item', 'list', '--categories', ITEM_CATEGORY)
        return items.map do |item|
          item_to_secret(op_json('item', 'get', item['id'])).merge(id: item['id'])
        end
      end

      def ids
        op_json('item', 'list', '--categories', ITEM_CATEGORY).map{ |item| {id: item['id'], label: item['title']}}
      end

      def set(options)
        validate_set(options)
        args = ['item', 'create', '--category', ITEM_CATEGORY, "--title=#{options[:label]}"]
        args << "#{FIELD_USERNAME}=#{options[:username]}"           if options[:username]
        args << "#{FIELD_PASSWORD}[password]=#{options[:password]}" if options[:password]
        args << "#{FIELD_URL}[url]=#{options[:url]}"                if options[:url]
        args << "#{FIELD_NOTES_ID}=#{options[:description]}"        if options[:description]
        op_run(*args)
        nil
      end

      def get(label:, id: nil, exception: true)
        identifier = id || label
        stdout, _stderr, status = op_capture('item', 'get', identifier, '--format=json')
        if !status.success?
          raise "Secret '#{label}' not found" if exception
          return
        end
        full = JSON.parse(stdout)
        return item_to_secret(full).merge(id: full['id'])
      end

      def delete(label:, id: nil)
        op_run('item', 'delete', id || label)
        nil
      end

      private

      def common_flags
        flags = []
        flags.push('--vault',   @vault)   unless @vault.nil?
        flags.push('--account', @account) unless @account.nil?
        flags
      end

      def op_json(*args)
        stdout, = op_capture(*args, '--format=json', exception: true)
        JSON.parse(stdout)
      end

      def op_run(*args)
        op_capture(*args, exception: true)
        nil
      end

      def op_capture(*args, exception: true)
        Environment.instance.class.secure_execute(
          OP_EXECUTABLE, *args, *common_flags,
          mode: :capture,
          exception: exception
        )
      end
    end
  end
end
