# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/node/commands, removed in 5.0
# Not a plugin: the bundle `node` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/node/commands'
Aspera::Log.log.warn('aspera/cli/plugins/node is deprecated: use aspera/plugins/node/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Node = Aspera::Plugins::Node::Commands
      deprecate_constant :Node
    end
  end
end
