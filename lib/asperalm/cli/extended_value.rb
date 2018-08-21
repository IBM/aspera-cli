require 'json'
require 'base64'
require 'zlib'
require 'csv'

module Asperalm
  module Cli
    # command line extended values
    class ExtendedValue
      # decoders can be pipelined
      @@DECODERS=['base64', 'json', 'zlib', 'ruby', 'csvt']

      # there shall be zero or one reader only
      def self.readers; ['val', 'file', 'path', 'env', 'stdin'].push(@@DECODERS); end

      # parse an option value, special behavior for file:, env:, val:
      def self.parse(name_or_descr,value)
        if value.is_a?(String)
          # first determine decoders, in reversed order
          decoders_reversed=[]
          while (m=value.match(/^@([^:]+):(.*)/)) and @@DECODERS.include?(m[1])
            decoders_reversed.unshift(m[1])
            value=m[2]
          end
          # then read value
          if m=value.match(/^@val:(.*)/) then
            value=m[1]
          elsif m=value.match(%r{^@file:(.*)}) then
            value=File.read(File.expand_path(m[1]))
            #raise CliBadArgument,"cannot open file \"#{value}\" for #{name_or_descr}" if ! File.exist?(value)
          elsif m=value.match(/^@path:(.*)/) then
            value=File.expand_path(m[1])
          elsif m=value.match(/^@env:(.*)/) then
            value=ENV[m[1]]
          elsif value.eql?('@stdin') then
            value=STDIN.gets
          end
          decoders_reversed.each do |d|
            case d
            when 'json'; value=JSON.parse(value)
            when 'ruby'; value=eval(value)
            when 'base64'; value=Base64.decode64(value)
            when 'zlib'; value=Zlib::Inflate.inflate(value)
            when 'csvt'
              col_titles=nil
              hasharray=[]
              CSV.parse(value).each do |values|
                next if values.empty?
                if col_titles.nil?
                  col_titles=values
                else
                  entry={}
                  col_titles.each{|title|entry[title]=values.shift}
                  hasharray.push(entry)
                end
              end
              value=hasharray
            end
          end
        end
        value
      end
    end
  end
end
