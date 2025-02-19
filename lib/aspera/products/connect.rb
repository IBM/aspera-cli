# frozen_string_literal: true

require 'aspera/environment'

module Aspera
  module Products
    class Connect
      APP_NAME = 'IBM Aspera Connect'
      class << self
        # standard folder locations
        def locations
          case Aspera::Environment.os
          when Aspera::Environment::OS_WINDOWS then [{
            app_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Programs', 'Aspera', 'Aspera Connect'),
            log_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Aspera', 'Aspera Connect', 'var', 'log'),
            run_root: File.join(ENV.fetch('LOCALAPPDATA', nil), 'Aspera', 'Aspera Connect')
          }]
          when Aspera::Environment::OS_MACOS then [{
            app_root: File.join(Dir.home, 'Applications', 'Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }, {
            app_root: File.join('', 'Applications', 'Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }, {
            app_root: File.join(Dir.home, 'Applications', 'IBM Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }, {
            app_root: File.join('', 'Applications', 'IBM Aspera Connect.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Connect'),
            run_root: File.join(Dir.home, 'Library', 'Application Support', 'Aspera', 'Aspera Connect'),
            sub_bin:  File.join('Contents', 'Resources')
          }]
          else [{ # other: Linux and Unix family
            app_root: File.join(Dir.home, '.aspera', 'connect'),
            run_root: File.join(Dir.home, '.aspera', 'connect')
          }]
          end.map { |i| i.merge({ expected: APP_NAME }) }
        end
      end
    end
  end
end
