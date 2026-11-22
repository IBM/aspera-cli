# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transfer/sync_actions, removed in 5.0
require_relative '../log'
require_relative '../plugins/transfer/sync_actions'
Aspera::Log.log.warn('aspera/cli/sync_actions is deprecated: use aspera/plugins/transfer/sync_actions (removed in 5.0)')
module Aspera
  module Cli
    SyncActions = Aspera::Plugins::Transfer::SyncActions
    deprecate_constant :SyncActions
  end
end
