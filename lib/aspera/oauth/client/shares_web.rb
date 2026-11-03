# frozen_string_literal: true

require 'aspera/oauth/client/web'
require 'securerandom'

module Aspera
  module OAuth
    # Authentication of a SAML user of Aspera Shares using a Web browser.
    #
    # Shares has no OAuth authorization endpoint: the SAML login page (`<url>/auth/saml`) redirects, once the user is authenticated,
    # to the loopback URL given in `RelayState`, with the OAuth tokens of the user (same as those of `<url>/auth/oauth2/token`) in the query.
    # The refresh token received in the URL is immediately exchanged for a new token: the tokens that went through the browser are not valid any more.
    class SharesWeb < Web
      # @param redirect_uri   [String] Loopback URL that receives the tokens
      # @param path_authorize [String] Path to the SAML login page, from the base URL
      # @param base_params    [Hash]   Parameters for base class: `base_url` is `<url>/auth`, `path_token` is `oauth2/token`
      def initialize(redirect_uri:, path_authorize: 'saml', **base_params)
        # Shares needs a path in the loopback URL, and the local server expects it
        uri = URI.parse(redirect_uri)
        uri.path = '/' if uri.path.empty?
        super(redirect_uri: uri.to_s, path_authorize: path_authorize, path_token: 'oauth2/token', **base_params)
      end

      def create_token
        # state is returned unchanged in the query of RelayState: it ties the answer to this login
        random_state = SecureRandom.uuid
        login_page_url = Rest.build_uri(
          "#{api.base_url}/#{@path_authorize}",
          RelayState: Rest.build_uri(@redirect_uri, state: random_state).to_s
        )
        Log.log.debug { "login_page_url=#{login_page_url}" }
        web_server = WebAuth::Server.new(@redirect_uri, Web.additional_info)
        Environment.instance.open_uri(login_page_url)
        received_params = web_server.received_request
        Aspera.assert(random_state.eql?(received_params['state'])) { 'wrong received state' }
        refresh_token = received_params['refresh_token'].to_s
        Aspera.assert(!refresh_token.empty?) { 'No token received: does this Shares support redirection to a loopback URL?' }
        Secret::Hider.instance.add_secret_values(refresh_token, received_params['access_token'].to_s)
        create_token_base(grant_type: 'refresh_token', refresh_token: refresh_token)
      end
    end
    Factory.instance.register_token_creator(SharesWeb)
  end
end
