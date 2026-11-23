# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/connect/agent, removed in 5.0
require_relative '../log'
require_relative '../plugins/connect/agent'
Aspera::Log.log.warn('aspera/agent/connect is deprecated: use aspera/plugins/connect/agent (removed in 5.0)')
module Aspera
  module Agent
    Connect = Aspera::Plugins::Connect::Agent
    deprecate_constant :Connect
  end
end
