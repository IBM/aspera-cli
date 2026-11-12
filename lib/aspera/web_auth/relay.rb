# frozen_string_literal: true

require 'uri'
require 'aspera/web_auth/server'
require 'aspera/web_server_simple'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module WebAuth
    # Login on the workstation that has the browser, for `ascli` that runs on another host (option `ui.web_auth=paste`).
    # The remote `ascli` gives a code (`Blob`, type login) with the URL of the login page, the loopback URL to which the browser is redirected,
    # and the keys of the reply. Here, a local server receives the redirection, and the page shown in the browser gives a code (type reply)
    # to paste in the terminal of the remote `ascli`.
    module Relay
      # @!attribute [r] login_url
      #   @return [URI] URL of the login page (https)
      # @!attribute [r] redirect_uri
      #   @return [String] Loopback URL to which the browser is redirected
      # @!attribute [r] reply_keys
      #   @return [Array<String>] Keys of the query that are given to the remote `ascli`
      # @!attribute [r] host
      #   @return [String] Host of the login page, calculated here (not given by the remote `ascli`)
      Login = Struct.new(:login_url, :redirect_uri, :reply_keys, :host, keyword_init: true)
      # Keys of the reply are names of query parameters
      REPLY_KEY_REGEX = /\A[a-z][a-z0-9_]{0,63}\z/
      MAX_REPLY_KEYS = 16
      private_constant :REPLY_KEY_REGEX, :MAX_REPLY_KEYS

      class << self
        # The code comes from another host, or from a message: its content is checked.
        # @param data [Hash] Content of a code of type login: `login_url`, `redirect_uri`, `reply_keys`
        # @return [Login]
        # @raise [ParameterError] if content is not acceptable
        def parse(data)
          Aspera.assert_type(data, Hash, type: ParameterError) { 'login code' }
          login_url = parse_uri(data['login_url'], 'login_url')
          raise ParameterError, "URL of the login page shall be https: #{login_url.scheme}://#{login_url.host}" unless login_url.scheme.eql?('https')
          raise ParameterError, 'URL of the login page has no host' if login_url.host.to_s.empty?
          redirect = parse_uri(data['redirect_uri'], 'redirect_uri')
          raise ParameterError, "redirect_uri shall be http or https, with a port: #{redirect}" unless %w[http https].include?(redirect.scheme) && redirect.port
          raise ParameterError, "redirect_uri host shall be loopback (localhost, 127.0.0.0/8, ::1): #{redirect.host}" unless WebServerSimple.loopback?(redirect.hostname.to_s)
          keys = data['reply_keys']
          valid_keys = keys.is_a?(Array) && !keys.empty? && keys.length <= MAX_REPLY_KEYS && keys.all? { |key| key.is_a?(String) && key.match?(REPLY_KEY_REGEX) }
          raise ParameterError, 'reply_keys shall be a list of parameter names' unless valid_keys
          Login.new(login_url: login_url, redirect_uri: redirect.to_s, reply_keys: keys, host: login_url.host.downcase)
        end

        # Open the login page, receive the redirection, and show the code to the user in the browser.
        # @param login [Login] Result of `parse`
        # @return [nil]
        def run(login)
          server = Server.new(login.redirect_uri, "#{login.host} - login for ascli on another host", reply_keys: login.reply_keys)
          Environment.instance.open_uri(login.login_url)
          server.received_request
          # the page that gives the code is sent after the request is received: wait for it before ending
          server.wait_stopped
          nil
        end

        private

        # @return [URI]
        def parse_uri(value, name)
          raise ParameterError, "#{name} is missing" unless value.is_a?(String) && !value.empty?
          URI.parse(value)
        rescue URI::InvalidURIError => e
          raise ParameterError, "#{name} is not a valid URL: #{e.message}"
        end
      end
    end
  end
end
