# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transferd/commands, removed in 5.0
# Not a plugin: the bundle `transferd` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/transferd/commands'
Aspera::Log.log.warn('aspera/cli/plugins/transferd is deprecated: use aspera/plugins/transferd/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Transferd = Aspera::Plugins::Transferd::Commands
      deprecate_constant :Transferd
    end
  end
end
