# simple vt100 colors
class String
  private
  def self.vtcmd(code); "\e[#{code}m";end

  # see https://en.wikipedia.org/wiki/ANSI_escape_code
  VTSTYLES = {
    :bold=>1,
    :italic=>3,
    :underline=>4,
    :blink=>5,
    :reverse_color=>7,
    :black=>30,
    :red=>31,
    :green=>32,
    :brown=>33,
    :blue=>34,
    :magenta=>35,
    :cyan=>36,
    :gray=>37,
    :bg_black=>40,
    :bg_red=>41,
    :bg_green=>42,
    :bg_brown=>43,
    :bg_blue=>44,
    :bg_magenta=>45,
    :bg_cyan=>46,
    :bg_gray=>47,
  }
  public
  # defines methods to String, one per entry in VTSTYLES
  VTSTYLES.each do |name,code|
    # the end code depends on value
    endcode = (code >= 10) ? 0 : code+20+(code.eql?(1)?1:0)
    eval %q|def #{name}; "#{vtcmd(code)}\#{self}#{vtcmd(endcode)}"; end|
  end

end
