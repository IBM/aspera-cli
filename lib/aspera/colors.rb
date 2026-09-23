# frozen_string_literal: true

# cspell:words

# simple vt100 colors
class String
  # see https://en.wikipedia.org/wiki/ANSI_escape_code
  # symbol is the method name added to String, e.g. "hello".bold
  # it adds control chars to set color (and reset at the end).
  VT_STYLES = {
    bold:          1,
    dim:           2,
    italic:        3,
    underline:     4,
    blink:         5,
    reverse_color: 7,
    invisible:     8,
    strike:        9,
    black:         30,
    red:           31,
    green:         32,
    brown:         33,
    blue:          34,
    magenta:       35,
    cyan:          36,
    gray:          37,
    bg_black:      40,
    bg_red:        41,
    bg_green:      42,
    bg_brown:      43,
    bg_blue:       44,
    bg_magenta:    45,
    bg_cyan:       46,
    bg_gray:       47
  }.freeze
  private_constant :VT_STYLES
  class << self
    # Defines methods to String, one per entry in VT_STYLES
    def enable_colors(enabled = $stdout.tty?)
      VT_STYLES.each do |name, code|
        if enabled
          define_method(name) { "#{String.vt_cmd(code)}#{self}#{String.vt_cmd(String.vt_end_code(code))}" }
        else
          define_method(name) { self }
        end
      end
    end

    def vt_end_code(code)
      if code <= 2 then 22
      elsif code <= 8 then code + 20
      elsif code <= 37 then 39
      elsif code <= 47 then 49
      else
        0 # by default reset all
      end
    end

    def vt_cmd(code); "\e[#{code}m"; end
  end

  enable_colors

  # Applies the provided list of string decoration (colors).
  # @param colors [Array<Symbol>] List of decorations.
  # @return [String] Enhanced String.
  def apply(*colors)
    colors.reduce(self) { |s, c| s.public_send(c) }
  end

  # Transform capitalized to snake case
  def capital_to_snake
    return gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .downcase
  end

  # Transform snake case to capitalized
  def snake_to_capital
    split('_').map(&:capitalize).join
  end
end
