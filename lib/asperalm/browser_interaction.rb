# Laurent/Aspera
# a code listener will listen on a tcp port, redirect the user to a login page
# and wait for the browser to send the request with code on local port

require 'asperalm/log'
require 'socket'
require 'pp'

module Asperalm
  class BrowserInteraction
    def self.getter_types; [ :tty, :os ]; end
    
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

    # uitype: :tty, or :os
    def initialize(redirect_uri,uitype)
      @redirect_uri=redirect_uri
      @login_type=uitype
      @browser=nil
      @creds=nil
      @code=nil
      @mutex = Mutex.new
      @is_logged_in=false
    end

    def redirect_uri
      return @redirect_uri
    end

    def terminate
      if !@browser.nil? then
        @browser.close
      end
    end

    def set_creds(username,password)
      @creds={:user=>username,:password=>password}
    end

    def start_listener
      Thread.new {
        @mutex.synchronize {
          port=URI.parse(redirect_uri).port
          Log.log.info "listening on port #{port}"
          TCPServer.open('127.0.0.1', port) { |webserver|
            Log.log.info "server=#{webserver}"
            websession = webserver.accept
            line = websession.gets.chomp
            Log.log.info "line=#{line}"
            if ! line.start_with?('GET /?') then
              raise "unexpected request"
            end
            request = line.partition('?').last.partition(' ').first
            data=URI.decode_www_form(request)
            Log.log.info "data=#{PP.pp(data,'').chomp}"
            code=data[0][1]
            Log.log.info "code=#{PP.pp(code,'').chomp}"
            websession.print "HTTP/1.1 200/OK\r\nContent-type:text/html\r\n\r\n<html><body><h1>received answer (code)</h1><code>#{code}</code></body></html>"
            websession.close
            @code=code
          }
        }
      }
    end

    def get_code
      @mutex.synchronize {
        return @code
      }
    end

    def goto_page_and_get_code(the_url)
      Log.log.info "the_url=#{the_url}".bg_red().gray()
      start_listener()
      case @login_type
      when :os
        self.class.open_system_uri(the_url)
      when :tty
        puts "USER ACTION: please enter this url in a browser:\n"+the_url.to_s.red()+"\n"
      else
        raise 'choose open method'
      end
      code=get_code()
      return code
    end

  end
end # Asperalm
