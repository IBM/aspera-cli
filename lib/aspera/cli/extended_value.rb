# frozen_string_literal: true

# cspell:ignore csvt jsonpp stdbin
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

      MARKER_START = '@'
      MARKER_END = ':'
      MARKER_IN_END = '@'

      # special handlers stop processing of handlers on right
      # extend includes processing of other handlers in itself
      # val keeps the value intact
      SPECIAL_HANDLERS = %i[extend val].freeze

      private_constant :MARKER_START, :MARKER_END, :MARKER_IN_END, :SPECIAL_HANDLERS

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
          Log.log.warn('Titled CSV file without any row') if hash_array.empty?
          return hash_array
        end

        def assert_no_value(value, what)
          raise "no value allowed for extended value type: #{what}" unless value.empty?
        end
      end

      private

      def initialize
        # base handlers
        # other handlers can be set using set_handler, e.g. `preset` is reader in config plugin
        @handlers = {
          val:    lambda{ |i| i},
          base64: lambda{ |i| Base64.decode64(i)},
          csvt:   lambda{ |i| ExtendedValue.decode_csvt(i)},
          env:    lambda{ |i| ENV.fetch(i, nil)},
          file:   lambda{ |i| File.read(File.expand_path(i))},
          uri:    lambda{ |i| UriReader.read(i)},
          json:   lambda{ |i| JSON_parse(i)},
          lines:  lambda{ |i| i.split("\n")},
          list:   lambda{ |i| i[1..-1].split(i[0])},
          none:   lambda{ |i| ExtendedValue.assert_no_value(i, :none); nil}, # rubocop:disable Style/Semicolon
          path:   lambda{ |i| File.expand_path(i)},
          re:     lambda{ |i| Regexp.new(i, Regexp::MULTILINE)},
          ruby:   lambda{ |i| Environment.secure_eval(i, __FILE__, __LINE__)},
          secret: lambda{ |i| prompt = i.empty? ? 'secret' : i; $stdin.getpass("#{prompt}> ")}, # rubocop:disable Style/Semicolon
          stdin:  lambda{ |i| ExtendedValue.assert_no_value(i, :stdin); $stdin.read}, # rubocop:disable Style/Semicolon
          stdbin: lambda{ |i| ExtendedValue.assert_no_value(i, :stdbin); $stdin.binmode.read}, # rubocop:disable Style/Semicolon
          yaml:   lambda{ |i| YAML.load(i)},
          zlib:   lambda{ |i| Zlib::Inflate.inflate(i)},
          extend: lambda{ |i| ExtendedValue.instance.evaluate_all(i)}
        }
        @default_decoder = nil
      end

      # Regex to match an extended value
      def handler_regex_string
        "#{MARKER_START}(#{modifiers.join('|')})#{MARKER_END}"
      end

      # JSON Parser, with more information on error location
      # :reek:UncommunicativeMethodName
      def JSON_parse(value) # rubocop:disable Naming/MethodName
        JSON.parse(value)
      rescue JSON::ParserError => e
        m = /at line (\d+) column (\d+)/.match(e.message)
        raise if m.nil?
        line = m[1].to_i - 1
        column = m[2].to_i - 1
        lines = value.lines
        raise if line >= lines.size
        error_line = lines[line].chomp
        context_col_beg = [column - 10, 0].max
        context_col_end = [column + 10, error_line.length].min
        context = error_line[context_col_beg...context_col_end]
        cursor_pos = column - context_col_beg
        pointer = ' ' * cursor_pos + '^'.blink
        raise BadArgument, "#{e.message}\n#{context}\n#{pointer}"
      end

      public

      def default_decoder=(value)
        Log.log.debug{"setting default decoder to #{value} (#{value.class})"}
        Aspera.assert(value.nil? || @handlers.key?(value))
        @default_decoder = value
      end

      def modifiers; @handlers.keys; end

      # add a new handler
      def set_handler(name, method)
        Log.log.debug{"setting handler for #{name}"}
        Aspera.assert_type(name, Symbol){'name'}
        @handlers[name] = method
      end

      # parse an string value to extended value, if it is a String using supported extended value modifiers
      # other value types are returned as is
      # @param value [String] the value to parse
      # @param expect [Class,Array] one or a list of expected types
      def evaluate(value)
        return value unless value.is_a?(String)
        regex = Regexp.new("^#{handler_regex_string}(.*)$", Regexp::MULTILINE)
        # first determine decoders, in reversed order
        handlers_reversed = []
        while (m = value.match(regex))
          handler = m[1].to_sym
          handlers_reversed.unshift(handler)
          value = m[2]
          break if SPECIAL_HANDLERS.include?(handler)
        end
        Log.log.trace1{"evaluating: #{handlers_reversed}, value: #{value}"}
        handlers_reversed.each do |handler|
          value = @handlers[handler].call(value)
        end
        return value
      end

      # parse string value as extended value
      # use default decoder if none is specified
      def evaluate_with_default(value)
        if value.is_a?(String) && value.match(/^#{handler_regex_string}.*$/).nil? && !@default_decoder.nil?
          value = [MARKER_START, @default_decoder, MARKER_END, value].join
        end
        return evaluate(value)
      end

      # find inner extended values
      def evaluate_all(value)
        regex = Regexp.new("^(.*)#{handler_regex_string}([^#{MARKER_IN_END}]*)#{MARKER_IN_END}(.*)$", Regexp::MULTILINE)
        while (m = value.match(regex))
          sub_value = "@#{m[2]}:#{m[3]}"
          Log.log.debug{"evaluating #{sub_value}"}
          value = "#{m[1]}#{evaluate(sub_value)}#{m[4]}"
        end
        return value
      end
    end
  end
end
