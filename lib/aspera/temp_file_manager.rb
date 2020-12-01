require 'singleton'
require 'fileutils'
require 'etc'

module Aspera
  # create a temp file name for a given folder
  # files can be deleted on process exit by calling cleanup
  class TempFileManager
    include Singleton
    def initialize
      @created_files=[]
    end

    # call this on process exit
    def cleanup
      @created_files.each do |filepath|
        File.delete(filepath) if File.file?(filepath)
      end
      @created_files=[]
    end

    # ensure that provided folder exists, or create it, generate a unique filename
    # @return path to that unique file
    def new_file_path_in_folder(temp_folder,add_base='')
      FileUtils::mkdir_p(temp_folder) unless Dir.exist?(temp_folder)
      new_file=File.join(temp_folder,add_base+SecureRandom.uuid)
      @created_files.push(new_file)
      return new_file
    end

    # same as above but in global temp folder
    def new_file_path_global(base_name)
      username = Etc.getlogin || Etc.getpwuid(Process.uid).name || 'unknown_user' rescue 'unknown_user'
      return new_file_path_in_folder(Etc.systmpdir,base_name+'_'+username+'_')
    end
  end
end
