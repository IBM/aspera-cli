# frozen_string_literal: true

require 'json'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  # Persist data on file system
  class PersistencyActionOnce
    # @param :manager  Mandatory Database
    # @param :data     Mandatory object to persist, must be same object from begin to end (assume array by default)
    # @param :id       Mandatory identifiers
    # @param :delete   Optional  delete persistency condition
    # @param :parse    Optional  parse method (default to JSON)
    # @param :format   Optional  dump method (default to JSON)
    # @param :merge    Optional  merge data from file to current data
    def initialize(options)
      Log.log.debug{"persistency: #{options}"}
      assert_type(options, Hash)
      assert(!options[:manager].nil?){'mandatory :manager'}
      assert(!options[:data].nil?){'mandatory :data'}
      assert_type(options[:id], String)
      assert(options[:id].length >= 1){'mandatory 1 element in :id'}
      @manager = options[:manager]
      @persisted_object = options[:data]
      @object_id = options[:id]
      # by default , at save time, file is deleted if data is nil
      @delete_condition = options[:delete] || lambda{|d|d.empty?}
      @persist_format = options[:format] || lambda {|h| JSON.generate(h)}
      persist_parse = options[:parse] || lambda {|t| JSON.parse(t)}
      persist_merge = options[:merge] || lambda {|current, file| current.concat(file).uniq rescue current}
      value = @manager.get(@object_id)
      persist_merge.call(@persisted_object, persist_parse.call(value)) unless value.nil?
    end

    def save
      if @delete_condition.call(@persisted_object)
        @manager.delete(@object_id)
      else
        @manager.put(@object_id, @persist_format.call(@persisted_object))
      end
    end

    def data
      return @persisted_object
    end
  end
end
