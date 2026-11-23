# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/httpgw/api, removed in 5.0
require_relative '../log'
require_relative '../plugins/httpgw/api'
Aspera::Log.log.warn('aspera/api/httpgw is deprecated: use aspera/plugins/httpgw/api (removed in 5.0)')
module Aspera
  module Api
    Httpgw = Aspera::Plugins::Httpgw::Api
    deprecate_constant :Httpgw
  end
end
