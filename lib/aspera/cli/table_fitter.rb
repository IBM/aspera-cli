# frozen_string_literal: true

require 'terminal-table'
require 'unicode/display_width'

module Aspera
  module Cli
    # Build a terminal table that fits in a given width, by word-wrapping cells.
    # Only columns with text (containing spaces, e.g. `description`) are wrapped, the widest first.
    # Other columns (names, identifiers) keep their width.
    # If the table cannot fit, it is displayed with its natural width.
    module TableFitter
      # Minimum width of a wrapped column
      MIN_WRAP_WIDTH = 10
      private_constant :MIN_WRAP_WIDTH

      class << self
        # @param headings [Array]                 Column names
        # @param rows     [Array<Array<String>>]  Rows of cells
        # @param style    [Hash]                  `Terminal::Table` style
        # @param width    [Integer, nil]          Maximum width of the table, or `nil` for natural width
        # @return [Terminal::Table]
        def table(headings:, rows:, style:, width:)
          headings, rows = fit(headings, rows, width - overhead(headings.length, style)) unless width.nil?
          Terminal::Table.new(headings: headings, rows: rows, style: style)
        end

        private

        # @return [Integer] Width taken by borders and padding for a table with that number of columns
        def overhead(column_count, style)
          Terminal::Table.new(headings: [''] * column_count, style: style.except(:width)).to_s.lines.map { |line| display_width(line.chomp) }.max
        end

        # @param available [Integer] Width available for the content of all columns
        # @return [Array] Headings and rows, wrapped to fit in available width, or unchanged if not possible
        def fit(headings, rows, available)
          lines = [headings, *rows].map { |row| row.map(&:to_s) }
          columns = lines.transpose
          natural = columns.map { |cells| cells.flat_map { |cell| cell.split("\n") }.map { |line| display_width(line) }.max || 0 }
          minimum = columns.zip(natural).map do |cells, nat|
            next nat unless cells.any? { |cell| cell.match?(/[ \t]/) }
            # not narrower than heading
            MIN_WRAP_WIDTH.clamp(display_width(cells.first), nat)
          end
          return [headings, rows] if natural.sum <= available || minimum.sum > available
          # Columns wider than `limit` are narrowed to it, but not below their minimum
          widths_for = ->(limit) { natural.zip(minimum).map { |nat, min| limit.clamp(min, nat) } }
          limit = (0..natural.max).bsearch { |l| widths_for.call(l).sum > available } - 1
          widths = widths_for.call(limit)
          wrapped = lines.map { |row| row.each_with_index.map { |cell, i| word_wrap(cell, widths[i]) } }
          [wrapped.first, wrapped.drop(1)]
        end

        # @return [String] Text with lines longer than width wrapped on spaces
        def word_wrap(text, width)
          text.split("\n").map do |line|
            next line if display_width(line) <= width
            line.split.flat_map { |word| break_word(word, width) }.each_with_object([]) do |word, result|
              if !result.empty? && display_width(result.last) + 1 + display_width(word) <= width
                result[-1] = "#{result.last} #{word}"
              else
                result.push(word)
              end
            end.join("\n")
          end.join("\n")
        end

        # @return [Array<String>] Word split in pieces not wider than width (words with ANSI escape sequences are not split)
        def break_word(word, width)
          return [word] if display_width(word) <= width || word.include?("\e")
          word.each_char.with_object(['']) do |char, pieces|
            pieces.push('') if !pieces.last.empty? && display_width(pieces.last + char) > width
            pieces[-1] = pieces.last + char
          end
        end

        # @return [Integer] Number of terminal columns used to display the string, ignoring ANSI escape sequences
        def display_width(string)
          Unicode::DisplayWidth.of(Terminal::Table::Util.ansi_escape(string))
        end
      end
    end
  end
end
