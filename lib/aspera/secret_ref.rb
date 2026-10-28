# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/secret_hider'
require 'uri'

module Aspera
  # Reference to a secret held in a store: `secret://<store>/<path>[?<options>][#<field>]`
  #
  # The reference is stored instead of the value, the value is read when used (see `SecretRef::Resolver`).
  # A reference is a whole value, it is not searched in a text.
  # Path and field are percent-decoded (`%20` or a space), options are a URL query (`version=2&mount=a/b`).
  # Library only: `ascli` options do not accept `secret://`.
  module SecretRef
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

    SCHEME = 'secret://'
    # Store name, path, options, field
    SYNTAX = %r{\Asecret://([A-Za-z0-9_.-]+)/([^?#]+)(?:\?([^#]*))?(?:#(.+))?\z}
    private_constant :SYNTAX

    class << self
      # @param value [Object] Any value
      # @return [Boolean] `true` if value is a String starting with `secret://` (then `parse` checks it)
      def reference?(value)
        value.is_a?(String) && value.start_with?(SCHEME)
      end

      # @param text [String] Reference
      # @return [Reference] Parsed reference
      # @raise [Error] Invalid syntax
      def parse(text)
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

      # Read a bootstrap secret from a file (`*_file` keys of configuration, e.g. a systemd credential).
      # The value is declared to `SecretHider`.
      # @param path [String] Path of file
      # @return [String] Content of file without trailing newline
      # @raise [Error] Missing, unreadable or empty file
      def read_file_secret(path)
        value = File.read(path).chomp
        raise Error, "empty secret file: #{path}" if value.empty?
        SecretHider.instance.add_secret_values(value)
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
