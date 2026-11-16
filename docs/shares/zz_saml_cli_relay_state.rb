# frozen_string_literal: true

# ADDITIVE PATCH for Aspera Shares (Rails 8.1): no existing file is modified.
# This is a specific patch, not a standard function of Shares.
# The final implementation in Shares may differ (RelayState values, format and validity of the code, returned fields):
# ascli (--auth=web) works only with this patch and will be adapted to the final implementation.
# Install as <shares_rails_root>/config/initializers/zz_saml_cli_relay_state.rb and restart.
# Uninstall: delete the file and restart.
#
# Two ways for a command line client (ascli --auth=web) to get a token after a SAML login. The RelayState selects the way.
#
# 1. Loopback (ascli --ui.web_auth=port, default): automatic when the browser runs on the same system as ascli
#        GET /auth/saml?RelayState=http://127.0.0.1:<port>/callback   (opened in the user's browser)
#        -> IdP -> POST /auth/saml/callback -> Shares redirects the browser to
#        http://127.0.0.1:<port>/callback?access_token=..&refresh_token=..&expires_in=86400&token_type=bearer
#
# 2. Code (ascli --ui.web_auth=paste): the browser can be on any system
#        GET /auth/saml?RelayState=aspera://device-code?state=<state>
#        -> IdP -> POST /auth/saml/callback -> Shares answers with a page that shows a code (Base64 URL-safe),
#        that the user pastes in the terminal of ascli. The code holds refresh_token and state.
#        The code is encrypted (AES-256-GCM) with a key derived from the state and from the current time in slots of
#        15 minutes (CODE_PERIOD): ascli also accepts the previous and the next slot, so the code is valid for 15 to 30 minutes.
#        The clocks of Shares and of the system that runs ascli must be correct (less than 15 minutes apart), otherwise
#        ascli rejects the code (expired, or wrong clock).
#
# The token is a regular Oauth2Token (same as POST /auth/oauth2/token): it works as "Authorization: Bearer"
# on /api/v1 and /node_api and can be renewed with grant_type=refresh_token.
# Any other RelayState, including other "aspera://..." values (login_token), keeps its existing behavior.
module SamlCliRelayState
  # http only, explicit port mandatory (URI#port would default to 80), no userinfo, no fragment
  LOOPBACK_RE = %r{\Ahttp://(?:127\.0\.0\.1|\[::1\]|localhost):\d{1,5}(?:/[^\s#]*)?\z}
  # same scheme as the existing aspera:// RelayState, but this exact form is handled here (other aspera:// URLs are not)
  CODE_RE = %r{\Aaspera://device-code\?state=([A-Za-z0-9-]{8,64})\z}
  # Code format: Base64 URL-safe, without padding, of IV (12) + GCM tag (16) + AES-256-GCM(deflate(JSON)),
  # as Aspera::SealedHash of ascli (base key "ascli").
  # Key: SHA256("ascli" + state + slot), slot = Unix time / CODE_PERIOD (rounded down). The state is known only by ascli and the browser it opened:
  # the code is not readable without it. ascli also accepts the previous and the next slot: the code is valid from 15 to 30 minutes.
  CODE_KEY_BASE = 'ascli'
  # Duration of a slot, in seconds: must be the same as Aspera::SealedHash::PERIOD of ascli
  CODE_PERIOD = 900

  private

  def aspera_relay_state?
    super || !cli_relay_state.nil?
  end

  # Same as SamlController#get_auth_token, except the token is an Oauth2Token sent to the loopback URL or shown as a code.
  def get_auth_token
    kind, value = cli_relay_state
    return super if kind.nil?

    auth_response = authenticate_with_params
    if auth_response.success?
      user = User.new(auth_response.user_resource)
      user.process_login
      token = Oauth2Token.create!(user: user.authorizable_user)
      response.set_header('Cache-Control', 'no-store')
      response.set_header('Referrer-Policy', 'no-referrer')
      kind.eql?(:code) ? render_device_code(token, value) : redirect_with_token(token, value)
    else
      login_failure(auth_response.user_message)
    end
  end

  def redirect_with_token(token, target)
    uri = URI.parse(target)
    query = URI.decode_www_form(uri.query.to_s).reject do |k, _|
      %w[access_token refresh_token expires_in token_type].include?(k)
    end
    query.concat([%w[token_type bearer], ['access_token', token.access_token],
                  ['refresh_token', token.refresh_token], ['expires_in', Oauth2Token::EXPIRATION_WINDOW.to_i.to_s]])
    uri.query = URI.encode_www_form(query)
    redirect_to uri.to_s, allow_other_host: true
  end

  # @return [String] Code for ascli
  def device_code(data, state)
    cipher = OpenSSL::Cipher.new('aes-256-gcm').encrypt
    cipher.key = OpenSSL::Digest.digest('SHA256', "#{CODE_KEY_BASE}#{state}#{Time.now.to_i / CODE_PERIOD}")
    iv = cipher.random_iv
    body = cipher.update(Zlib::Deflate.deflate(JSON.generate(data), Zlib::BEST_COMPRESSION)) + cipher.final
    [iv + cipher.auth_tag(16) + body].pack('m0').tr('+/', '-_').delete('=')
  end

  def render_device_code(token, state)
    code = device_code({ 'refresh_token' => token.refresh_token, 'state' => state }, state)
    response.set_header('Content-Security-Policy', "frame-ancestors 'none'")
    # The code is in the script only, not in the page: it is inserted in the page when the user clicks on the eye.
    js_code = JSON.generate(code).gsub('<', '\u003c')
    # Same look as the login page of Shares: its layout (header, footer), h1, fieldset and buttons.
    render html: <<~HTML.html_safe, layout: true # rubocop:disable Rails/OutputSafety
      <h1>Login Complete</h1>
      <p>Copy this code, and paste it in the terminal where <b>ascli</b> waits for it. You can then close this window.</p>
      <fieldset style="border:1px solid #c0c0c0;padding:12px">
        <div id="cli_code" aria-live="polite" style="font-family:monospace;word-break:break-all;max-height:9em;overflow-y:auto;margin-bottom:10px;user-select:none">&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;</div>
        <button type="button" id="cli_reveal" aria-pressed="false" title="Show the code" aria-label="Show the code">
          <svg id="cli_eye" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
          <svg id="cli_eye_off" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:none"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
        </button>
        <button type="button" id="cli_copy">Copy code</button>
        <span id="cli_status" role="status" style="margin-left:8px"></span>
      </fieldset>
      <script>
        (function () {
          var code = #{js_code};
          var box = document.getElementById('cli_code');
          var mask = box.textContent;
          var reveal = document.getElementById('cli_reveal');
          var status = document.getElementById('cli_status');
          var shown = false;
          reveal.addEventListener('click', function () {
            shown = !shown;
            box.textContent = shown ? code : mask;
            box.style.userSelect = shown ? 'all' : 'none';
            document.getElementById('cli_eye').style.display = shown ? 'none' : '';
            document.getElementById('cli_eye_off').style.display = shown ? '' : 'none';
            reveal.setAttribute('aria-pressed', shown ? 'true' : 'false');
            var label = shown ? 'Hide the code' : 'Show the code';
            reveal.title = label;
            reveal.setAttribute('aria-label', label);
          });
          function legacyCopy() {
            var area = document.createElement('textarea');
            area.value = code;
            area.setAttribute('readonly', '');
            area.style.position = 'fixed';
            area.style.opacity = '0';
            document.body.appendChild(area);
            area.select();
            var ok = false;
            try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
            document.body.removeChild(area);
            return ok;
          }
          function done(ok) {
            status.style.color = ok ? 'green' : 'red';
            status.textContent = ok ? 'Copied. Paste it in the terminal.' : 'Copy failed: show the code, select it and copy it.';
          }
          document.getElementById('cli_copy').addEventListener('click', function () {
            if (navigator.clipboard && window.isSecureContext) {
              navigator.clipboard.writeText(code).then(function () { done(true); }, function () { done(legacyCopy()); });
            } else {
              done(legacyCopy());
            }
          });
          // Remove the query from the address bar and from the session history
          if (window.history && history.replaceState) history.replaceState(null, '', location.pathname);
        })();
      </script>
    HTML
  end

  # @return [Array(Symbol, String), nil] [:loopback, url] or [:code, state], or nil for any other RelayState.
  # Same source as the original aspera_relay_state?. Not for POST /auth/oauth2/token (subclass of SamlController).
  def cli_relay_state
    return unless instance_of?(::SamlController)

    relay_state = (params[:RelayState].presence || Rails.cache.read("saml_relay_state:#{saml_response.in_response_to}")).to_s
    return [:loopback, relay_state] if LOOPBACK_RE.match?(relay_state)

    (m = CODE_RE.match(relay_state)) ? [:code, m[1]] : nil
  end
end

Rails.application.config.to_prepare do
  SamlController.prepend(SamlCliRelayState) unless SamlController.ancestors.include?(SamlCliRelayState)
end
