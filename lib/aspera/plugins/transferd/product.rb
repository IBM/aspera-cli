# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../environment'
require_relative '../../log'
require_relative '../../assert'
require_relative '../../temp_file_manager'
require_relative '../../ascp/installation'
require_relative '../../products/transferd'
require 'json'
require 'fileutils'
require 'securerandom'
require 'timeout'

module Aspera
  module Plugins
    module Transferd
      # A Transfer Daemon (`transferd`) started by this process on a local address, with the SDK of `Products::Transferd.sdk_directory`:
      # configuration file and logs in the global temporary folder.
      class Product
        # Size in bytes of the random API key of a daemon started here (same as `transferd service`)
        API_KEY_BYTES = 32

        private_constant :API_KEY_BYTES

        class << self
          # API key of a daemon started here
          # @param api_key [String, nil] API key given by the user
          # @param stop    [Boolean]     `true` if the daemon is stopped on exit
          # @return [String, nil] The key given, else a random one if the daemon is stopped on exit,
          #   else `nil` (no authentication): the next executions that attach to the daemon left running cannot know a random key
          def daemon_api_key(api_key, stop:)
            return api_key unless api_key.nil?
            return SecureRandom.hex(API_KEY_BYTES) if stop
            Log.log.warn('Daemon left running (stop: false) without authentication: other users of the host can use it. Set parameter api_key.')
            nil
          end

          # Write the configuration file of a daemon started here: created only by this call, readable only by the user (it may contain the API key)
          # @param path   [String] Path of the file, in the global temporary folder
          # @param config [Hash]   Configuration of the daemon
          def write_config(path, config)
            File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(config.to_json) }
          end
        end

        # Start the daemon, and wait for its initialization
        # @param address [String]      Local address the daemon listens on
        # @param port    [Integer]     Port the daemon listens on, `0`: a random available port (see `listen_port`)
        # @param api_key [String, nil] API key given by the user (see `daemon_api_key`)
        # @param stop    [Boolean]     `false`: the daemon is left running on exit
        # @raise [RuntimeError] The daemon exited during its initialization
        def initialize(address:, port:, api_key:, stop:)
          # The daemon listens on a local port: clients must give its API key, so that other users of the host cannot use it
          @api_key = self.class.daemon_api_key(api_key, stop: stop)
          # create a config file for daemon
          config = {
            address:      address,
            port:         port,
            fasp_runtime: {
              use_embedded: false,
              user_defined: {
                bin: Products::Transferd.sdk_directory,
                etc: Products::Transferd.sdk_directory
              }
            }
          }
          config[:authentication] = {enabled: true, api_key: @api_key} unless @api_key.nil?
          # config file and logs are created in same folder
          transferd_base_tmp = TempFileManager.instance.new_file_path_global('transferd')
          Log.log.debug { "transferd base tmp #{transferd_base_tmp}" }
          conf_file = "#{transferd_base_tmp}.conf"
          @log_stdout = "#{transferd_base_tmp}.out"
          @log_stderr = "#{transferd_base_tmp}.err"
          # Folder of the port file of a daemon started with port zero (see `listen_port`): of this daemon only (the default is shared),
          # created here, readable only by the user
          @runtime_dir = nil
          if port.zero?
            @runtime_dir = "#{transferd_base_tmp}.run"
            Dir.mkdir(@runtime_dir, 0o700)
            config[:runtime_dir] = @runtime_dir
          end
          self.class.write_config(conf_file, config)
          @pid = Environment.secure_execute(
            Ascp::Installation.instance.path(:transferd), '--config', conf_file,
            mode: :background,
            out: @log_stdout,
            err: @log_stderr
          )
          begin
            # wait for process to initialize, max 2 seconds
            Timeout.timeout(2.0) do
              # this returns if process dies (within 2 seconds)
              _, status = ::Process.wait2(@pid)
              remove_runtime_dir
              raise "Transfer daemon exited with status #{status.exitstatus}. Check files: #{log_files.join(' and ')}"
            end
          rescue Timeout::Error
            nil
          end
          Log.log.debug { "Daemon started with pid #{@pid}" }
          ::Process.detach(@pid) unless stop
        end

        # @return [Integer, nil] PID of the daemon, `nil` once stopped
        attr_reader :pid
        # @return [String, nil] API key of the daemon, `nil`: no authentication
        attr_reader :api_key

        # @return [Array(String, String)] Files of the standard output and error of the daemon
        def log_files
          [@log_stdout, @log_stderr]
        end

        # @return [Integer, nil] Port the daemon started with port `0` listens on: from its port file (transferd 1.1.7 and later), else from its log;
        #   `nil`: it does not listen yet
        # @raise [AssertError] Not started with port zero, or port file not valid: retrying does not help
        def listen_port
          Aspera.assert(!@runtime_dir.nil?) { 'Daemon not started with port zero' }
          # Written before the log
          Products::Transferd.daemon_port_from_file(@runtime_dir) || Products::Transferd.daemon_port_from_log(@log_stdout)
        end

        # Stop the daemon, if not stopped yet
        def stop
          return if @pid.nil?
          Log.log.debug("Stopping daemon #{@pid}")
          ::Process.kill(:KILL, @pid)
          _, status = ::Process.wait2(@pid)
          Log.log.debug("daemon stopped #{status}")
          @pid = nil
          remove_runtime_dir
        end

        private

        # Delete the folder of the port file: the daemon deletes its port file only when interrupted (`SIGINT`), not when killed
        def remove_runtime_dir
          FileUtils.rm_rf(@runtime_dir) unless @runtime_dir.nil?
        end
      end
    end
  end
end
