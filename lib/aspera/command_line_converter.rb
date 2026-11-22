# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/transfer/command_line_converter, removed in 5.0
require_relative 'log'
require_relative 'transfer/command_line_converter'
Aspera::Log.log.warn('aspera/command_line_converter is deprecated: use aspera/transfer/command_line_converter (removed in 5.0)')
module Aspera
  CommandLineConverter = Transfer::CommandLineConverter
  deprecate_constant :CommandLineConverter
end
