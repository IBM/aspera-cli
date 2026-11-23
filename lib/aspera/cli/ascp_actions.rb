# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transfer_agents/ascp_actions, removed in 5.0
require_relative '../log'
require_relative '../plugins/transfer_agents/ascp_actions'
Aspera::Log.log.warn('aspera/cli/ascp_actions is deprecated: use aspera/plugins/transfer_agents/ascp_actions (removed in 5.0)')
module Aspera
  module Cli
    AscpActions = Aspera::Plugins::TransferAgents::AscpActions
    deprecate_constant :AscpActions
  end
end
