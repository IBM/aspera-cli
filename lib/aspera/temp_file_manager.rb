# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/log'
require 'singleton'
require 'fileutils'
require 'etc'
require 'tmpdir'

module Aspera
  # create a temp file name for a given folder
  # files can be deleted on process exit by calling cleanup
  #
  # @!method self.instance
  #   Returns the singleton instance of TempFileManager
  #   @return [TempFileManager] the singleton instance
  class TempFileManager
    include Singleton

    # Assume no transfer lasts longer than this
    # (garbage collect file lists which were not deleted after transfer)
    EXPIRY_DEFAULT_SEC = 5 * 86_400
    private_constant :EXPIRY_DEFAULT_SEC

    # @return [Boolean] `true`: files created by this execution are deleted by `cleanup`
    attr_accessor :cleanup_on_exit
    # @return [Numeric, nil] Age in seconds of files deleted by `cleanup_expired`, `nil`: never deleted
    attr_reader :expiry_sec
    attr_reader :global_temp

    def initialize
      @created_files = []
      # Number of holders of a created file: not deleted by cleanup while held
      @hold_counts = {}
      # Files are created and released by transfer threads
      @mutex = Mutex.new
      @cleanup_on_exit = true
      @expiry_sec = EXPIRY_DEFAULT_SEC
      @global_temp = Etc.systmpdir
    end

    # @param value [Numeric, nil] Age in seconds, `0`: all files, `nil`: never delete
    def expiry_sec=(value)
      Aspera.assert(value.nil? || (value.is_a?(Numeric) && !value.negative?), type: ParameterError) { "Expiry must be a positive duration: #{value}" }
      @expiry_sec = value
    end

    def global_temp=(value)
      @global_temp = case value
      when '@env' then Dir.tmpdir
      when '@sys' then Etc.systmpdir
      else value
      end
    end

    def delete_file(filepath)
      remove_file(filepath) if @cleanup_on_exit
    end

    # Call this on process exit, or at the end of a command.
    # Held files are kept: they are deleted when released.
    def cleanup
      @mutex.synchronize do
        @created_files.each do |filepath|
          delete_file(filepath) if !@hold_counts.key?(filepath) && File.file?(filepath)
        end
        @created_files.select! { |filepath| @hold_counts.key?(filepath) }
      end
    end

    # Keep created files after `cleanup`, until released, for example a file list used by a transfer
    # that ends after the command (asynchronous transfer).
    # A file can be held several times (multi-session): it is deleted when the last holder releases it.
    # @param paths [Array<String>] Files created by this manager (others are ignored)
    def hold(paths)
      @mutex.synchronize do
        paths.each do |filepath|
          @hold_counts[filepath] = @hold_counts.fetch(filepath, 0) + 1 if @created_files.include?(filepath)
        end
      end
    end

    # Release files held with `hold`, and delete those that are no longer held.
    # @param paths [Array<String>] Files given to `hold`
    def release(paths)
      @mutex.synchronize do
        paths.each do |filepath|
          next unless @hold_counts.key?(filepath)
          @hold_counts[filepath] -= 1
          next if @hold_counts[filepath].positive?
          @hold_counts.delete(filepath)
          @created_files.delete(filepath)
          delete_file(filepath) if File.file?(filepath)
        end
      end
    end

    # Ensure that provided folder exists, or create it, atomically create and reserve a unique file.
    # The file is created immediately (O_EXCL) to prevent TOCTOU race conditions.
    # @return [String] path to that unique file
    def new_file_path_in_folder(temp_folder, prefix: nil, suffix: nil)
      FileUtils.mkdir_p(temp_folder)
      basename = [prefix || 'aspera', SecureRandom.uuid].join('-')
      # Create the file atomically with O_EXCL (retry with another name if it exists)
      # Note: Tempfile is not used, as its file is deleted when the object is garbage collected
      new_file = Dir::Tmpname.create([basename, suffix ? "-#{suffix}" : ''], temp_folder) do |path|
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { nil }
      end
      @mutex.synchronize { @created_files.push(new_file) }
      new_file
    end

    # Same as above but in global temp folder, with user's name
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

    # Generate a unique directory path inside the global temp folder (does NOT create it).
    # Unlike new_file_path_global, the caller is expected to use the path as a directory.
    # @return [String] path to a unique (not yet existing) directory
    def new_dir_path_global(prefix = nil)
      username =
        begin
          Etc.getlogin || Etc.getpwuid(Process.uid).name || 'unknown_user'
        rescue StandardError
          'unknown_user'
        end
      dir_name = [prefix, username, SecureRandom.uuid].compact.join('-')
      File.join(@global_temp, dir_name)
    end

    # Garbage collect files not deleted by previous executions (e.g. killed), older than `expiry_sec`.
    # Not disabled by `cleanup_on_exit`, which applies to files of this execution.
    # @param temp_folder [String] Folder that contains only temporary files
    def cleanup_expired(temp_folder)
      return if @expiry_sec.nil?
      now = Time.now
      Dir.entries(temp_folder).each do |name|
        file_path = File.join(temp_folder, name)
        # check age of file, delete too old
        next unless File.file?(file_path) && (now - File.mtime(file_path)) >= @expiry_sec
        Log.log.debug { "garbage collecting #{name}" }
        remove_file(file_path)
      rescue Errno::ENOENT
        # deleted meanwhile by another execution
        nil
      end
    end

    private

    # Delete a file, a failure is logged
    def remove_file(filepath)
      File.delete(filepath)
    rescue Errno::ENOENT
      nil
    rescue => e
      Log.log.warn { "Problem deleting file: #{filepath}: #{e.message}" }
    end
  end
end
