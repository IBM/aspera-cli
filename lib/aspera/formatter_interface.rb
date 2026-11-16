# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'assert'

module Aspera
  # Common interface for documentation formatters
  # Used by Schema::Documentation to format tables
  module FormatterInterface
    Aspera.require_method!(:tick)
    Aspera.require_method!(:special_format)
    Aspera.require_method!(:markdown_text)
  end
end
