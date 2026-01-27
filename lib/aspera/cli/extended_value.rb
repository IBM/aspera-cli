# frozen_string_literal: true

# cspell:ignore csvt jsonpp stdbin
require 'aspera/uri_reader'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/cli/error'
require 'json'
require 'base64'
require 'zlib'
require 'csv'
require 'singleton'

module Aspera
  module Cli
    # Command line extended values
    class ExtendedValue
      include Singleton

      # First is default
      DEFAULT_DECODERS = %i[none json ruby yaml]

      class << self
        # Decode comma separated table text
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

        # JSON Parser, with more information on error location
        # extract a context: 10 chars before and after the error on the given line and display a pointer "^"
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

        # The value must be empty
        # @param value [String] The value as parameter
        # @param ext_type [Symbol] The method of extended value
        def assert_no_value(value, ext_type)
          Aspera.assert(value.empty?, type: BadArgument){"no value allowed for extended value type: #{ext_type}"}
        end

        def read_stdin(mode)
          case mode
          when '' then $stdin.read
          when 'bin' then $stdin.binmode.read
          when 'chomp' then $stdin.chomp
          else raise BadArgument, "`stdin` supports only: '', 'bin' or 'chomp'"
          end
        end
      end

      private

      def initialize
        # Base handlers
        # Other handlers can be set using `on`
        # e.g. `preset` is reader in config plugin
        @handlers = {
          val:    lambda{ |i| i},
          base64: lambda{ |i| Base64.decode64(i)},
          csvt:   lambda{ |i| ExtendedValue.decode_csvt(i)},
          env:    lambda{ |i| ENV.fetch(i, nil)},
          file:   lambda{ |i| File.read(File.expand_path(i))},
          uri:    lambda{ |i| UriReader.read(i)},
          json:   lambda{ |i| ExtendedValue.JSON_parse(i)},
          lines:  lambda{ |i| i.split("\n")},
          list:   lambda{ |i| i[1..-1].split(i[0])},
          none:   lambda{ |i| ExtendedValue.assert_no_value(i, :none); nil}, # rubocop:disable Style/Semicolon
          path:   lambda{ |i| File.expand_path(i)},
          re:     lambda{ |i| Regexp.new(i, Regexp::MULTILINE)},
          ruby:   lambda{ |i| Environment.secure_eval(i, __FILE__, __LINE__)},
          secret: lambda{ |i| prompt = i.empty? ? 'secret' : i; $stdin.getpass("#{prompt}> ")}, # rubocop:disable Style/Semicolon
          stdin:  lambda{ |i| ExtendedValue.read_stdin(i)},
          yaml:   lambda{ |i| YAML.load(i)},
          zlib:   lambda{ |i| Zlib::Inflate.inflate(i)},
          extend: lambda{ |i| ExtendedValue.instance.evaluate_extend(i)}
        }
        @regex_single = nil
        @regex_extend = nil
        @default_decoder = nil
        update_regex
      end

      # Update the Regex to match an extended value based on @handlers
      def update_regex
        handler_regex = "#{MARKER_START}(#{modifiers.join('|')})#{MARKER_END}"
        @regex_single = Regexp.new("^#{handler_regex}(.*)$", Regexp::MULTILINE)
        @regex_extend = Regexp.new("^(.*)#{handler_regex}([^#{MARKER_IN_END}]*)#{MARKER_IN_END}(.*)$", Regexp::MULTILINE)
      end

      public

      attr_reader :default_decoder

      def default_decoder=(value)
        Log.log.debug{"Setting default decoder to (#{value.class}) #{value}"}
        Aspera.assert_values(value, DEFAULT_DECODERS)
        value = nil if value.eql?(:none)
        @default_decoder = value
      end

      # List of Extended Value methods
      def modifiers; @handlers.keys; end

      # Add a new handler
      def on(name, &block)
        Aspera.assert_type(name, Symbol){'name'}
        Aspera.assert(block)
        Log.log.debug{"Setting handler for #{name}"}
        @handlers[name] = block
        update_regex
      end

      # Parses a `String` value to extended value.
      # If it is a String using supported extended value modifiers, then evaluate them.
      # Other value types are returned as is.
      # @param value   [String] the value to parse
      # @param context [String] Context in which evaluation is done
      # @param allowed [Array<Class>,NilClass] Expected types
      # @return [Object] Evaluated value
      def evaluate(value, context:, allowed: nil)
        return value unless value.is_a?(String)
        Aspera.assert_array_all(allowed, Class) unless allowed.nil?
        # use default decoder if not an extended value and expect complex types
        using_default_decoder = allowed&.all?{ |t| DEFAULT_PARSER_TYPES.include?(t)} && !@regex_single.match?(value) && !@default_decoder.nil?
        value = [MARKER_START, @default_decoder, MARKER_END, value].join if using_default_decoder
        # First determine decoders, in reversed order
        handlers_reversed = []
        while (m = value.match(@regex_single))
          handler = m[1].to_sym
          handlers_reversed.unshift(handler)
          value = m[2]
          break if SPECIAL_HANDLERS.include?(handler)
        end
        Log.log.trace1{"evaluating: #{handlers_reversed}, value: #{value}"}
        handlers_reversed.each do |handler|
          value = @handlers[handler].call(value)
        rescue => e
          raise BadArgument, "Evaluation of #{handler} for #{context}: #{e.message}"
        end
        return value
      end

      # Find inner extended values
      # Only used in above lambda
      def evaluate_extend(value)
        while (m = value.match(@regex_extend))
          sub_value = "@#{m[2]}:#{m[3]}"
          Log.log.debug{"evaluating #{sub_value}"}
          value = "#{m[1]}#{evaluate(sub_value, context: 'composite extended value')}#{m[4]}"
        end
        return value
      end
      # marker "@"
      MARKER_START = '@'
      # marker ":"
      MARKER_END = ':'
      # marker "@"
      MARKER_IN_END = '@'

      # Special handlers stop processing of handlers on right
      # :extend includes processing of other handlers in itself
      # :val keeps the value intact
      SPECIAL_HANDLERS = %i[extend val].freeze

      # Array and Hash types:
      DEFAULT_PARSER_TYPES = [Array, Hash].freeze
      private_constant :MARKER_START, :MARKER_END, :MARKER_IN_END, :SPECIAL_HANDLERS, :DEFAULT_PARSER_TYPES
    end
  end
end
