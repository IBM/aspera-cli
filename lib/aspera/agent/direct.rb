# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/direct/agent, removed in 5.0
require_relative '../log'
require_relative '../plugins/direct/agent'
Aspera::Log.log.warn('aspera/agent/direct is deprecated: use aspera/plugins/direct/agent (removed in 5.0)')
module Aspera
  module Agent
    Direct = Aspera::Plugins::Direct::Agent
    deprecate_constant :Direct
  end
end
