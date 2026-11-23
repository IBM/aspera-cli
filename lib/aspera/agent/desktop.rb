# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/desktop/agent, removed in 5.0
require_relative '../log'
require_relative '../plugins/desktop/agent'
Aspera::Log.log.warn('aspera/agent/desktop is deprecated: use aspera/plugins/desktop/agent (removed in 5.0)')
module Aspera
  module Agent
    Desktop = Aspera::Plugins::Desktop::Agent
    deprecate_constant :Desktop
  end
end
