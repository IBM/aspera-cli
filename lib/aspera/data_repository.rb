# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/ascp/data_repository, removed in 5.0
require_relative 'log'
require_relative 'ascp/data_repository'
Aspera::Log.log.warn('aspera/data_repository is deprecated: use aspera/ascp/data_repository (removed in 5.0)')
module Aspera
  DataRepository = Ascp::DataRepository
  deprecate_constant :DataRepository
end
