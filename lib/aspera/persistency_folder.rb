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

    # @return String or nil string on existing persist, else nil
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

    def put(object_id, value)
      assert_type(value, String)
      persist_filepath = id_to_filepath(object_id)
      Log.log.debug{"persistency saving: #{persist_filepath}"}
      FileUtils.rm_f(persist_filepath)
      File.write(persist_filepath, value)
      Environment.restrict_file_access(persist_filepath)
      @cache[object_id] = value
    end

    def delete(object_id)
      persist_filepath = id_to_filepath(object_id)
      Log.log.debug{"persistency deleting: #{persist_filepath}"}
      FileUtils.rm_f(persist_filepath)
      @cache.delete(object_id)
    end

    def garbage_collect(persist_category, max_age_seconds=nil)
      garbage_files = Dir[File.join(@folder, persist_category + '*' + FILE_SUFFIX)]
      if !max_age_seconds.nil?
        current_time = Time.now
        garbage_files.select! { |filepath| (current_time - File.stat(filepath).mtime).to_i > max_age_seconds}
      end
      garbage_files.each do |filepath|
        File.delete(filepath)
        Log.log.debug{"persistency deleted expired: #{filepath}"}
      end
      return garbage_files
    end

    private

    # @param object_id String or Array
    def id_to_filepath(object_id)
      assert_type(object_id, String)
      FileUtils.mkdir_p(@folder)
      Environment.restrict_file_access(@folder)
      return File.join(@folder, "#{object_id}#{FILE_SUFFIX}")
      # .gsub(/[^a-z]+/,FILE_FIELD_SEPARATOR)
    end
  end # PersistencyFolder
end # Aspera
