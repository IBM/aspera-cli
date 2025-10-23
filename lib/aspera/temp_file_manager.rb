# frozen_string_literal: true

require 'singleton'
require 'fileutils'
require 'etc'

module Aspera
  # create a temp file name for a given folder
  # files can be deleted on process exit by calling cleanup
  class TempFileManager
    include Singleton

    SEC_IN_DAY = 86_400
    # assume no transfer last longer than this
    # (garbage collect file list which were not deleted after transfer)
    FILE_LIST_AGE_MAX_SEC = SEC_IN_DAY * 5
    private_constant :SEC_IN_DAY, :FILE_LIST_AGE_MAX_SEC

    attr_accessor :cleanup_on_exit, :global_temp

    def initialize
      @created_files = []
      @cleanup_on_exit = true
      @global_temp = Etc.systmpdir
    end

    def delete_file(filepath)
      File.delete(filepath) if @cleanup_on_exit
    rescue => e
      Log.log.error{"Problem deleting file: #{filepath}: #{e.message}"}
    end

    # call this on process exit
    def cleanup
      @created_files.each do |filepath|
        delete_file(filepath) if File.file?(filepath)
      end
      @created_files = []
    end

    # ensure that provided folder exists, or create it, generate a unique filename
    # @return path to that unique file
    def new_file_path_in_folder(temp_folder, prefix: nil, suffix: nil)
      FileUtils.mkdir_p(temp_folder)
      new_file = File.join(temp_folder, [prefix, SecureRandom.uuid, suffix].compact.join('-'))
      @created_files.push(new_file)
      new_file
    end

    # same as above but in global temp folder, with user's name
    def new_file_path_global(prefix = nil, suffix: nil)
      username =
        begin
          Etc.getlogin || Etc.getpwuid(Process.uid).name || 'unknown_user'
        rescue StandardError
          'unknown_user'
        end
      prefix = [prefix, username].compact.join('-')
      new_file_path_in_folder(@global_temp, prefix: prefix, suffix: suffix)
    end

    def cleanup_expired(temp_folder)
      # garbage collect undeleted files
      Dir.entries(temp_folder).each do |name|
        file_path = File.join(temp_folder, name)
        age_sec = (Time.now - File.stat(file_path).mtime).to_i
        # check age of file, delete too old
        if File.file?(file_path) && (age_sec > FILE_LIST_AGE_MAX_SEC)
          Log.log.debug{"garbage collecting #{name}"}
          delete_file(file_path)
        end
      end
    end
  end
end
