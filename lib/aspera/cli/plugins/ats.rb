# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/ats/commands, removed in 5.0
# Not a plugin: the bundle `ats` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/ats/commands'
Aspera::Log.log.warn('aspera/cli/plugins/ats is deprecated: use aspera/plugins/ats/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Ats = Aspera::Plugins::Ats::Commands
      deprecate_constant :Ats
    end
  end
end
