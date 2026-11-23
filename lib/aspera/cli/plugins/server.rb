# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/server/commands, removed in 5.0
# Not a plugin: the bundle `server` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/server/commands'
Aspera::Log.log.warn('aspera/cli/plugins/server is deprecated: use aspera/plugins/server/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Server = Aspera::Plugins::Server::Commands
      deprecate_constant :Server
    end
  end
end
