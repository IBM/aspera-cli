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
    class << self
      USER_INTERFACES = %i[text graphical].freeze
      # User Interfaces
      def user_interfaces; USER_INTERFACES; end

      def default_gui_mode
        return :graphical if [Aspera::Environment::OS_WINDOWS, Aspera::Environment::OS_X].include?(Aspera::Environment.os)
        # unix family
        return :graphical if ENV.key?('DISPLAY') && !ENV['DISPLAY'].empty?
        return :text
      end

      # command must be non blocking
      def uri_graphical(uri)
        case Aspera::Environment.os
        when Aspera::Environment::OS_X       then return system('open', uri.to_s)
        when Aspera::Environment::OS_WINDOWS then return system('start', 'explorer', %Q{"#{uri}"})
        when Aspera::Environment::OS_LINUX   then return system('xdg-open', uri.to_s)
        else
          raise "no graphical open method for #{Aspera::Environment.os}"
        end
      end

      def editor(file_path)
        if ENV.key?('EDITOR')
          system(ENV['EDITOR'], file_path.to_s)
        elsif Aspera::Environment.os.eql?(Aspera::Environment::OS_WINDOWS)
          system('notepad.exe', %Q{"#{file_path}"})
        else
          uri_graphical(file_path.to_s)
        end
      end
    end # self

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
  end # OpenApplication
end # Aspera
