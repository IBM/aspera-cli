# frozen_string_literal: true

# cspell:words

# simple vt100 colors
class String
  class << self
    private

    def vt_cmd(code); "\e[#{code}m"; end
  end
  # see https://en.wikipedia.org/wiki/ANSI_escape_code
  # symbol is the method name added to String
  # it adds control chars to set color (and reset at the end).
  VT_STYLES = {
    bold:          1,
    dim:           2,
    italic:        3,
    underline:     4,
    blink:         5,
    reverse_color: 7,
    invisible:     8,
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
  # defines methods to String, one per entry in VT_STYLES
  VT_STYLES.each do |name, code|
    if $stdout.tty?
      begin_seq = vt_cmd(code)
      end_code = 0 # by default reset all
      if code <= 7 then code + 20
      elsif code <= 37 then 39
      elsif code <= 47 then 49
      end
      end_seq = vt_cmd(end_code)
      define_method(name){"#{begin_seq}#{self}#{end_seq}"}
    else
      define_method(name){self}
    end
  end
  def capital_to_snake
    return gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .downcase
  end
end
