# frozen_string_literal: true

require 'aspera/oauth/client/web'
require 'aspera/web_auth/blob'
require 'aspera/cli/prompt'
require 'securerandom'

module Aspera
  module OAuth
    # Authentication of a SAML user of Aspera Shares using a Web browser.
    #
    # Shares has no OAuth authorization endpoint: the OAuth tokens of the user (same as those of `<url>/auth/oauth2/token`) are given by the SAML login page
    # (`<url>/auth/saml`), once the user is authenticated. The way depends on option `ui.web_auth`:
    # - `port` (default): `RelayState` is the loopback URL, Shares redirects the browser to it with the tokens in the query. It is automatic.
    # - `paste`: `RelayState` is `aspera://device-code?state=<state>`, Shares shows a code that the user pastes in the terminal.
    #   No local port is used, the browser can be on any system.
    # The refresh token received (in the URL, or in the code) is immediately exchanged for a new token: the tokens that went through the browser are not valid any more.
    class SharesWeb < Web
      # `RelayState` that tells Shares to show the code (`paste`)
      DEVICE_CODE_RELAY_STATE = 'aspera://device-code?state='

      # @param redirect_uri   [String] Loopback URL that receives the tokens (`port`)
      # @param path_authorize [String] Path to the SAML login page, from the base URL
      # @param base_params    [Hash]   Parameters for base class: `base_url` is `<url>/auth`, `path_token` is `oauth2/token`
      def initialize(redirect_uri:, path_authorize: 'saml', **base_params)
        # Shares needs a path in the loopback URL, and the local server expects it
        uri = URI.parse(redirect_uri)
        uri.path = '/' if uri.path.empty?
        super(redirect_uri: uri.to_s, path_authorize: path_authorize, path_token: 'oauth2/token', **base_params)
      end

      def create_token
        # state is returned unchanged by Shares: it ties the answer to this login
        random_state = SecureRandom.uuid
        received_params =
          case Environment.instance.web_auth
          when :paste then receive_code(random_state)
          when :port then receive_on_loopback(random_state)
          else Aspera.error_unexpected_value(Environment.instance.web_auth) { 'ui.web_auth' }
          end
        Aspera.assert(random_state.eql?(received_params['state'])) { 'wrong received state' }
        refresh_token = received_params['refresh_token'].to_s
        Aspera.assert(!refresh_token.empty?) { 'No token received: does this Shares have the login patch for ascli?' }
        Secret::Hider.instance.add_secret_values(refresh_token, received_params['access_token'].to_s)
        create_token_base(grant_type: 'refresh_token', refresh_token: refresh_token)
      end

      private

      # `port`: the browser is redirected to the loopback URL, which has the state in its query
      # @return [Hash{String=>String}] Query received
      def receive_on_loopback(state)
        login_page_url = login_page(Rest.build_uri(@redirect_uri, state: state).to_s)
        # the page shows where the user is logged in
        login_receiver = WebAuth.receiver(@redirect_uri, [Web.additional_info, URI.parse(api.base_url).host].compact.join(' - '))
        Environment.instance.open_uri(login_page_url)
        login_receiver.received_request
      end

      # `paste`: Shares shows a code, to paste in the terminal
      # @return [Hash{String=>String}] Content of the code
      def receive_code(state)
        Environment.instance.open_uri(login_page("#{DEVICE_CODE_RELAY_STATE}#{state}"))
        Log.log.warn { 'USER ACTION: Log in with the web browser, then copy the code displayed by Shares and paste it in the prompt below.' }
        input = Cli::Prompt.prompt_user_input('Code', sensitive: true)
        Aspera.assert(WebAuth::Blob.code?(input), type: ParameterError) { 'Not a code: copy the code displayed by Shares after login' }
        type, data = WebAuth::Blob.decode(input)
        Aspera.assert_values(type, [:reply], type: ParameterError) { 'type of code' }
        data
      end

      # @param relay_state [String] Where Shares sends the result
      # @return [String] URL of the SAML login page
      def login_page(relay_state)
        url = Rest.build_uri("#{api.base_url}/#{@path_authorize}", RelayState: relay_state)
        Log.log.debug { "login_page_url=#{url}" }
        url
      end
    end
    Factory.instance.register_token_creator(SharesWeb)
  end
end
