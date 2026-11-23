# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transferd/agent, removed in 5.0
require_relative '../log'
require_relative '../plugins/transferd/agent'
Aspera::Log.log.warn('aspera/agent/transferd is deprecated: use aspera/plugins/transferd/agent (removed in 5.0)')
module Aspera
  module Agent
    Transferd = Aspera::Plugins::Transferd::Agent
    deprecate_constant :Transferd
  end
end
