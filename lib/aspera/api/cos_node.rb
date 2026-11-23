# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/cos/api, removed in 5.0
require_relative '../log'
require_relative '../plugins/cos/api'
Aspera::Log.log.warn('aspera/api/cos_node is deprecated: use aspera/plugins/cos/api (removed in 5.0)')
module Aspera
  module Api
    CosNode = Aspera::Plugins::Cos::Api
    deprecate_constant :CosNode
  end
end
