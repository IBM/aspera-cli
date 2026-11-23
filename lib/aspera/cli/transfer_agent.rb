# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transfer_agents/transfer_agent, removed in 5.0
require_relative '../log'
require_relative '../plugins/transfer_agents/transfer_agent'
Aspera::Log.log.warn('aspera/cli/transfer_agent is deprecated: use aspera/plugins/transfer_agents/transfer_agent (removed in 5.0)')
module Aspera
  module Cli
    TransferAgent = Aspera::Plugins::TransferAgents::TransferAgent
    deprecate_constant :TransferAgent
  end
end
