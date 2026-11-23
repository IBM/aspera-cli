# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/faspex5/api, removed in 5.0
require_relative '../log'
require_relative '../plugins/faspex5/api'
Aspera::Log.log.warn('aspera/api/faspex is deprecated: use aspera/plugins/faspex5/api (removed in 5.0)')
module Aspera
  FaspexPubLink = Aspera::Plugins::Faspex5::FaspexPubLink
  deprecate_constant :FaspexPubLink
  module Api
    Faspex = Aspera::Plugins::Faspex5::Api
    deprecate_constant :Faspex
  end
end
