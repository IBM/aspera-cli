# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
module Aspera
  module Products
    class Transferd
      APP_NAME = 'IBM Aspera Transfer Daemon'
      V1_DAEMON_NAME = 'asperatransferd'
      # from 1.1.5
      V2_DAEMON_NAME = 'transferd'
      # folders to extract from SDK archive
      RUNTIME_FOLDERS = %w[bin lib sbin aspera].freeze
      class << self
        # standard folder locations
        def locations
          [{
            app_root: sdk_directory,
            sub_bin:  ''
          }].map{ |i| i.merge({expected: APP_NAME})}
        end

        # location of SDK files
        def sdk_directory=(folder)
          Log.log.debug{"sdk_directory=#{folder}"}
          @sdk_dir = folder
          sdk_directory
        end

        # @return the path to folder where SDK is installed
        def sdk_directory
          Aspera.assert(!@sdk_dir.nil?){'SDK path was not initialized'}
          @sdk_dir
        end

        def transferd_path
          v1_path = File.join(sdk_directory, Environment.instance.exe_file(V1_DAEMON_NAME))
          return v1_path if File.exist?(v1_path)
          return File.join(sdk_directory, Environment.instance.exe_file(V2_DAEMON_NAME))
        end

        # Well, the port number is only in log file
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
          Aspera.assert(!result.nil?){'Port not found in daemon logs'}
          Log.log.debug{"Got port #{result} from log"}
          return result
        end
      end
    end
  end
end
