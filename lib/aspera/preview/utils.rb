# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/preview/utils, removed in 5.0
require_relative '../log'
require_relative '../plugins/preview/utils'
Aspera::Log.log.warn('aspera/preview/utils is deprecated: use aspera/plugins/preview/utils (removed in 5.0)')
module Aspera
  module Preview
    Utils = Aspera::Plugins::Preview::Utils
    deprecate_constant :Utils
  end
end
