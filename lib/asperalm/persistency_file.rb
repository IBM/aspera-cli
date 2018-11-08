require 'asperalm/cli/plugins/config'

module Asperalm
  # maintain a list of file_name_parts for packages that have already been downloaded
  class PersistencyFile
    @@FILE_FIELD_SEPARATOR='_'
    @@FILE_SUFFIX='.txt'
    @@WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    attr_accessor :filepath
    def initialize(type)
      @filepath=nil
    end

    # define a filepath in config folder from unique identifiers
    def set_unique(prefix,file_identifiers,url=nil)
      file_name_parts=identifiers.clone
      file_name_parts.unshift(URI.parse(url).host) unless url.nil?
      file_name_parts.unshift(prefix)
      basename=file_name_parts.map do |i|
        i.downcase.gsub!(@@WINDOWS_PROTECTED_CHAR,@@FILE_FIELD_SEPARATOR)
        #.gsub(/[^a-z]+/,@@FILE_FIELD_SEPARATOR)
      end.join(@@FILE_FIELD_SEPARATOR)
      @filepath=File.join(Cli::Plugins::Config.instance.config_folder,basename+@@FILE_SUFFIX)
      Log.log.debug("snapshot path=#{@filepath}")
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
      File.write(@filepath,data)
    end
  end
end
