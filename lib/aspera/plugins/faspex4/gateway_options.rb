# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

module Aspera
  module Plugins
    # Faspex 4 gateway: emulation of the Faspex 4 API, started by the commands `gateway` of the bundles `aoc` and `faspex5`
    module Faspex4
      # Options of the gateway (key `faspex4_opts` of the schemas of the bundle).
      # In a file of its own: the servlet (`gw_servlet.rb`, loads `webrick`) is required only when the gateway starts.
      module GatewayOptions
        # Path of the schema of the options
        SCHEMA = 'faspex4_opts:components.schemas.Faspex4GatewayOptions'
      end
    end
  end
end
