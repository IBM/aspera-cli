# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transfer/ascp_logs_actions, removed in 5.0
require_relative '../log'
require_relative '../plugins/transfer/ascp_logs_actions'
Aspera::Log.log.warn('aspera/cli/ascp_logs_actions is deprecated: use aspera/plugins/transfer/ascp_logs_actions (removed in 5.0)')
module Aspera
  module Cli
    AscpLogsActions = Aspera::Plugins::Transfer::AscpLogsActions
    deprecate_constant :AscpLogsActions
  end
end
