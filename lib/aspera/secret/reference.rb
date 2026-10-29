# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/secret/hider'
require 'uri'

module Aspera
  # Reference to a secret held in a store: `secret://<store>/<path>[?<options>][#<field>]`
  #
  # The reference is stored instead of the value, the value is read when used (see `Secret::Resolver`).
  # A reference is a whole value, it is not searched in a text.
  # Path and field are percent-decoded (`%20` or a space), options are a URL query (`version=2&mount=a/b`).
  # In `ascli`: `@vault://<store>/<path>[?<options>][#<field>]`, stores of option `vault`.
  module Secret
    # Error on a reference: the message gives the reference, never a value
    class Error < Aspera::Error
    end

    # Parsed reference
    # @!attribute text    [String]             Reference as given
    # @!attribute store   [String]             Name of store
    # @!attribute path    [String]             Path of secret in store (decoded)
    # @!attribute options [Hash<String,String>] Options
    # @!attribute field   [String, nil]        Field of secret (decoded), `nil` for default field of store
    Reference = Data.define(:text, :store, :path, :options, :field)

    # Bootstrap secret of a store in configuration (e.g. `password` of type `file`):
    # the value, or `@file:<path>` to read it from a file when used (e.g. a systemd credential), without final newline.
    # Syntax of extended values of `ascli`, only `@file:` is supported: other prefixes may be added.
    # In YAML, quote the value: `@` cannot start a plain scalar.
    class Bootstrap
      FILE_PREFIX = '@file:'

      # @param name [String] Name of parameter, for errors
      # @param text [String] Value, or `@file:<path>`
      # @raise [Error] Not a String, or empty
      def initialize(name, text)
        raise Error, "#{name}: expecting the value, or #{FILE_PREFIX}<path>" unless text.is_a?(String) && !text.empty?
        if text.start_with?(FILE_PREFIX)
          @path = text.delete_prefix(FILE_PREFIX)
          raise Error, "#{name}: expecting #{FILE_PREFIX}<path>" if @path.empty?
        else
          @value = text
          Secret::Hider.instance.add_secret_values(text)
        end
      end

      # @return [Boolean] `true` if read from a file
      def file?
        !@path.nil?
      end

      # @return [Time, nil] Modification time of file, `nil` for a value
      # @raise [Error] Missing file
      def mtime
        File.mtime(@path) unless @path.nil?
      rescue SystemCallError => e
        raise Error, "secret file: #{e.message}"
      end

      # @return [String] Value, read from the file at each call
      # @raise [Error] Missing, unreadable or empty file
      def value
        @path.nil? ? @value : Secret.read_file(@path)
      end

      # No value in logs and errors
      def inspect
        "#<#{self.class} #{@path.nil? ? 'value' : "#{FILE_PREFIX}#{@path}"}>"
      end
    end

    SCHEME = 'secret://'
    # Store name, path, options, field
    SYNTAX = %r{\Asecret://([A-Za-z0-9_.-]+)/([^?#]+)(?:\?([^#]*))?(?:#(.+))?\z}
    private_constant :SYNTAX

    class << self
      # @param value [Object] Any value
      # @return [Boolean] `true` if value is a String starting with `secret://` (then `parse_reference` checks it)
      def reference?(value)
        value.is_a?(String) && value.start_with?(SCHEME)
      end

      # @param text [String] Reference
      # @return [Reference] Parsed reference
      # @raise [Error] Invalid syntax
      def parse_reference(text)
        match = SYNTAX.match(text) if text.is_a?(String)
        raise Error, "secret reference #{text}: expected #{SCHEME}<store>/<path>[?<options>][#<field>]" if match.nil?
        Reference.new(
          text:    text,
          store:   match[1],
          path:    decode(text, match[2]),
          options: match[3].nil? ? {} : URI.decode_www_form(match[3]).to_h.freeze,
          field:   match[4].nil? ? nil : decode(text, match[4])
        )
      rescue ArgumentError => e
        raise Error, "secret reference #{text}: #{e.message}"
      end

      # Read a bootstrap secret from a file (`@file:` of `Bootstrap`, e.g. a systemd credential).
      # The value is declared to `Secret::Hider`.
      # @param path [String] Path of file
      # @return [String] Content of file without trailing newline
      # @raise [Error] Missing, unreadable or empty file
      def read_file(path)
        value = File.read(path).chomp
        raise Error, "empty secret file: #{path}" if value.empty?
        Secret::Hider.instance.add_secret_values(value)
        value
      rescue SystemCallError => e
        raise Error, "secret file: #{e.message}"
      end

      private

      # @return [String] Percent-decoded part of reference (`+` is not a space)
      def decode(text, part)
        URI.decode_uri_component(part)
      rescue ArgumentError
        raise Error, "secret reference #{text}: invalid percent-encoding: #{part}"
      end
    end
  end
end
