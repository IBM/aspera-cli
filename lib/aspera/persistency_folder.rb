require 'fileutils'
require 'aspera/log'

# search: persistency_folder PersistencyFolder

module Aspera
  # Persist data on file system
  class PersistencyFolder
    WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    PROTECTED_CHAR_REPLACE='_'
    ID_SEPARATOR='_'
    FILE_SUFFIX='.txt'
    private_constant :PROTECTED_CHAR_REPLACE,:FILE_SUFFIX,:WINDOWS_PROTECTED_CHAR,:ID_SEPARATOR
    def initialize(folder)
      @cache={}
      set_folder(folder)
    end

    def set_folder(folder)
      @folder=folder
      Log.log.debug("persistency folder: #{@folder}")
    end

    # @return String or nil string on existing persist, else nil
    def get(object_id)
      object_id=marshalled_id(object_id)
      if @cache.has_key?(object_id)
        persist_filepath=id_to_filepath(object_id)
        Log.log.debug("persistency = #{persist_filepath}")
        if File.exist?(persist_filepath)
          @cache[object_id]=File.read(persist_filepath)
        end
      end
      return @cache[object_id]
    end

    def put(object_id,value)
      raise "only String supported" unless value.is_a?(String)
      object_id=marshalled_id(object_id)
      persist_filepath=id_to_filepath(object_id)
      Log.log.debug("saving: #{persist_filepath}")
      File.write(persist_filepath,value)
      @cache[object_id]=value
    end

    def delete(object_id)
      object_id=marshalled_id(object_id)
      persist_filepath=id_to_filepath(object_id)
      Log.log.debug("empty data, deleting: #{persist_filepath}")
      File.delete(persist_filepath) if File.exist?(persist_filepath)
      @cache.delete(object_id)
    end

    def flush_by_prefix(persist_category)
      persist_files=Dir[File.join(@folder,persist_category+'*'+FILE_SUFFIX)]
      persist_files.each do |filepath|
        File.delete(filepath)
      end
      return persist_files
    end

    private

    # @param object_id String or Array
    def id_to_filepath(object_id)
      FileUtils.mkdir_p(@folder)
      return File.join(@folder,"#{object_id}#{FILE_SUFFIX}")
      #.gsub(/[^a-z]+/,FILE_FIELD_SEPARATOR)
    end

    def marshalled_id(object_id)
      if object_id.is_a?(Array)
        # special case, url in second position: TODO: check any position
        if object_id[1].is_a?(String) and object_id[1] =~ URI::ABS_URI
          object_id=object_id.clone
          object_id[1]=URI.parse(object_id[1]).host
        end
        object_id=object_id.join(ID_SEPARATOR)
      end
      raise "id must be a String" unless object_id.is_a?(String)
      return object_id.
      gsub(WINDOWS_PROTECTED_CHAR,PROTECTED_CHAR_REPLACE). # remove windows forbidden chars
      gsub('.',PROTECTED_CHAR_REPLACE).  # keep dot for extension only (nicer)
      downcase
    end
  end # PersistencyFolder
end # Aspera
