# frozen_string_literal: true

# cspell:ignore pkce urlsafe

require 'aspera/log'
require 'erb'
require 'json'
require 'securerandom'

module Aspera
  module OAuth
    module Server
      # Minimal OAuth 2.0 authorization server supporting:
      #   - Dynamic Client Registration (RFC 7591)
      #   - Authorization Code + PKCE (S256) flow (RFC 7636)
      #   - Refresh Token rotation
      #   - RFC 8414 authorization server metadata discovery
      #
      # Designed to be embedded inside a WEBrick servlet.  The caller is
      # responsible for:
      #   1. Creating an instance (once, before the server starts).
      #   2. Routing the five OAuth paths to the handle_* methods.
      #   3. Calling authorized?(bearer_token) to gate every other request.
      #
      # All in-memory stores are protected by an internal Mutex.
      #
      # @example Minimal integration inside a WEBrick servlet
      #   @oauth = OAuth::Server::Pkce.new(base_url: 'http://localhost:3000')
      #   # inside do_GET / do_POST:
      #   case req.path
      #   when '/.well-known/oauth-authorization-server' then @oauth.handle_discovery(req, res)
      #   when '/oauth/register'   then @oauth.handle_register(req, res)
      #   when '/oauth/authorize'  then @oauth.handle_authorize(req, res)
      #   when '/oauth/token'      then @oauth.handle_token(req, res)
      #   else
      #     unless @oauth.authorized?(req['Authorization'])
      #       # respond 401 …
      #     end
      #   end
      class Pkce
        include ERB::Util
        ACCESS_TOKEN_TTL  = 3600        # 1 hour
        REFRESH_TOKEN_TTL = 2_592_000   # 30 days
        CODE_TTL          = 120         # 2 minutes
        # Path to the ERB consent page template (relative to this file).
        HTML_TEMPLATE_PATH = File.join(__dir__, 'authorize.html.erb')

        private_constant :ACCESS_TOKEN_TTL, :REFRESH_TOKEN_TTL, :CODE_TTL, :HTML_TEMPLATE_PATH

      # @param base_url          [String]  Full base URL, e.g. "http://localhost:3000"
      # @param access_token_ttl  [Integer] Lifetime (seconds) of issued access tokens
      # @param refresh_token_ttl [Integer] Lifetime (seconds) of issued refresh tokens
      # @param title             [String]  Page <title> and branding (default: "Authorization request")
      # @param description       [String]  Description shown in the consent text (default: "this server")
      # @param authorize_html_cb [#call]   Optional callable(params, base_url) → HTML String
      #                                    for the consent page.  If nil the built-in HTML template is used.
      def initialize(base_url:, access_token_ttl: ACCESS_TOKEN_TTL, refresh_token_ttl: REFRESH_TOKEN_TTL,
                     title: 'Authorization request', description: 'this server',
                     authorize_html_cb: nil)
        require 'openssl'
        @base_url          = base_url
        @access_token_ttl  = access_token_ttl
        @refresh_token_ttl = refresh_token_ttl
        @title             = title
        @description       = description
        @authorize_html_cb = authorize_html_cb
        @store_mutex       = Mutex.new
        # dynamically registered clients:  Array<{client_id:}>
        @clients           = []
        # pending authorization codes: code => {client_id:, redirect_uri:, code_challenge:, expires_at:}
        @pending_codes     = {}
        # valid access tokens: token => expires_at (Time)
        @access_tokens     = {}
        # refresh tokens: token => {access_token:, expires_at:}
        @refresh_tokens    = {}
      end

      # -------------------------------------------------------------------------
      # Authorization check
      # -------------------------------------------------------------------------

      # Returns true when the Authorization header carries a valid Bearer token.
      # @param authorization_header [String, nil] value of the "Authorization" HTTP header
      # @return [Boolean]
      def authorized?(authorization_header)
        scheme, value = authorization_header.to_s.split(' ', 2)
        return false unless scheme.to_s.casecmp?('Bearer')
        result = @store_mutex.synchronize do
          expire_at = @access_tokens[value]
          expire_at && expire_at > Time.now
        end
        result == true
      end

      # -------------------------------------------------------------------------
      # RFC 8414 — authorization server metadata
      # -------------------------------------------------------------------------

      # Metadata hash (RFC 8414).
      # @return [Hash]
      def metadata
        {
          issuer:                                @base_url,
          authorization_endpoint:                "#{@base_url}/oauth/authorize",
          token_endpoint:                        "#{@base_url}/oauth/token",
          registration_endpoint:                 "#{@base_url}/oauth/register",
          response_types_supported:              ['code'],
          grant_types_supported:                 %w[authorization_code refresh_token],
          code_challenge_methods_supported:      ['S256'],
          token_endpoint_auth_methods_supported: ['none']
        }
      end

      # GET /.well-known/oauth-authorization-server
      def handle_discovery(_req, res)
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate(metadata)
      end

      # -------------------------------------------------------------------------
      # Dynamic Client Registration — RFC 7591
      # -------------------------------------------------------------------------

      # POST /oauth/register
      def handle_register(req, res)
        body = req.body.to_s.empty? ? {} : (JSON.parse(req.body.to_s) rescue {})
        client_id = SecureRandom.urlsafe_base64(16)
        @store_mutex.synchronize { @clients << {client_id: client_id} }
        Log.log.info { "OAuth dynamic registration: client_id=#{client_id} name=#{body['client_name']}" }
        res.status = 201
        res['Content-Type'] = 'application/json'
        res['Cache-Control'] = 'no-store'
        res.body = JSON.generate({
          client_id:                  client_id,
          client_id_issued_at:        Time.now.to_i,
          grant_types:                %w[authorization_code refresh_token],
          response_types:             ['code'],
          token_endpoint_auth_method: 'none',
          redirect_uris:              body['redirect_uris'] || []
        })
      end

      # -------------------------------------------------------------------------
      # Authorization endpoint — RFC 6749 §4.1
      # -------------------------------------------------------------------------

      # GET or POST /oauth/authorize — dispatch based on request method.
      def handle_authorize(req, res)
        if req.request_method == 'GET'
          handle_authorize_get(req, res)
        elsif req.request_method == 'POST'
          handle_authorize_post(req, res)
        else
          json_error(res, 405, 'method_not_allowed')
        end
      end

      # -------------------------------------------------------------------------
      # Token endpoint — RFC 6749 §4.1 / §6
      # -------------------------------------------------------------------------

      # POST /oauth/token
      def handle_token(req, res)
        require 'webrick'
        params     = WEBrick::HTTPUtils.parse_query(req.body.to_s)
        grant_type = params['grant_type']
        case grant_type
        when 'authorization_code'
          code          = params['code']
          code_verifier = params['code_verifier']
          stored = @store_mutex.synchronize { @pending_codes.delete(code) }
          if stored.nil? || stored[:expires_at] < Time.now
            json_error(res, 400, 'invalid_grant', 'Authorization code expired or unknown')
            return
          end
          unless pkce_valid?(code_verifier.to_s, stored[:code_challenge])
            json_error(res, 400, 'invalid_grant', 'PKCE verification failed')
            return
          end
          token_response(res)
        when 'refresh_token'
          rt_value = params['refresh_token']
          stored = @store_mutex.synchronize do
            entry = @refresh_tokens[rt_value]
            if entry && entry[:expires_at] > Time.now
              # Rotate: revoke old access token and issue fresh pair
              @access_tokens.delete(entry[:access_token])
              @refresh_tokens.delete(rt_value)
            end
            entry
          end
          if stored.nil?
            json_error(res, 400, 'invalid_grant', 'Refresh token expired or unknown')
            return
          end
          token_response(res)
        else
          json_error(res, 400, 'unsupported_grant_type', "Unsupported grant_type: #{grant_type}")
        end
      end

      # -------------------------------------------------------------------------
      # WWW-Authenticate header value for 401 responses
      # -------------------------------------------------------------------------

      # @return [String] value for the WWW-Authenticate header
      def www_authenticate_header
        "Bearer realm=\"#{@base_url}\", " \
          "resource_metadata=\"#{@base_url}/.well-known/oauth-authorization-server\""
      end

      private

      # -------------------------------------------------------------------------
      # Internal helpers
      # -------------------------------------------------------------------------

      def client_registered?(client_id)
        @clients.any? { |c| c[:client_id] == client_id }
      end

      def json_error(res, status, error, description = nil)
        res.status = status
        res['Content-Type'] = 'application/json'
        body = {error: error}
        body[:error_description] = description if description
        res.body = JSON.generate(body)
      end

      def purge_expired
        now = Time.now
        @pending_codes.delete_if  { |_, v| v[:expires_at] < now }
        @access_tokens.delete_if  { |_, exp| exp < now }
        @refresh_tokens.delete_if { |_, v| v[:expires_at] < now }
      end

      def issue_tokens
        access  = SecureRandom.urlsafe_base64(32)
        refresh = SecureRandom.urlsafe_base64(48)
        now = Time.now
        @store_mutex.synchronize do
          purge_expired
          @access_tokens[access]   = now + @access_token_ttl
          @refresh_tokens[refresh] = {access_token: access, expires_at: now + @refresh_token_ttl}
        end
        {
          access_token:  access,
          token_type:    'Bearer',
          expires_in:    @access_token_ttl,
          refresh_token: refresh
        }
      end

      def token_response(res)
        res.status = 200
        res['Content-Type'] = 'application/json'
        res['Cache-Control'] = 'no-store'
        res.body = JSON.generate(issue_tokens)
      end

      # Verify PKCE: SHA-256(code_verifier) == code_challenge (base64url, no padding).
      def pkce_valid?(verifier, challenge)
        require 'base64'
        digest   = OpenSSL::Digest::SHA256.digest(verifier)
        computed = Base64.urlsafe_encode64(digest, padding: false)
        OpenSSL.secure_compare(computed, challenge)
      end

      def handle_authorize_get(req, res)
        require 'webrick'
        params    = req.query
        client_id = params['client_id']
        unless client_registered?(client_id)
          json_error(res, 400, 'unauthorized_client', "Unknown client_id: #{client_id}")
          return
        end
        unless params['code_challenge'] && params['code_challenge_method'] == 'S256'
          json_error(res, 400, 'invalid_request', 'PKCE with S256 is required')
          return
        end
        res.status = 200
        res['Content-Type'] = 'text/html; charset=utf-8'
        res.body = if @authorize_html_cb
          @authorize_html_cb.call(params, @base_url)
        else
          authorize_html_from_template(params)
        end
      end

      def handle_authorize_post(req, res)
        require 'webrick'
        params       = WEBrick::HTTPUtils.parse_query(req.body.to_s)
        client_id    = params['client_id']
        redirect_uri = params['redirect_uri']
        state        = params['state']
        decision     = params['decision']
        if decision != 'allow'
          target = "#{redirect_uri}?error=access_denied"
          target += "&state=#{WEBrick::HTTPUtils.escape(state)}" unless state.to_s.empty?
          res.status = 302
          res['Location'] = target
          return
        end
        unless client_registered?(client_id)
          json_error(res, 400, 'unauthorized_client', "Unknown client_id: #{client_id}")
          return
        end
        code = SecureRandom.urlsafe_base64(24)
        @store_mutex.synchronize do
          purge_expired
          @pending_codes[code] = {
            client_id:      client_id,
            redirect_uri:   redirect_uri,
            code_challenge: params['code_challenge'],
            expires_at:     Time.now + CODE_TTL
          }
        end
        target = "#{redirect_uri}?code=#{WEBrick::HTTPUtils.escape(code)}"
        target += "&state=#{WEBrick::HTTPUtils.escape(state)}" unless state.to_s.empty?
        res.status = 302
        res['Location'] = target
      end

      # Render the consent page from the ERB template.
      # ERB::Util is included in the class, so h() is available in the binding.
      def authorize_html_from_template(params)
        title                 = @title
        description           = @description
        action_url            = "#{@base_url}/oauth/authorize"
        client_id             = params['client_id'].to_s
        redirect_uri          = params['redirect_uri'].to_s
        state                 = params['state'].to_s
        code_challenge        = params['code_challenge'].to_s
        code_challenge_method = params['code_challenge_method'].to_s
        ERB.new(File.read(HTML_TEMPLATE_PATH)).result(binding)
      end
    end
  end
end
end
