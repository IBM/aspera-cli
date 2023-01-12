# frozen_string_literal: true

require 'aspera/cli/plugins/config'
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
          hasharray = []
          CSV.parse(value).each do |values|
            next if values.empty?
            if col_titles.nil?
              col_titles = values
            else
              entry = {}
              col_titles.each{|title|entry[title] = values.shift}
              hasharray.push(entry)
            end
          end
          Log.log.warn('Titled CSV file without any line') if hasharray.empty?
          return hasharray
        end
      end

      private

      def initialize
        @handlers = {
          decoder: {
            base64: lambda{|v|Base64.decode64(v)},
            json:   lambda{|v|JSON.parse(v)},
            zlib:   lambda{|v|Zlib::Inflate.inflate(v)},
            ruby:   lambda{|v|Environment.secure_eval(v)},
            csvt:   lambda{|v|ExtendedValue.decode_csvt(v)},
            lines:  lambda{|v|v.split("\n")},
            list:   lambda{|v|v[1..-1].split(v[0])}
          },
          reader:  {
            val:   lambda{|v|v},
            file:  lambda{|v|File.read(File.expand_path(v))},
            path:  lambda{|v|File.expand_path(v)},
            env:   lambda{|v|ENV[v]},
            uri:   lambda{|v|UriReader.read(v)},
            stdin: lambda{|v|raise 'no value allowed for stdin' unless v.empty?; $stdin.read} # rubocop:disable Style/Semicolon
          }
          # other handlers can be set using set_handler, e.g. preset is reader in config plugin
        }
      end

      public

      def modifiers; @handlers.keys.map{|i|@handlers[i].keys}.flatten.map(&:to_s); end

      # add a new :reader or :decoder
      # decoder can be chained, reader is last one on right
      def set_handler(name, type, method)
        Log.log.debug{"setting #{type} handler for #{name}"}
        raise 'name must be Symbol' unless name.is_a?(Symbol)
        raise "type #{type} must be one of #{@handlers.keys}" unless @handlers.key?(type)
        @handlers[type][name] = method
      end

      # parse an option value if it is a String using supported extended value modifiers
      # other value types are returned as is
      def evaluate(value)
        return value if !value.is_a?(String)
        # first determine decoders, in reversed order
        decoders_reversed = []
        while (m = value.match(/^@([^:]+):(.*)/)) && @handlers[:decoder].include?(m[1].to_sym)
          decoders_reversed.unshift(m[1].to_sym)
          value = m[2]
        end
        # then read value
        @handlers[:reader].each do |reader, method|
          if (m = value.match(/^@#{reader}:(.*)/))
            value = method.call(m[1])
            break
          end
        end
        decoders_reversed.each do |decoder|
          value = @handlers[:decoder][decoder].call(value)
        end
        return value
      end # parse
    end
  end
end
