# frozen_string_literal: true

require 'fileutils'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'

# search: persistency_folder PersistencyFolder

module Aspera
  # Persist data on file system
  class PersistencyFolder
    FILE_SUFFIX = '.txt'
    private_constant :FILE_SUFFIX
    def initialize(folder)
      @cache = {}
      @folder = folder
      Log.log.debug{"persistency folder: #{@folder}"}
    end

    # Get value of persisted item
    # @return [String,nil] Value of persisted id
    def get(object_id)
      Log.log.debug{"persistency get: #{object_id}"}
      if @cache.key?(object_id)
        Log.log.debug('got from memory cache')
      else
        persist_filepath = id_to_filepath(object_id)
        Log.log.debug{"persistency = #{persist_filepath}"}
        if File.exist?(persist_filepath)
          Log.log.debug('got from file cache')
          @cache[object_id] = File.read(persist_filepath)
        end
      end
      return @cache[object_id]
    end

    # Set value of persisted item
    # @param object_id [String] Identifier of persisted item
    # @param value [String] Value of persisted item
    # @return [nil]
    def put(object_id, value)
      Aspera.assert_type(value, String)
      persist_filepath = id_to_filepath(object_id)
      Log.log.debug{"persistency saving: #{persist_filepath}"}
      FileUtils.rm_f(persist_filepath)
      File.write(persist_filepath, value)
      Environment.restrict_file_access(persist_filepath)
      @cache[object_id] = value
      nil
    end

    # Delete persisted item
    # @param object_id [String] Identifier of persisted item
    def delete(object_id)
      persist_filepath = id_to_filepath(object_id)
      Log.log.debug{"persistency deleting: #{persist_filepath}"}
      FileUtils.rm_f(persist_filepath)
      @cache.delete(object_id)
    end

    # Delete persisted items
    def garbage_collect(persist_category, max_age_seconds=nil)
      garbage_files = current_files(persist_category)
      if !max_age_seconds.nil?
        current_time = Time.now
        garbage_files.select!{ |filepath| (current_time - File.stat(filepath).mtime).to_i > max_age_seconds}
      end
      garbage_files.each do |filepath|
        File.delete(filepath)
        Log.log.debug{"persistency deleted expired: #{filepath}"}
      end
      @cache.clear
      return garbage_files
    end

    def current_files(persist_category)
      Dir[File.join(@folder, persist_category + '*' + FILE_SUFFIX)]
    end

    def current_items(persist_category)
      current_files(persist_category).each_with_object({}){ |i, h| h[File.basename(i, FILE_SUFFIX)] = File.read(i)}
    end

    private

    # @param object_id String or Array
    def id_to_filepath(object_id)
      Aspera.assert_type(object_id, String)
      FileUtils.mkdir_p(@folder)
      Environment.restrict_file_access(@folder)
      return File.join(@folder, "#{object_id}#{FILE_SUFFIX}")
      # .gsub(/[^a-z]+/,FILE_FIELD_SEPARATOR)
    end
  end
end
