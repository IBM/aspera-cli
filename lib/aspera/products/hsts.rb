# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../environment'

module Aspera
  module Products
    # IBM Aspera High-Speed Transfer Server
    class Hsts
      APP_NAME = 'IBM Aspera High-Speed Transfer Server'

      class << self
        # standard folder locations
        def locations
          case Aspera::Environment.instance.os
          when Aspera::Environment::OS_WINDOWS then [{
            app_root: File.join('C:', 'Program Files', 'Aspera', 'Enterprise Server'),
            log_root: File.join('C:', 'Program Files', 'Aspera', 'Enterprise Server', 'var', 'log')
          }]
          when Aspera::Environment::OS_MACOS then [{
            app_root: File.join('', 'Library', 'Aspera'),
            log_root: File.join(Dir.home, 'Library', 'Logs', 'Aspera')
          }]
          else [{ # other: Linux and Unix family
            app_root: File.join('', 'opt', 'aspera')
          }]
          end.map { |i| {expected: APP_NAME}.merge(i) }
        end
      end
    end
  end
end
