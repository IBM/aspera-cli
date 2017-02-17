# simple vt100 colors
class String
  def vtcmd(code); "\e[#{code}m";end

  def colstr(code); "#{vtcmd(code)}#{self}#{vtcmd(0)}" end

  def stystr(code); "#{vtcmd(code)}#{self}#{vtcmd(code+(code.eql?(1)?21:20))}" end

  def black;          colstr(30) end

  def red;            colstr(31) end

  def green;          colstr(32) end

  def brown;          colstr(33) end

  def blue;           colstr(34) end

  def magenta;        colstr(35) end

  def cyan;           colstr(36) end

  def gray;           colstr(37) end

  def bg_black;       colstr(40) end

  def bg_red;         colstr(41) end

  def bg_green;       colstr(42) end

  def bg_brown;       colstr(43) end

  def bg_blue;        colstr(44) end

  def bg_magenta;     colstr(45) end

  def bg_cyan;        colstr(46) end

  def bg_gray;        colstr(47) end

  def bold;           stystr(1) end

  def italic;         stystr(3) end

  def underline;      stystr(4) end

  def blink;          stystr(5) end

  def reverse_color;  stystr(7) end
end
