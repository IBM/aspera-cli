# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/shares/shares_web, removed in 5.0
require_relative '../../log'
require_relative '../../plugins/shares/shares_web'
Aspera::Log.log.warn('aspera/oauth/client/shares_web is deprecated: use aspera/plugins/shares/shares_web (removed in 5.0)')
module Aspera
  module OAuth
    SharesWeb = Aspera::Plugins::Shares::SharesWeb
    deprecate_constant :SharesWeb
  end
end
