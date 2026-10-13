# frozen_string_literal: true

# cspell:ignore pkce urlsafe

require 'aspera/log'
require 'aspera/assert'
require 'aspera/web_page'
require 'aspera/servlet_helpers'
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
        include ServletHelpers

        ACCESS_TOKEN_TTL  = 3600        # 1 hour
        REFRESH_TOKEN_TTL = 2_592_000   # 30 days
        CODE_TTL          = 120         # 2 minutes
        # Path to the ERB consent page template (relative to this file).
        HTML_TEMPLATE_PATH = File.join(__dir__, 'authorize.html.erb')

        private_constant :ACCESS_TOKEN_TTL, :REFRESH_TOKEN_TTL, :CODE_TTL, :HTML_TEMPLATE_PATH

        # Default TTL values, exposed for callers that want to display or override them.
        class << self
          def default_access_token_ttl  = ACCESS_TOKEN_TTL
          def default_refresh_token_ttl = REFRESH_TOKEN_TTL
        end

        # @param base_url          [String]  Full base URL, e.g. "http://localhost:3000"
        # @param access_token_ttl  [Integer] Lifetime (seconds) of issued access tokens
        # @param refresh_token_ttl [Integer] Lifetime (seconds) of issued refresh tokens
        # @param title             [String]  Page <title> and branding (default: "Authorization request")
        # @param description       [String]  Description shown in the consent text (default: "this server"), trusted HTML (not escaped)
        # @param consent_secret    [String, nil] If set, the user must enter this secret on the consent page to allow access.
        #                                    Without it, anyone who can reach the server can approve its own request.
        # @param authorize_html_cb [#call]   Optional callable(params, base_url) → HTML String
        #                                    for the consent page.  If nil the built-in HTML template is used.
        #                                    With `consent_secret`, the form must post it in field `consent_secret`.
        def initialize(base_url:, access_token_ttl: ACCESS_TOKEN_TTL, refresh_token_ttl: REFRESH_TOKEN_TTL,
          title: 'Authorization request', description: 'this server',
          consent_secret: nil, authorize_html_cb: nil)
          require 'openssl'
          Aspera.assert(consent_secret.nil? || !consent_secret.to_s.empty?) { 'consent_secret must not be empty' }
          @base_url          = base_url
          @access_token_ttl  = access_token_ttl
          @refresh_token_ttl = refresh_token_ttl
          @title             = title
          @description       = description
          @consent_secret    = consent_secret&.to_s
          @authorize_html_cb = authorize_html_cb
          @store_mutex       = Mutex.new
          # dynamically registered clients:  Array<{client_id:, redirect_uris:}>
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
          json_response(res, 200, metadata)
        end

        # -------------------------------------------------------------------------
        # Dynamic Client Registration — RFC 7591
        # -------------------------------------------------------------------------

        # POST /oauth/register
        def handle_register(req, res)
          body = req.body.to_s.empty? ? {} : (JSON.parse(req.body.to_s) rescue {})
          redirect_uris = body['redirect_uris']
          unless redirect_uris.is_a?(Array) && !redirect_uris.empty? && redirect_uris.all?(String)
            json_error(res, 400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array of strings')
            return
          end
          client_id = SecureRandom.urlsafe_base64(16)
          @store_mutex.synchronize { @clients << {client_id: client_id, redirect_uris: redirect_uris} }
          Log.log.info { "OAuth dynamic registration: client_id=#{client_id} name=#{body['client_name']}" }
          registration = {
            client_id:                  client_id,
            client_id_issued_at:        Time.now.to_i,
            grant_types:                %w[authorization_code refresh_token],
            response_types:             ['code'],
            token_endpoint_auth_method: 'none',
            redirect_uris:              redirect_uris
          }
          json_response(res, 201, registration, headers: {'Cache-Control' => 'no-store'})
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
            # RFC 6749 §4.1.3: the code must have been issued to this client (client_id is optional with PKCE)
            unless params['client_id'].nil? || params['client_id'] == stored[:client_id]
              json_error(res, 400, 'invalid_grant', 'client_id mismatch')
              return
            end
            # RFC 6749 §4.1.3: redirect_uri must match the one used in the authorization request
            unless params['redirect_uri'] == stored[:redirect_uri]
              json_error(res, 400, 'invalid_grant', 'redirect_uri mismatch')
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
              # Single use: removed even if expired
              entry = @refresh_tokens.delete(rt_value)
              next nil if entry.nil? || entry[:expires_at] < Time.now
              # Rotate: revoke old access token and issue fresh pair
              @access_tokens.delete(entry[:access_token])
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

        # @return [Boolean] true if client is registered and redirect_uri is one of its registered URIs (exact match)
        def client_redirect_valid?(client_id, redirect_uri)
          @store_mutex.synchronize do
            @clients.any? { |c| c[:client_id] == client_id && c[:redirect_uris].include?(redirect_uri) }
          end
        end

        # Build redirect URL to client, preserving any query already present in redirect_uri.
        def client_redirect_url(redirect_uri, **params)
          query = params.reject { |_, v| v.to_s.empty? }.map { |k, v| "#{k}=#{WEBrick::HTTPUtils.escape_form(v.to_s)}" }.join('&')
          "#{redirect_uri}#{redirect_uri.include?('?') ? '&' : '?'}#{query}"
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
          json_response(res, 200, issue_tokens, headers: {'Cache-Control' => 'no-store'})
        end

        # Verify PKCE: SHA-256(code_verifier) == code_challenge (base64url, no padding).
        def pkce_valid?(verifier, challenge)
          return false unless challenge.is_a?(String) && !challenge.empty?
          require 'base64'
          digest   = OpenSSL::Digest::SHA256.digest(verifier)
          computed = Base64.urlsafe_encode64(digest, padding: false)
          OpenSSL.secure_compare(computed, challenge)
        end

        def handle_authorize_get(req, res)
          require 'webrick'
          params    = req.query
          client_id = params['client_id']
          unless client_redirect_valid?(client_id, params['redirect_uri'])
            json_error(res, 400, 'unauthorized_client', "Unknown client_id or unregistered redirect_uri: #{client_id}")
            return
          end
          unless pkce_requested?(params)
            json_error(res, 400, 'invalid_request', 'PKCE with S256 is required')
            return
          end
          consent_page(res, params)
        end

        # @return [Boolean] true if the request carries a S256 PKCE challenge
        def pkce_requested?(params)
          !params['code_challenge'].to_s.empty? && params['code_challenge_method'] == 'S256'
        end

        # Respond with the consent page
        # @param params [Hash]    Parameters of the authorization request
        # @param status [Integer] HTTP status
        # @param error  [String, nil] Error message displayed on the page
        def consent_page(res, params, status: 200, error: nil)
          res.status = status
          res['Content-Type'] = 'text/html; charset=utf-8'
          # Prevent clickjacking of the consent page
          res['X-Frame-Options'] = 'DENY'
          res['Content-Security-Policy'] = "frame-ancestors 'none'"
          res['Cache-Control'] = 'no-store'
          res.body = if @authorize_html_cb
            @authorize_html_cb.call(params, @base_url)
          else
            authorize_html_from_template(params, error: error)
          end
        end

        def handle_authorize_post(req, res)
          require 'webrick'
          params       = WEBrick::HTTPUtils.parse_query(req.body.to_s)
          client_id    = params['client_id']
          redirect_uri = params['redirect_uri']
          state        = params['state']
          decision     = params['decision']
          # Validate client and redirect_uri before any redirect (prevents open redirect)
          unless client_redirect_valid?(client_id, redirect_uri)
            json_error(res, 400, 'unauthorized_client', "Unknown client_id or unregistered redirect_uri: #{client_id}")
            return
          end
          if decision != 'allow'
            res.status = 302
            res['Location'] = client_redirect_url(redirect_uri, error: 'access_denied', state: state)
            return
          end
          unless pkce_requested?(params)
            res.status = 302
            res['Location'] = client_redirect_url(redirect_uri, error: 'invalid_request', error_description: 'PKCE with S256 is required', state: state)
            return
          end
          # The consent secret proves that the user approving the request is allowed to grant access
          if @consent_secret && !OpenSSL.secure_compare(params['consent_secret'].to_s, @consent_secret)
            Log.log.warn { "OAuth consent refused: wrong access code for client_id=#{client_id}" }
            consent_page(res, params, status: 401, error: 'Invalid access code')
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
          res.status = 302
          res['Location'] = client_redirect_url(redirect_uri, code: code, state: state)
        end

        # Render the consent page from the ERB template.
        # @param error [String, nil] Error message displayed on the page
        def authorize_html_from_template(params, error: nil)
          WebPage.render(
            HTML_TEMPLATE_PATH,
            title:                 @title,
            description:           @description,
            action_url:            "#{@base_url}/oauth/authorize",
            client_id:             params['client_id'].to_s,
            redirect_uri:          params['redirect_uri'].to_s,
            state:                 params['state'].to_s,
            code_challenge:        params['code_challenge'].to_s,
            code_challenge_method: params['code_challenge_method'].to_s,
            secret_required:       !@consent_secret.nil?,
            error:                 error
          )
        end
      end
    end
  end
end
