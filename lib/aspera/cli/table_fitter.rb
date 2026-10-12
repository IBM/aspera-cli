# frozen_string_literal: true

require 'terminal-table'
require 'unicode/display_width'

module Aspera
  module Cli
    # Build a terminal table that fits in a given width, by wrapping cells.
    # Columns with text (containing spaces, e.g. `description`) are wrapped first, the widest first.
    # If not enough, other columns (names, identifiers) are wrapped too.
    # If the table cannot fit, columns are narrowed to their minimum width.
    module TableFitter
      # Minimum width of a wrapped column with text
      MIN_TEXT_WIDTH = 20
      # Minimum width of other wrapped columns
      MIN_WIDTH = 10
      # ANSI style (zero width)
      STYLE = /\e\[[0-9;]*m/
      # Styles that reset all styles
      RESETS = ["\e[0m", "\e[m"].freeze
      # ANSI style or character
      TOKEN = /#{STYLE}|\X/
      # Long words are preferably broken after one of these characters
      BREAK_AFTER = %r{[-_./,=]}
      private_constant :MIN_TEXT_WIDTH, :MIN_WIDTH, :STYLE, :RESETS, :TOKEN, :BREAK_AFTER

      class << self
        # @param headings [Array]                 Column names
        # @param rows     [Array<Array<String>>]  Rows of cells
        # @param style    [Hash]                  `Terminal::Table` style
        # @param width    [Integer, nil]          Maximum width of the table, or `nil` for natural width (not a `style` parameter)
        # @return [Terminal::Table]
        def table(headings:, rows:, style:, width:)
          headings, rows = fit(headings, rows, width - overhead(headings.length, style)) unless width.nil?
          Terminal::Table.new(headings: headings, rows: rows, style: style)
        end

        private

        # @return [Integer] Width taken by borders and padding for a table with that number of columns
        def overhead(column_count, style)
          Terminal::Table.new(headings: [''] * column_count, style: style).to_s.lines.map { |line| display_width(line.chomp) }.max
        end

        # @param available [Integer] Width available for the content of all columns
        # @return [Array] Headings and rows, wrapped to fit in available width, or as narrow as possible
        def fit(headings, rows, available)
          lines = [headings, *rows].map { |row| row.map(&:to_s) }
          columns = lines.transpose
          natural = columns.map { |cells| cells.flat_map { |cell| cell.split("\n") }.map { |line| display_width(line) }.max || 0 }
          return [headings, rows] if natural.sum <= available
          text = columns.map { |cells| cells.any? { |cell| cell.match?(/[ \t]/) } }
          # Minimum width of a column, not narrower than its heading
          floor = ->(i, min) { min.clamp(display_width(columns[i].first), natural[i]) }
          # First wrap only columns with text, if not enough wrap all columns
          text_only = natural.each_index.map { |i| text[i] ? floor.call(i, MIN_TEXT_WIDTH) : natural[i] }
          all = natural.each_index.map { |i| floor.call(i, text[i] ? MIN_TEXT_WIDTH : MIN_WIDTH) }
          minimum = text_only.sum <= available ? text_only : all
          # Columns wider than `limit` are narrowed to it, but not below their minimum (`limit` is `-1` if the table cannot fit)
          widths_for = ->(limit) { natural.zip(minimum).map { |nat, min| limit.clamp(min, nat) } }
          limit = (0..natural.max).bsearch { |l| widths_for.call(l).sum > available } - 1
          widths = widths_for.call(limit)
          wrapped = lines.map { |row| row.each_with_index.map { |cell, i| wrap(cell, widths[i]) } }
          [wrapped.first, wrapped.drop(1)]
        end

        # @return [String] Text with lines longer than width wrapped on spaces, and long words broken
        def wrap(text, width)
          text.split("\n").map do |line|
            next line if display_width(line) <= width
            wrapped = line.split.flat_map { |word| break_word(word, width) }.each_with_object([]) do |word, result|
              if !result.empty? && display_width(result.last) + 1 + display_width(word) <= width
                result[-1] = "#{result.last} #{word}"
              else
                result.push(word)
              end
            end
            restyle(wrapped).join("\n")
          end.join("\n")
        end

        # @return [Array<String>] Word split in pieces not wider than width, preferably after a punctuation
        def break_word(word, width)
          pieces = []
          while display_width(word) > width
            piece = +''
            word.scan(TOKEN) do |token|
              break if display_width(piece + token) > width && display_width(piece).positive?
              piece << token
            end
            cut = piece.rindex(BREAK_AFTER)
            piece = piece[0..cut] if cut && display_width(piece[0..cut]) > width / 2
            pieces.push(piece)
            word = word[piece.length..]
          end
          pieces.push(word)
        end

        # @return [Array<String>] Lines with ANSI styles closed at end of line, and open again on next line
        def restyle(lines)
          active = []
          lines.map do |line|
            result = active.join + line
            line.scan(STYLE) { |style| RESETS.include?(style) ? active.clear : active.push(style) }
            active.empty? ? result : "#{result}#{RESETS.first}"
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
