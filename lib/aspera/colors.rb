# frozen_string_literal: true

# simple vt100 colors
class String
  class << self
    private

    def vtcmd(code);"\e[#{code}m";end
  end
  # see https://en.wikipedia.org/wiki/ANSI_escape_code
  # symbol is the method name added to String
  # it adds control chars to set color (and reset at the end).
  VTSTYLES = {
    bold:          1,
    italic:        3,
    underline:     4,
    blink:         5,
    reverse_color: 7,
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
  private_constant :VTSTYLES
  # defines methods to String, one per entry in VTSTYLES
  VTSTYLES.each do |name,code|
    if $stderr.tty?
      begin_seq = vtcmd(code)
      end_code =
      if code >= 10 then 0
      elsif code.eql?(1) then 22
      else 20 + code # rubocop:disable Lint/ElseLayout
      end
      end_seq = vtcmd(end_code)
      define_method(name){"#{begin_seq}#{self}#{end_seq}"}
    else
      define_method(name){self}
    end
  end
end
