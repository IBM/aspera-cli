# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/console/commands, removed in 5.0
require_relative '../../log'
require_relative '../../plugins/console/commands'
Aspera::Log.log.warn('aspera/cli/plugins/console is deprecated: use aspera/plugins/console/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Console = Aspera::Plugins::Console::Commands
      deprecate_constant :Console
    end
  end
end
