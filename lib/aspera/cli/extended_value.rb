# frozen_string_literal: true

# cspell:ignore csvt jsonpp
require 'aspera/uri_reader'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
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

      # special values
      INIT = 'INIT'
      ALL = 'ALL'
      DEF = 'DEF'

      MARKER_START = '@'
      MARKER_END = ':'
      MARKER_IN_END = '@'

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
              hash_array.push(col_titles.zip(values).to_h)
            end
          end
          Log.log.warn('Titled CSV file without any line') if hash_array.empty?
          return hash_array
        end

        def assert_no_value(v, what)
          raise "no value allowed for extended value type: #{what}" unless v.empty?
        end
      end

      private

      def initialize
        # base handlers
        # other handlers can be set using set_handler, e.g. `preset` is reader in config plugin
        @handlers = {
          val:    lambda{|v|v},
          base64: lambda{|v|Base64.decode64(v)},
          csvt:   lambda{|v|ExtendedValue.decode_csvt(v)},
          env:    lambda{|v|ENV.fetch(v, nil)},
          file:   lambda{|v|File.read(File.expand_path(v))},
          uri:    lambda{|v|UriReader.read(v)},
          json:   lambda{|v|JSON.parse(v)},
          lines:  lambda{|v|v.split("\n")},
          list:   lambda{|v|v[1..-1].split(v[0])},
          none:   lambda{|v|ExtendedValue.assert_no_value(v, :none); nil}, # rubocop:disable Style/Semicolon
          path:   lambda{|v|File.expand_path(v)},
          re:     lambda{|v|Regexp.new(v, Regexp::MULTILINE)},
          ruby:   lambda{|v|Environment.secure_eval(v, __FILE__, __LINE__)},
          secret: lambda{|v|prompt = v.empty? ? 'secret' : v; $stdin.getpass("#{prompt}> ")}, # rubocop:disable Style/Semicolon
          stdin:  lambda{|v|ExtendedValue.assert_no_value(v, :stdin); $stdin.read}, # rubocop:disable Style/Semicolon
          yaml:   lambda{|v|YAML.load(v)},
          zlib:   lambda{|v|Zlib::Inflate.inflate(v)},
          extend: lambda{|v|ExtendedValue.instance.evaluate_all(v)}
        }
      end

      public

      def modifiers; @handlers.keys; end

      # add a new handler
      def set_handler(name, method)
        Log.log.debug{"setting handler for #{name}"}
        Aspera.assert_type(name, Symbol){'name'}
        @handlers[name] = method
      end

      # Regex to match an extended value
      def ext_re
        "#{MARKER_START}(#{modifiers.join('|')})#{MARKER_END}"
      end

      # parse an option value if it is a String using supported extended value modifiers
      # other value types are returned as is
      def evaluate(value)
        return value unless value.is_a?(String)
        regex = Regexp.new("^#{ext_re}(.*)$", Regexp::MULTILINE)
        # first determine decoders, in reversed order
        handlers_reversed = []
        while (m = value.match(regex))
          handler = m[1].to_sym
          handlers_reversed.unshift(handler)
          value = m[2]
          # stop processing if handler is extend (it will be processed later)
          break if handler.eql?(:extend)
        end
        Log.log.trace1{"evaluating: #{handlers_reversed}, value: #{value}"}
        handlers_reversed.each do |handler|
          value = @handlers[handler].call(value)
        end
        return value
      end # evaluate

      # find inner extended values
      def evaluate_all(value)
        regex = Regexp.new("^(.*)#{ext_re}([^#{MARKER_IN_END}]*)#{MARKER_IN_END}(.*)$", Regexp::MULTILINE)
        while (m = value.match(regex))
          sub_value = "@#{m[2]}:#{m[3]}"
          Log.log.debug{"evaluating #{sub_value}"}
          value = m[1] + evaluate(sub_value) + m[4]
        end
        return value
      end
    end
  end
end
