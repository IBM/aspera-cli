require 'asperalm/log'
require 'rbconfig'
require 'singleton'

module Asperalm
  # Allows a user to open a Url
  # if method is "text", then URL is displayed on terminal
  # if method is "graphical", then the URL will be opened with the default browser.
  class OpenApplication
    include Singleton
    # User Interfaces
    def self.user_interfaces; [ :text, :graphical ]; end

    def self.default_gui_mode
      case current_os_type
      when :windows
        return :graphical
      else
        if ENV.has_key?("DISPLAY") and !ENV["DISPLAY"].empty?
          return :graphical
        end
        return :text
      end
    end

    def self.current_os_type
      case RbConfig::CONFIG['host_os']
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        return :windows
      when /darwin|mac os/
        return :mac
      else  # unix family
        return :unix
      end
    end

    # command must be non blocking
    def self.uri_graphical(uri)
      case current_os_type
      when :mac
        system("open '#{uri.to_s}'")
      when :windows
        system('start explorer "'+uri.to_s+'"')
      else  # unix family
        system("xdg-open '#{uri.to_s}'")
      end
    end

    attr_accessor :url_method

    def initialize
      @url_method=self.class.default_gui_mode
    end

    # this is non blocking
    def uri(the_url)
      case @url_method
      when :graphical
        self.class.uri_graphical(the_url)
      when :text
        case the_url.to_s
        when /^http/
          puts "USER ACTION: please enter this url in a browser:\n"+the_url.to_s.red()+"\n"
        else
          puts "USER ACTION: open this:\n"+the_url.to_s.red()+"\n"
        end
      else
        raise StandardError,"unsupported url open method: #{@url_method}"
      end
    end
  end # OpenApplication
end # Asperalm
