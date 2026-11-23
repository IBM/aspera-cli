# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/node/agent, removed in 5.0
require_relative '../log'
require_relative '../plugins/node/agent'
Aspera::Log.log.warn('aspera/agent/node is deprecated: use aspera/plugins/node/agent (removed in 5.0)')
module Aspera
  module Agent
    Node = Aspera::Plugins::Node::Agent
    deprecate_constant :Node
  end
end
