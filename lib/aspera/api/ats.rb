# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/ats/api, removed in 5.0
require_relative '../log'
require_relative '../plugins/ats/api'
Aspera::Log.log.warn('aspera/api/ats is deprecated: use aspera/plugins/ats/api (removed in 5.0)')
module Aspera
  module Api
    Ats = Aspera::Plugins::Ats::Api
    deprecate_constant :Ats
  end
end
