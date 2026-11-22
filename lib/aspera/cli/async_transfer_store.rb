# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transfer/async_transfer_store, removed in 5.0
require_relative '../log'
require_relative '../plugins/transfer/async_transfer_store'
Aspera::Log.log.warn('aspera/cli/async_transfer_store is deprecated: use aspera/plugins/transfer/async_transfer_store (removed in 5.0)')
module Aspera
  module Cli
    AsyncTransferStore = Aspera::Plugins::Transfer::AsyncTransferStore
    deprecate_constant :AsyncTransferStore
  end
end
