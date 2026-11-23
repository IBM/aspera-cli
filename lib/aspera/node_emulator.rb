# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/node/emulator, removed in 5.0
require_relative 'log'
require_relative 'plugins/node/emulator'
Aspera::Log.log.warn('aspera/node_emulator is deprecated: use aspera/plugins/node/emulator (removed in 5.0)')
module Aspera
  NodeEmulator = Aspera::Plugins::Node::Emulator
  NodeEmulatorServlet = Aspera::Plugins::Node::NodeEmulatorServlet
  deprecate_constant :NodeEmulator, :NodeEmulatorServlet
end
