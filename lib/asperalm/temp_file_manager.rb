require 'singleton'
require 'fileutils'
require 'etc'

module Asperalm
  # create a temp file name for a given folder
  # files can be deleted on process exit by calling cleanup
  class TempFileManager
    include Singleton
    def initialize
      @created_files=[]
    end

    def temp_filelist_path(temp_folder)
      FileUtils::mkdir_p(temp_folder) unless Dir.exist?(temp_folder)
      new_file=File.join(temp_folder,SecureRandom.uuid)
      @created_files.push(new_file)
      return new_file
    end

    def cleanup
      @created_files.each do |filepath|
        File.delete(filepath)
      end
      @created_files=[]
    end

    def global_tmpfile_path(some_name)
      username = Etc.getlogin || Etc.getpwuid(Process.uid).name || 'unknown' rescue 'unknown'
      return File.join(Etc.systmpdir,username)+'_'+some_name
    end
  end
end
