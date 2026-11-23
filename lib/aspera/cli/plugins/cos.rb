# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/cos/commands, removed in 5.0
# Not a plugin: the bundle `cos` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/cos/commands'
Aspera::Log.log.warn('aspera/cli/plugins/cos is deprecated: use aspera/plugins/cos/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Cos = Aspera::Plugins::Cos::Commands
      deprecate_constant :Cos
    end
  end
end
