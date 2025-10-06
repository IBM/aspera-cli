# frozen_string_literal: true

require 'aspera/environment'

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
            log_root: File.join(Dir.home, 'Library', 'Logs', APP_IDENTIFIER),
            sub_bin:  File.join('Contents', 'Resources', 'transferd', 'bin')
          }]
          else []
          end.map{ |i| i.merge({expected: APP_NAME})}
        end
      end
    end
  end
end
