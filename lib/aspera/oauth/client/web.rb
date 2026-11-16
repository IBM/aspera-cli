# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'base'
require_relative '../../environment'
require_relative '../../web_auth/receiver'
require_relative '../../assert'
require 'base64'
require 'digest'
require 'securerandom'
module Aspera
  module OAuth
    # Authentication using Web browser
    class Web < Base
      # PKCE code challenge method (RFC 7636 §4.2)
      PKCE_METHOD = 'S256'
      class << self
        attr_accessor :additional_info

        # @param verifier [String] PKCE code verifier
        # @return [String] PKCE S256 code challenge: BASE64URL(SHA256(verifier)), without padding (RFC 7636 §4.2)
        def pkce_challenge(verifier)
          Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
        end
      end
      # @param redirect_uri   [String]  url to receive the code after auth (to be exchanged for token)
      # @param path_authorize [String]  path to login page on web app
      # @param pkce           [Boolean] use PKCE (RFC 7636): the code can be exchanged only by this process
      def initialize(
        redirect_uri:,
        path_authorize: 'authorize',
        pkce: false,
        **base_params
      )
        super(**base_params)
        @redirect_uri = redirect_uri
        @path_authorize = path_authorize
        @pkce = pkce
        uri = URI.parse(@redirect_uri)
        Aspera.assert_values(uri.scheme, %w[http https]) { 'redirect_uri scheme must be http or https' }
        Aspera.assert(!uri.port.nil?, 'redirect_uri must have a port')
        Aspera.assert(WebServerSimple.loopback?(uri.hostname)) { "redirect_uri host must be loopback (localhost, 127.0.0.0/8, ::1): #{uri.host}" }
      end

      def create_token
        # generate secure state to check later
        random_state = SecureRandom.uuid
        authorize_params = {response_type: 'code', redirect_uri: @redirect_uri, state: random_state}
        token_params = {}
        if @pkce
          # 32 random bytes: 43 characters of base64url, within the 43..128 allowed (RFC 7636 §4.1)
          code_verifier = SecureRandom.urlsafe_base64(32)
          authorize_params[:code_challenge] = self.class.pkce_challenge(code_verifier)
          authorize_params[:code_challenge_method] = PKCE_METHOD
          token_params[:code_verifier] = code_verifier
        end
        login_page_url = Rest.build_uri(
          "#{api.base_url}/#{@path_authorize}",
          base_parameters(**authorize_params)
        )
        # here, we need a human to authorize on a web page
        Log.log.debug { "login_page_url=#{login_page_url}" }
        # receive the code: local web server, or redirect URL pasted by the user (see option ui.web_auth)
        login_receiver = WebAuth.receiver(@redirect_uri, self.class.additional_info, login_url: login_page_url, reply_keys: %w[code state])
        # start browser on login page
        WebAuth.open_login_page(login_receiver, login_page_url)
        # wait for code in request
        received_params = login_receiver.received_request
        Aspera.assert(random_state.eql?(received_params['state'])) { 'wrong received state' }
        # exchange code for token
        create_token_base(
          include_secret: true,
          grant_type:     'authorization_code',
          code:           received_params['code'],
          redirect_uri:   @redirect_uri,
          **token_params
        )
      end
    end
    Factory.instance.register_token_creator(Web)
  end
end
