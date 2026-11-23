# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/aoc/graphql, removed in 5.0
require_relative 'log'
require_relative 'plugins/aoc/graphql'
Aspera::Log.log.warn('aspera/graphql is deprecated: use aspera/plugins/aoc/graphql (removed in 5.0)')
module Aspera
  GraphQL = Aspera::Plugins::Aoc::GraphQL
  deprecate_constant :GraphQL
end
