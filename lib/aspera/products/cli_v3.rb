# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../environment'

module Aspera
  module Products
    # Aspera CLI version 3 (deprecated)
    class CliV3
      APP_NAME = 'Aspera CLI (deprecated)'

      class << self
        # standard folder locations
        def locations
          case Aspera::Environment.instance.os
          when Aspera::Environment::OS_WINDOWS then [{
            app_root: File.join('C:', 'Program Files', 'Aspera', 'cli'),
            log_root: File.join('C:', 'Program Files', 'Aspera', 'cli', 'var', 'log')
          }]
          when Aspera::Environment::OS_MACOS then [{
            app_root: File.join(Dir.home, 'Applications', 'Aspera CLI'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera')
          }]
          else [{ # other: Linux and Unix family
            app_root: File.join(Dir.home, '.aspera', 'cli')
          }]
          end.map { |i| {expected: APP_NAME}.merge(i) }
        end
      end
    end
  end
end
