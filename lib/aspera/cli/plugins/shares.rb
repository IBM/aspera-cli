# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/shares/commands, removed in 5.0
# Not a plugin: the bundle `shares` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/shares/commands'
Aspera::Log.log.warn('aspera/cli/plugins/shares is deprecated: use aspera/plugins/shares/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Shares = Aspera::Plugins::Shares::Commands
      deprecate_constant :Shares
    end
  end
end
