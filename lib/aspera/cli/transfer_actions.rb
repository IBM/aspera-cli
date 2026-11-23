# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transfer_agents/transfer_actions, removed in 5.0
require_relative '../log'
require_relative '../plugins/transfer_agents/transfer_actions'
Aspera::Log.log.warn('aspera/cli/transfer_actions is deprecated: use aspera/plugins/transfer_agents/transfer_actions (removed in 5.0)')
module Aspera
  module Cli
    TransferActions = Aspera::Plugins::TransferAgents::TransferActions
    deprecate_constant :TransferActions
  end
end
