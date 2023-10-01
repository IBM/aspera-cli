# frozen_string_literal: true

require 'aspera/uri_reader'
require 'aspera/environment'
require 'json'
require 'base64'
require 'zlib'
require 'csv'
require 'singleton'

module Aspera
  module Cli
    # command line extended values
    class ExtendedValue
      include Singleton

      class << self
        # decode comma separated table text
        def decode_csvt(value)
          col_titles = nil
          hash_array = []
          CSV.parse(value).each do |values|
            next if values.empty?
            if col_titles.nil?
              col_titles = values
            else
              entry = {}
              col_titles.each{|title|entry[title] = values.shift}
              hash_array.push(entry)
            end
          end
          Log.log.warn('Titled CSV file without any line') if hash_array.empty?
          return hash_array
        end
      end

      private

      def initialize
        @handlers = {
          val:    lambda{|v|v},
          base64: lambda{|v|Base64.decode64(v)},
          csvt:   lambda{|v|ExtendedValue.decode_csvt(v)},
          env:    lambda{|v|ENV[v]},
          file:   lambda{|v|File.read(File.expand_path(v))},
          uri:    lambda{|v|UriReader.read(v)},
          json:   lambda{|v|JSON.parse(v)},
          lines:  lambda{|v|v.split("\n")},
          list:   lambda{|v|v[1..-1].split(v[0])},
          path:   lambda{|v|File.expand_path(v)},
          ruby:   lambda{|v|Environment.secure_eval(v)},
          secret: lambda{|v|raise 'no value allowed for secret' unless v.empty?; $stdin.getpass('secret> ')}, # rubocop:disable Style/Semicolon
          stdin:  lambda{|v|raise 'no value allowed for stdin' unless v.empty?; $stdin.read}, # rubocop:disable Style/Semicolon
          zlib:   lambda{|v|Zlib::Inflate.inflate(v)},
          extend: lambda{|v|ExtendedValue.instance.evaluate_all(v)}
          # other handlers can be set using set_handler, e.g. preset is reader in config plugin
        }
      end

      public

      def modifiers; @handlers.keys; end

      # add a new handler
      def set_handler(name, method)
        Log.log.debug{"setting handler for #{name}"}
        raise 'name must be Symbol' unless name.is_a?(Symbol)
        @handlers[name] = method
      end

      # Regex to match an extended value
      def ext_re
        "@(#{modifiers.join('|')}):"
      end

      # parse an option value if it is a String using supported extended value modifiers
      # other value types are returned as is
      def evaluate(value)
        return value unless value.is_a?(String)
        regex = Regexp.new("^#{ext_re}(.*)$")
        # first determine decoders, in reversed order
        handlers_reversed = []
        while (m = value.match(regex))
          handler = m[1].to_sym
          handlers_reversed.unshift(handler)
          value = m[2]
          # stop processing if handler is extend (it will be processed later)
          break if handler.eql?(:extend)
        end
        handlers_reversed.each do |handler|
          value = @handlers[handler].call(value)
        end
        return value
      end # evaluate

      def evaluate_all(value)
        regex = Regexp.new("^(.*)#{ext_re}([^@]*)@(.*)$")
        while (m = value.match(regex))
          sub_value = "@#{m[2]}:#{m[3]}"
          Log.log.debug("evaluating #{sub_value}")
          value = m[1] + evaluate(sub_value) + m[4]
        end
        return value
      end
    end
  end
end
