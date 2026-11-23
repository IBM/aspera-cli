# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/aoc/api, removed in 5.0
require_relative '../log'
require_relative '../plugins/aoc/api'
Aspera::Log.log.warn('aspera/api/aoc is deprecated: use aspera/plugins/aoc/api (removed in 5.0)')
module Aspera
  module Api
    AoC = Aspera::Plugins::Aoc::Api
    deprecate_constant :AoC
  end
end
