# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/preview/generator, removed in 5.0
require_relative '../log'
require_relative '../plugins/preview/generator'
Aspera::Log.log.warn('aspera/preview/generator is deprecated: use aspera/plugins/preview/generator (removed in 5.0)')
module Aspera
  module Preview
    Generator = Aspera::Plugins::Preview::Generator
    deprecate_constant :Generator
  end
end
