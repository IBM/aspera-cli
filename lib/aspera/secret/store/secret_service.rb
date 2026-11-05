# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/secret/store/base'

module Aspera
  module Secret
    module Store
      # Manage secrets using the Linux Secret Service (GNOME Keyring, KWallet, KeePassXC...), with the `secret-tool` CLI of libsecret.
      # https://specifications.freedesktop.org/secret-service/latest/
      # Items have attributes: `service` (parameter `name`), `label`, and optionally `username`, `url`, `description`.
      class SecretService < Base
        SECRET_TOOL = 'secret-tool'
        # Attribute that groups the secrets of one store
        ATTR_SERVICE = 'service'
        # Attributes of a secret, other than the password
        ATTRIBUTES = %i[label username url description].freeze
        # `secret-tool search` writes the label of each item on stdout, and its attributes on stderr
        LABEL_REGEX = /^label = (.*)$/
        ATTRIBUTE_REGEX = /^attribute\.(\w+) = (.*)$/
        private_constant :SECRET_TOOL, :ATTR_SERVICE, :ATTRIBUTES, :LABEL_REGEX, :ATTRIBUTE_REGEX
        PARAMETERS = %i[name].freeze

        # @param name [String] Name of the group of secrets in the Secret Service (attribute `service`)
        def initialize(name: 'ascli')
          super()
          raise Error, 'type secret_service: only on Linux' unless Environment.instance.os.eql?(Environment::OS_LINUX)
          @name = name
        end

        def info
          {service: @name}
        end

        def all
          labels.map { |label| get(label: label) }
        end

        def ids
          labels.map { |label| {label: label} }
        end

        # Store a new secret
        # @param options [Hash] `label`, `password`, `username`, `url`, `description`
        def set(options)
          validate_set(options)
          Aspera.assert(options.key?(:password), 'password is required')
          assert_new_label(options[:label])
          attributes = [ATTR_SERVICE, @name]
          ATTRIBUTES.each do |key|
            attributes.push(key.to_s, options[key]) if options.key?(key)
          end
          # the password is read from stdin: not visible in process list
          _, stderr, status = secret_tool('store', "--label=#{options[:label]}", *attributes, stdin_data: options[:password])
          raise Error, stderr.strip unless status.success?
          nil
        end

        # @param label     [String]  Label of the secret
        # @param exception [Boolean] Raise if not found
        # @return [Hash, nil] Secret, `nil` if not found and `exception` is `false`
        def get(label:, exception: true)
          stdout, stderr, status = secret_tool('lookup', ATTR_SERVICE, @name, 'label', label)
          if !status.success?
            # no error message when the item does not exist
            raise Error, stderr.strip unless stderr.strip.empty?
            raise "Secret '#{label}' not found" if exception
            return
          end
          attributes = search(label).last
          return {
            label:       label,
            username:    attributes['username'],
            password:    stdout.dup.force_encoding('UTF-8'),
            url:         attributes['url'],
            description: attributes['description']
          }.compact
        end

        # @param label [String] Label of the secret
        def delete(label:)
          raise "Secret '#{label}' not found" if get(label: label, exception: false).nil?
          _, stderr, status = secret_tool('clear', ATTR_SERVICE, @name, 'label', label)
          raise Error, stderr.strip unless status.success?
          nil
        end

        private

        # @param args       [Array<String>] Arguments of `secret-tool`
        # @param stdin_data [String, nil]   Data sent to stdin
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def secret_tool(*args, stdin_data: nil)
          kwargs = {mode: :capture, exception: false}
          kwargs[:stdin_data] = stdin_data unless stdin_data.nil?
          Environment.secure_execute(SECRET_TOOL, *args, **kwargs)
        rescue Errno::ENOENT
          raise Error, "#{SECRET_TOOL} not found: install libsecret tools (e.g. libsecret-tools)"
        end

        # @return [Array<String>] Labels of all secrets of the store
        def labels
          search.first
        end

        # @param label [String, nil] Label of the secret, `nil` for all secrets of the store
        # @return [Array(Array<String>, Hash<String,String>)] Labels of found secrets, and attributes
        #   (those of all found secrets, so they belong to the secret only when `label` is given)
        def search(label = nil)
          filter = [ATTR_SERVICE, @name]
          filter.push('label', label) unless label.nil?
          stdout, stderr, status = secret_tool('search', '--all', '--unlock', *filter)
          # no output and no error message when there is no item
          raise Error, stderr.strip if !status.success? && !stderr.strip.empty?
          labels = stdout.dup.force_encoding('UTF-8').scan(LABEL_REGEX).flatten
          attributes = stderr.dup.force_encoding('UTF-8').scan(ATTRIBUTE_REGEX).to_h
          [labels, attributes]
        end
      end
    end
  end
end
