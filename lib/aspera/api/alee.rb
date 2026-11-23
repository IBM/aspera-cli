# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/alee/api, removed in 5.0
require_relative '../log'
require_relative '../plugins/alee/api'
Aspera::Log.log.warn('aspera/api/alee is deprecated: use aspera/plugins/alee/api (removed in 5.0)')
module Aspera
  module Api
    Alee = Aspera::Plugins::Alee::Api
    deprecate_constant :Alee
  end
end
