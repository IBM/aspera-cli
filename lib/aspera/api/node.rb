# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/node/api, removed in 5.0
require_relative '../log'
require_relative '../plugins/node/api'
Aspera::Log.log.warn('aspera/api/node is deprecated: use aspera/plugins/node/api (removed in 5.0)')
module Aspera
  module Api
    Node = Aspera::Plugins::Node::Api
    NodeFileId = Aspera::Plugins::Node::NodeFileId
    deprecate_constant :Node, :NodeFileId
  end
end
