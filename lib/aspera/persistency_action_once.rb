# frozen_string_literal: true

require 'json'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  # Persist data on file system
  class PersistencyActionOnce
    DELETE_DEFAULT = lambda{|d|d.empty?}
    PARSE_DEFAULT = lambda {|t| JSON.parse(t)}
    FORMAT_DEFAULT = lambda {|h| JSON.generate(h)}
    MERGE_DEFAULT = lambda {|current, file| current.concat(file).uniq rescue current}
    MANAGER_METHODS = %i[get put delete]
    private_constant :DELETE_DEFAULT, :PARSE_DEFAULT, :FORMAT_DEFAULT, :MERGE_DEFAULT, :MANAGER_METHODS

    # @param :manager  Mandatory Database
    # @param :data     Mandatory object to persist, must be same object from begin to end (assume array by default)
    # @param :id       Mandatory identifiers
    # @param :delete   Optional  delete persistency condition
    # @param :parse    Optional  parse method (default to JSON)
    # @param :format   Optional  dump method (default to JSON)
    # @param :merge    Optional  merge data from file to current data
    def initialize(manager:, data:, id:, delete: DELETE_DEFAULT, parse: PARSE_DEFAULT, format: FORMAT_DEFAULT, merge: MERGE_DEFAULT)
      Aspera.assert(MANAGER_METHODS.all?{|i|manager.respond_to?(i)}){"Manager must answer to #{MANAGER_METHODS}"}
      Aspera.assert(!data.nil?)
      Aspera.assert_type(id, String)
      Aspera.assert(!id.empty?)
      Aspera.assert_type(delete, Proc)
      Aspera.assert_type(parse, Proc)
      Aspera.assert_type(format, Proc)
      Aspera.assert_type(merge, Proc)
      @manager = manager
      @persisted_object = data
      @object_id = id
      @delete_condition = delete
      @persist_format = format
      value = @manager.get(@object_id)
      merge.call(@persisted_object, parse.call(value)) unless value.nil?
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
