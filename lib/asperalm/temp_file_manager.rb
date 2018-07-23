require 'singleton'
module Asperalm
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
  end
end
