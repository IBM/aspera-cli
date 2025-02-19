# frozen_string_literal: true

require 'aspera/environment'

module Aspera
  module Products
    # Aspera Desktop Alpha Client
    class Alpha
      APP_NAME = 'IBM Aspera for Desktop'
      APP_IDENTIFIER = 'com.ibm.software.aspera.desktop'
      class << self
        # standard folder locations
        def locations
          case Aspera::Environment.os
          when Aspera::Environment::OS_MACOS then [{
            app_root: File.join('', 'Applications', 'IBM Aspera.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', APP_IDENTIFIER),
            sub_bin:  File.join('Contents', 'Resources', 'transferd', 'bin')
          }]
          else []
          end.map { |i| i.merge({ expected: APP_NAME }) }
        end

        def log_file
          File.join(Dir.home, 'Library', 'Logs', APP_IDENTIFIER, 'ibm-aspera-desktop.log')
        end
      end
    end
  end
end
