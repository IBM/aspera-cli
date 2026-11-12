# frozen_string_literal: true

require 'aspera/web_auth/server'
require 'aspera/web_auth/paste'
require 'aspera/environment'
require 'aspera/log'

module Aspera
  module WebAuth
    class << self
      # Create the object that receives the result of a web login, according to `Environment#web_auth` (option `ui.web_auth`):
      # `:port` listens on the loopback address of `redirect_uri`, `:paste` asks the user to give the result in the terminal.
      # Both provide `received_request`.
      # @param redirect_uri    [String]        Loopback URL that receives the result
      # @param additional_info [String]        Information in web page (only with `:port`)
      # @param login_url       [String, URI]   URL of the login page: with `:paste`, a code for `ascli` on the workstation is given to the user,
      #                                        unless the browser is started by `ascli` (the user has no time to use the code, and the browser is local)
      # @param reply_keys      [Array<String>] Keys of the query that the client needs (with `login_url`)
      # @return [Server, Paste]
      def receiver(redirect_uri, additional_info = nil, login_url: nil, reply_keys: nil)
        env = Environment.instance
        case env.web_auth
        when :paste
          login_url = nil if env.browser_command || env.url_method.eql?(:graphical)
          Paste.new(redirect_uri, login_url: login_url, reply_keys: reply_keys)
        when :port
          if env.url_method.eql?(:text) && env.browser_command.nil? && (ENV.key?('SSH_CONNECTION') || ENV.key?('SSH_TTY'))
            Log.log.warn do
              "Web login: the browser must reach port #{URI.parse(redirect_uri).port} of this host (SSH tunnel). " \
                'If not possible, use option --ui.web_auth=paste'
            end
          end
          Server.new(redirect_uri, additional_info)
        else Aspera.error_unexpected_value(env.web_auth) { 'ui.web_auth' }
        end
      end

      # Let the user open the login page, unless the receiver already gives the URL in its own message
      # @param login_receiver [Server, Paste] Result of `receiver`
      # @param login_url      [String, URI]   URL of the login page
      def open_login_page(login_receiver, login_url)
        return if login_receiver.is_a?(Paste) && login_receiver.shows_login_url?
        Environment.instance.open_uri(login_url)
      end
    end
  end
end
