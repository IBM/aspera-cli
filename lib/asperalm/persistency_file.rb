module Asperalm
  # maintain a list of file_name_parts for packages that have already been downloaded
  class PersistencyFile
    @@FILE_FIELD_SEPARATOR='_'
    @@FILE_SUFFIX='.txt'
    @@WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    def initialize(prefix,default_folder)
      @filepath=nil
      @prefix=prefix
      @default_folder=default_folder
    end

    # define a filepath in config folder from unique identifiers
    def set_unique(override,file_identifiers,url=nil)
      if override.nil?
        Log.log.debug(">>> #{file_identifiers} >> #{url}")
        file_name_parts=file_identifiers.clone
        file_name_parts.unshift(URI.parse(url).host) unless url.nil?
        file_name_parts.unshift(@prefix)
        basename=file_name_parts.map do |i|
          i.downcase.gsub(@@WINDOWS_PROTECTED_CHAR,@@FILE_FIELD_SEPARATOR)
          #.gsub(/[^a-z]+/,@@FILE_FIELD_SEPARATOR)
        end.join(@@FILE_FIELD_SEPARATOR)
        @filepath=File.join(@default_folder,basename+@@FILE_SUFFIX)
      else
        @filepath=override
      end
      Log.log.debug("persistency(#{@prefix}) = #{@filepath}")
    end

    def read_from_file
      raise "no file defined" if @filepath.nil?
      if File.exist?(@filepath)
        return File.read(@filepath)
      end
      Log.log.debug("no persistency exists: #{@filepath}")
      return nil
    end

    def write_to_file(data)
      raise "no file defined" if @filepath.nil?
      if data.nil?
        Log.log.debug("nil data, deleting: #{@filepath}")
        File.delete(@filepath) if File.exist?(@filepath)
        return
      end
      Log.log.debug("saving: #{@filepath}")
      File.write(@filepath,data)
    end

    def flush_all
      persist_files=Dir[File.join(@@token_cache_folder,@prefix+'*'+@@FILE_SUFFIX)]
      persist_files.each do |filepath|
        File.delete(filepath)
      end
      return persist_files
    end
  end
end
