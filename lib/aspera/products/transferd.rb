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
      end
    end
  end
end
