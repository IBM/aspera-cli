# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../environment'

module Aspera
  module Products
    # Client Aspera for Desktop
    class Desktop
      APP_NAME = 'IBM Aspera for Desktop'
      APP_IDENTIFIER = 'com.ibm.software.aspera.desktop'
      LOG_FILENAME = 'ibm-aspera-desktop.log'
      class << self
        # standard folder locations
        def locations
          case Aspera::Environment.instance.os
          when Aspera::Environment::OS_MACOS then [{
            app_root: File.join('', 'Applications', 'IBM Aspera.app'),
            log_root: log_folder,
            sub_bin:  File.join('Contents', 'Resources', 'transferd', 'bin')
          }]
          else []
          end.map { |i| i.merge({expected: APP_NAME}) }
        end

        # Folder of the logs of the application, of `transferd` and of `ascp` (`log_directory` and `fasp_runtime.log.dir` of `transferd`)
        # @return [String, nil] nil if unknown
        def log_folder
          case Aspera::Environment.instance.os
          when Aspera::Environment::OS_MACOS then File.join(Dir.home, 'Library', 'Logs', APP_IDENTIFIER)
          when Aspera::Environment::OS_WINDOWS
            appdata = ENV.fetch('APPDATA', nil)
            File.join(appdata, APP_IDENTIFIER, 'logs') unless appdata.nil?
          else File.join(ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config')), APP_IDENTIFIER, 'logs')
          end
        end
      end
    end
  end
end
