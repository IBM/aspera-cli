# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/aoc/commands, removed in 5.0
# Not a plugin: the bundle `aoc` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/aoc/commands'
Aspera::Log.log.warn('aspera/cli/plugins/aoc is deprecated: use aspera/plugins/aoc/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Aoc = Aspera::Plugins::Aoc::Commands
      deprecate_constant :Aoc
    end
  end
end
