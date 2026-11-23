# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/orchestrator/commands, removed in 5.0
# Not a plugin: the bundle `orchestrator` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/orchestrator/commands'
Aspera::Log.log.warn('aspera/cli/plugins/orchestrator is deprecated: use aspera/plugins/orchestrator/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Orchestrator = Aspera::Plugins::Orchestrator::Commands
      deprecate_constant :Orchestrator
    end
  end
end
