# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/alee/commands, removed in 5.0
require_relative '../../log'
require_relative '../../plugins/alee/commands'
Aspera::Log.log.warn('aspera/cli/plugins/alee is deprecated: use aspera/plugins/alee/commands (removed in 5.0)')
module Aspera
  module Cli
    module Plugins
      Alee = Aspera::Plugins::Alee::Commands
      deprecate_constant :Alee
    end
  end
end
