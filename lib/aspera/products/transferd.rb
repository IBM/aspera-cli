# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../environment'
require_relative '../log'
require_relative '../assert'
module Aspera
  module Products
    class Transferd
      APP_NAME = 'IBM Aspera Transfer Daemon'
      V1_DAEMON_NAME = 'asperatransferd'
      # from 1.1.5
      V2_DAEMON_NAME = 'transferd'
      # folders to extract from SDK archive
      RUNTIME_FOLDERS = %w[bin lib sbin aspera].freeze
      # Configuration file of the service installed by `transferd service install`, also the default of the daemon
      SERVICE_CONFIG_FILE = '/etc/transferd/transferd.json'
      # Files `<name>.<port>.optport` where the daemon started with port zero writes its port, in its `runtime_dir` (from 1.1.7)
      PORT_FILE_PATTERN = '*.optport'
      class << self
        # standard folder locations
        def locations
          [{
            app_root: sdk_directory,
            sub_bin:  ''
          }].map { |i| i.merge({expected: APP_NAME}) }
        end

        # location of SDK files
        def sdk_directory=(folder)
          Log.log.debug { "sdk_directory=#{folder}" }
          @sdk_dir = folder
          sdk_directory
        end

        # @return [String] the path to folder where SDK is or should be installed
        def sdk_directory
          Aspera.assert(!@sdk_dir.nil?, 'SDK path was not initialized')
          @sdk_dir
        end

        def transferd_path
          v1_path = File.join(sdk_directory, Environment.instance.exe_file(V1_DAEMON_NAME))
          return v1_path if File.exist?(v1_path)
          return File.join(sdk_directory, Environment.instance.exe_file(V2_DAEMON_NAME))
        end

        # Port of a daemon started locally with port zero, from the file it writes in its `runtime_dir` once it listens (from 1.1.7)
        # @param runtime_dir [String] Folder `runtime_dir` of the daemon, used by this daemon only
        # @return [Integer, nil] Port of the file, `nil`: no file (version before 1.1.7, or not listening yet), or file being written (empty)
        # @raise [AssertError] The file has no port, or there are several: retrying does not help
        def daemon_port_from_file(runtime_dir)
          # `base`: the path of the folder is not a pattern
          files = Dir.glob(PORT_FILE_PATTERN, base: runtime_dir).map { |name| File.join(runtime_dir, name) }
          return if files.empty?
          Aspera.assert(files.length.eql?(1)) { "Several port files in #{runtime_dir}: #{files.join(', ')}" }
          # The file is created, then written
          content = File.read(files.first)
          return if content.empty?
          Aspera.assert(content.match?(/\A[0-9]+\z/)) { "No port in file #{files.first}" }
          Log.log.debug { "Got port #{content} from #{files.first}" }
          return content.to_i
        end

        # Port of a daemon started locally with port zero, from its log: transferd before 1.1.7 writes it only there (see `daemon_port_from_file`)
        # @param log_file [String] Log file (standard output) of a daemon started locally
        # @return [Integer, nil] Port of the last line of the API server, `nil`: not listening yet
        def daemon_port_from_log(log_file)
          result = nil
          # if port is zero, a dynamic port was created, get it
          File.open(log_file, 'r') do |file|
            file.each_line do |line|
              # Well, it's tricky to depend on log
              if (m = line.match(/Info: API Server: Listening on ([^:]+):(\d+) /))
                result = m[2].to_i
                # no "break" , need to read last matching log line
              end
            end
          end
          Log.log.debug { "Got port #{result} from log" } unless result.nil?
          return result
        end
      end
    end
  end
end
