# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/transfer/command_line_builder, removed in 5.0
require_relative 'log'
require_relative 'transfer/command_line_builder'
Aspera::Log.log.warn('aspera/command_line_builder is deprecated: use aspera/transfer/command_line_builder (removed in 5.0)')
module Aspera
  CommandLineBuilder = Transfer::CommandLineBuilder
  deprecate_constant :CommandLineBuilder
end
