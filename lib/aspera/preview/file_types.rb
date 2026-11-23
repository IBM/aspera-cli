# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/preview/file_types, removed in 5.0
require_relative '../log'
require_relative '../plugins/preview/file_types'
Aspera::Log.log.warn('aspera/preview/file_types is deprecated: use aspera/plugins/preview/file_types (removed in 5.0)')
module Aspera
  module Preview
    FileTypes = Aspera::Plugins::Preview::FileTypes
    deprecate_constant :FileTypes
  end
end
