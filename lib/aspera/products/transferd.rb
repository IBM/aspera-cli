# frozen_string_literal: true

module Aspera
  module Products
    class Transferd
      APP_NAME = 'IBM Aspera Transfer Daemon'
      class << self
        # standard folder locations
        def locations
          [{
            app_root: sdk_directory,
            sub_bin:  ''
          }].map { |i| i.merge({ expected: APP_NAME }) }
        end

        # location of SDK files
        def sdk_directory=(v)
          Log.log.debug{"sdk_directory=#{v}"}
          @sdk_dir = v
          sdk_directory
        end

        # @return the path to folder where SDK is installed
        def sdk_directory
          Aspera.assert(!@sdk_dir.nil?){'SDK path was not initialized'}
          FileUtils.mkdir_p(@sdk_dir)
          @sdk_dir
        end

        def transferd_path
          return File.join(sdk_directory, Environment.exe_file('transferd')) # cspell:disable-line
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
          raise 'Port not found in daemon logs' if result.nil?
          Log.log.debug{"Got port #{result} from log"}
          return result
        end
      end
    end
  end
end
