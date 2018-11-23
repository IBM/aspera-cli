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
          'base64'=>{:type=>:decoder,:func=>lambda{|v|Base64.decode64(v)}},
          'json'  =>{:type=>:decoder,:func=>lambda{|v|JSON.parse(v)}},
          'zlib'  =>{:type=>:decoder,:func=>lambda{|v|Zlib::Inflate.inflate(v)}},
          'ruby'  =>{:type=>:decoder,:func=>lambda{|v|eval(v)}},
          'csvt'  =>{:type=>:decoder,:func=>lambda{|v|ExtendedValue.decode_csvt(v)}},
          'val'   =>{:type=>:reader ,:func=>lambda{|v|v}},
          'file'  =>{:type=>:reader ,:func=>lambda{|v|File.read(File.expand_path(v))}},
          'path'  =>{:type=>:reader ,:func=>lambda{|v|File.expand_path(v)}},
          'env'   =>{:type=>:reader ,:func=>lambda{|v|ENV[v]}},
          'stdin' =>{:type=>:reader ,:func=>lambda{|v|raise "no value allowed for stdin" unless v.empty?;STDIN.gets}},
        }
      end
      public

      def modifiers;@handlers.keys;end

      def set_handler(name,type,method)
        @handlers[name]={:type=>type,:func=>method}
      end

      # parse an option value, special behavior for file:, env:, val:
      # parse only string, other values are returned as is
      def parse(name_or_descr,value)
        return value if !value.is_a?(String)
        decoder_list=@handlers.keys.select{|k|@handlers[k][:type].eql?(:decoder)}
        reader_list=@handlers.keys.select{|k|@handlers[k][:type].eql?(:reader)}
        # first determine decoders, in reversed order
        decoders_reversed=[]
        while (m=value.match(/^@([^:]+):(.*)/)) and decoder_list.include?(m[1])
          decoders_reversed.unshift(m[1])
          value=m[2]
        end
        # then read value
        reader_list.each do |reader|
          if m=value.match(/^@#{reader}:(.*)/) then
            value=@handlers[reader][:func].call(m[1])
            break
          end
        end
        decoders_reversed.each do |decoder|
          value=@handlers[decoder][:func].call(value)
        end
        return value
      end # parse
    end
  end
end
