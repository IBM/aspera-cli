# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/formatter_interface'

# Markdown/HTML formatter for static documentation
# @see Aspera::FormatterInterface
# @see TerminalFormatter (in lib/aspera/cli/terminal_formatter.rb)
module MarkdownFormatter
  include Aspera::FormatterInterface

  # Format special values as HTML entities
  # @param special [String] Special value, e.g. `null`
  # @return [String] Value between escaped angle brackets
  def special_format(special)
    "&lt;#{special}&gt;"
  end

  # Keep Markdown formatting unchanged (pass-through)
  # @param text [#to_s] Text with Markdown formatting
  # @return [String] Same text
  def markdown_text(text)
    text.to_s
  end

  # Format boolean as simple Y or space
  # @param bool [Boolean] Value
  # @return [String] `Y` if true, else a space
  def tick(bool)
    bool ? 'Y' : ' '
  end

  module_function :tick, :special_format, :markdown_text
end
