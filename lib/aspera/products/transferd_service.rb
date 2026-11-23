# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transferd/service, removed in 5.0
require_relative '../log'
require_relative '../plugins/transferd/service'
Aspera::Log.log.warn('aspera/products/transferd_service is deprecated: use aspera/plugins/transferd/service (removed in 5.0)')
module Aspera
  module Products
    TransferdService = Aspera::Plugins::Transferd::Service
    deprecate_constant :TransferdService
  end
end
