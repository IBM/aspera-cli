# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/transferd/grpc/transferd_services_pb, loaded by aspera/plugins/transferd/api, removed in 5.0
require_relative 'aspera/log'
require_relative 'aspera/plugins/transferd/api'
Aspera::Log.log.warn('transferd_services_pb is deprecated: use aspera/plugins/transferd/api (removed in 5.0)')
