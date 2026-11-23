# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/preview/commands, removed in 5.0
# Not a plugin: the bundle `preview` has priority over this file (see `Plugins::Factory#add_lookup_folder`)
require_relative '../../log'
require_relative '../../plugins/preview/commands'
Aspera::Log.log.warn('aspera/cli/plugins/preview is deprecated: use aspera/plugins/preview/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Preview = Aspera::Plugins::Preview::Commands
      deprecate_constant :Preview
    end
  end
end
