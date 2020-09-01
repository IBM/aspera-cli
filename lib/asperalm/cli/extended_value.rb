require 'asperalm/cli/plugins/config'
require 'json'
require 'base64'
require 'zlib'
require 'csv'
require 'singleton'

module Asperalm
  module Cli
    # command line extended values
    class ExtendedValue
      include Singleton
      private
      # decode comma separated table text
      def self.decode_csvt(value)
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

      def initialize
        @handlers={
          :decoder=>{
          'base64' =>lambda{|v|Base64.decode64(v)},
          'json'   =>lambda{|v|JSON.parse(v)},
          'zlib'   =>lambda{|v|Zlib::Inflate.inflate(v)},
          'ruby'   =>lambda{|v|eval(v)},
          'csvt'   =>lambda{|v|ExtendedValue.decode_csvt(v)},
          'lines'  =>lambda{|v|v.split("\n")},
          'list'   =>lambda{|v|v[1..-1].split(v[0])}
          },
          :reader=>{
          'val'    =>lambda{|v|v},
          'file'   =>lambda{|v|File.read(File.expand_path(v))},
          'path'   =>lambda{|v|File.expand_path(v)},
          'env'    =>lambda{|v|ENV[v]},
          'stdin'  =>lambda{|v|raise "no value allowed for stdin" unless v.empty?;STDIN.read}
          }
          # other handlers can be set using set_handler, e.g. preset is reader in config plugin
        }
      end
      public

      def modifiers;@handlers.keys.map{|i|@handlers[i].keys}.flatten;end

      # add a new :reader or :decoder
      # decoder can be chained, reader is last one on right
      def set_handler(name,type,method)
        raise "type must be one of #{@handlers.keys}" unless @handlers.keys.include?(type)
        Log.log.debug("setting #{type} handler for #{name}")
        @handlers[type][name]=method
      end

      # parse an option value if it is a String using supported extended value modifiers
      # other value types are returned as is
      def evaluate(value)
        return value if !value.is_a?(String)
        # first determine decoders, in reversed order
        decoders_reversed=[]
        while (m=value.match(/^@([^:]+):(.*)/)) and @handlers[:decoder].include?(m[1])
          decoders_reversed.unshift(m[1])
          value=m[2]
        end
        # then read value
        @handlers[:reader].each do |reader,method|
          if m=value.match(/^@#{reader}:(.*)/) then
            value=method.call(m[1])
            break
          end
        end
        decoders_reversed.each do |decoder|
          value=@handlers[:decoder][decoder].call(value)
        end
        return value
      end # parse
    end
  end
end
