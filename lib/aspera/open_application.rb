# frozen_string_literal: true

require 'aspera/log'
require 'aspera/environment'
require 'rbconfig'
require 'singleton'

module Aspera
  # Allows a user to open a Url
  # if method is "text", then URL is displayed on terminal
  # if method is "graphical", then the URL will be opened with the default browser.
  class OpenApplication
    include Singleton
    USER_INTERFACES = %i[text graphical].freeze
    class << self
      def default_gui_mode
        # assume not remotely connected on macos and windows
        return :graphical if [Environment::OS_WINDOWS, Environment::OS_X].include?(Environment.os)
        # unix family
        return :graphical if ENV.key?('DISPLAY') && !ENV['DISPLAY'].empty?
        return :text
      end

      # command must be non blocking
      def uri_graphical(uri)
        case Environment.os
        when Environment::OS_X       then return system('open', uri.to_s)
        when Environment::OS_WINDOWS then return system('start', 'explorer', %Q{"#{uri}"})
        when Environment::OS_LINUX   then return system('xdg-open', uri.to_s)
        else
          raise "no graphical open method for #{Environment.os}"
        end
      end

      def editor(file_path)
        if ENV.key?('EDITOR')
          system(ENV['EDITOR'], file_path.to_s)
        elsif Environment.os.eql?(Environment::OS_WINDOWS)
          system('notepad.exe', %Q{"#{file_path}"})
        else
          uri_graphical(file_path.to_s)
        end
      end
    end

    attr_accessor :url_method

    def initialize
      @url_method = self.class.default_gui_mode
    end

    # this is non blocking
    def uri(the_url)
      case @url_method
      when :graphical
        self.class.uri_graphical(the_url)
      when :text
        case the_url.to_s
        when /^http/
          puts "USER ACTION: please enter this url in a browser:\n#{the_url.to_s.red}\n"
        else
          puts "USER ACTION: open this:\n#{the_url.to_s.red}\n"
        end
      else
        raise StandardError, "unsupported url open method: #{@url_method}"
      end
    end
  end
end
