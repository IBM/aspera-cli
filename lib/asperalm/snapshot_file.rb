require 'asperalm/cli/plugins/config'
require 'json'

module Asperalm
  # maintain a list of file_name_parts for packages that have already been downloaded
  class SnapshotFile
    @@FILE_FIELD_SEPARATOR='_'
    @@FILE_SUFFIX='.txt'
    @@WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    def initialize(prefix,file_identifiers,url=nil)
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

    def read_persistency
      if File.exist?(@filepath)
        return JSON.parse(File.read(@filepath))
      end
      return []
    end

    def write_persistency(ids)
      File.write(@filepath,JSON.pretty_generate(ids))
    end
  end
end
