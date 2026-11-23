# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/httpgw/agent, removed in 5.0
require_relative '../log'
require_relative '../plugins/httpgw/agent'
Aspera::Log.log.warn('aspera/agent/httpgw is deprecated: use aspera/plugins/httpgw/agent (removed in 5.0)')
module Aspera
  module Agent
    Httpgw = Aspera::Plugins::Httpgw::Agent
    deprecate_constant :Httpgw
  end
end
