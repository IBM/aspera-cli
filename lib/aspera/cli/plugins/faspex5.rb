# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/faspex5/commands, removed in 5.0
# Not a plugin: the bundle `faspex5` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/faspex5/commands'
Aspera::Log.log.warn('aspera/cli/plugins/faspex5 is deprecated: use aspera/plugins/faspex5/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Faspex5 = Aspera::Plugins::Faspex5::Commands
      deprecate_constant :Faspex5
    end
  end
end
