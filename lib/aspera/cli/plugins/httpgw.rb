# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/httpgw/commands, removed in 5.0
# Not a plugin: the bundle `httpgw` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/httpgw/commands'
Aspera::Log.log.warn('aspera/cli/plugins/httpgw is deprecated: use aspera/plugins/httpgw/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Httpgw = Aspera::Plugins::Httpgw::Commands
      deprecate_constant :Httpgw
    end
  end
end
