require 'asperalm/log'

module Asperalm
  # Allows a user to open a Url
  # if method is "tty", then URL is displayed on terminal
  # if method is "os", then the URL will be opened with the default browser.
  class BrowserInteraction
    def self.open_url_methods; [ :tty, :os ]; end
    @@open_url_method=:tty

    def self.open_url_method=(value)
      @@open_url_method=value
    end

    def self.open_url_method()
      @@open_url_method
    end

    # command must be non blocking
    def self.open_system_uri(uri)
      case RbConfig::CONFIG['host_os']
      when /darwin|mac os/
        system("open '#{uri.to_s}'")
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        system('start explorer "'+uri.to_s+'"')
      else  # unix family
        system("xdg-open '#{uri.to_s}'")
      end
    end

    # this is non blocking
    def self.open_uri(the_url)
      case @@open_url_method
      when :os
        open_system_uri(the_url)
      when :tty
        puts "USER ACTION: please enter this url in a browser:\n"+the_url.to_s.red()+"\n"
      else
        raise StandardError,"unsupported url open method: #{@@open_url_method}"
      end
    end
  end # BrowserInteraction
end # Asperalm
