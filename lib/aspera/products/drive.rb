# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../environment'

module Aspera
  module Products
    # Aspera Drive (deprecated), macOS only
    class Drive
      APP_NAME = 'Aspera Drive (deprecated)'

      class << self
        # standard folder locations, empty if the product does not exist on this OS
        def locations
          case Aspera::Environment.instance.os
          when Aspera::Environment::OS_MACOS then [{
            app_root: File.join('', 'Applications', 'Aspera Drive.app'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera_Drive'),
            sub_bin:  File.join('Contents', 'Resources')
          }]
          else []
          end.map { |i| {expected: APP_NAME}.merge(i) }
        end
      end
    end
  end
end
