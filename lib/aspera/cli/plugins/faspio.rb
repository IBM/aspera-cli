# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/faspio/commands, removed in 5.0
require_relative '../../log'
require_relative '../../plugins/faspio/commands'
Aspera::Log.log.warn('aspera/cli/plugins/faspio is deprecated: use aspera/plugins/faspio/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Faspio = Aspera::Plugins::Faspio::Commands
      deprecate_constant :Faspio
    end
  end
end
