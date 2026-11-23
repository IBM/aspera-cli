# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/server/ascmd, removed in 5.0
require_relative 'log'
require_relative 'plugins/server/ascmd'
Aspera::Log.log.warn('aspera/ascmd is deprecated: use aspera/plugins/server/ascmd (removed in 5.0)')
module Aspera
  AsCmd = Aspera::Plugins::Server::AsCmd
  deprecate_constant :AsCmd
end
