require 'asperalm/log'

module Asperalm
# open a Url
  class BrowserInteraction
    def self.getter_types; [ :tty, :os ]; end
    @@login_type=:tty
    def self.browser_method=(value)
      @@login_type=value
    end
    def self.browser_method()
      @@login_type
    end

    # command must be non blocking
    def self.open_system_uri(uri)
      case RbConfig::CONFIG['host_os']
      when /darwin|mac os/
        system("open '#{uri.to_s}'")
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        system("start '#{uri.to_s}'")
      else  # unix family
        system("xdg-open '#{uri.to_s}'")
      end
    end

    # this is non blocking
    def self.open_uri(the_url)
      case @@login_type
      when :os
        open_system_uri(the_url)
      when :tty
        puts "USER ACTION: please enter this url in a browser:\n"+the_url.to_s.red()+"\n"
      else
        raise 'choose open method'
      end
    end
  end # BrowserInteraction
end # Asperalm
