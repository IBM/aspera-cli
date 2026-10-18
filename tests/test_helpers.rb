# frozen_string_literal: true

# Helper methods for tests.yml post/pre blocks.
# Loaded from rakelib/test.rake via require_relative.
# Methods receive `t` (TestEnv::Context) when needed; constants (TMP, etc.) are global.

require 'openssl'
require 'shellwords'
require 'base64'
require 'securerandom'
require 'aspera/rest'
require 'aspera/mime'
require 'aspera/json_rpc/client'
require 'aspera/keychain/macos_security'

MCP_REDIRECT_URI = 'http://127.0.0.1:19999/cb'
MCP_INIT_PARAMS  = {protocolVersion: '2024-11-05', capabilities: {}, clientInfo: {name: 'test', version: '0'}}.freeze
# Static token of the MCP server, also the access code of the OAuth consent page and of secret pages
MCP_AUTH_TOKEN   = 'test-secret'
# Protocol version of stateless requests: version and client capabilities in `_meta` of each request
MCP_MODERN_VERSION = '2026-07-28'

TEST_KEYCHAIN_NAME = 'ascli'
TEST_KEYCHAIN_PASS = 'ascli_test_pass'

# Value of env var `ASCLI_UI`: sub-option `command` of option `ui` is the auto browser (`tests/auto_browser.rb`).
# @param args [Array<String>] Additional arguments of the browser command
# @return [String, nil] Value, or nil in manual mode (system browser)
def browser_ui_option(*args)
  return if BROWSER_COMMAND.nil?
  "@json:#{JSON.generate({command: BROWSER_COMMAND + args})}"
end

# Select the preset of the test configuration file that holds the web login credentials (`username`, `password`)
# for the current test. It is given as option to the browser command run by the CLI when a login page is displayed.
# `ASCLI_UI` is reset before each test. Does nothing in manual mode (no auto browser).
# @param preset [String] Name of the preset in the test configuration file
# @return [void]
def select_login_preset(preset)
  return if BROWSER_COMMAND.nil?
  ENV['ASCLI_UI'] = browser_ui_option("--login-preset=#{preset}")
end

# Ensure the test keychain is present and unlocked for tests on macOS.
# @return [void]
def ensure_test_keychain
  return unless Aspera::Environment.instance.os.eql?(Aspera::Environment::OS_MACOS)
  kc = Aspera::Keychain::MacosSecurity::Keychain.by_name(TEST_KEYCHAIN_NAME)
  if kc.nil?
    kc_path = (TMP / "#{TEST_KEYCHAIN_NAME}.keychain-db").to_s
    kc = Aspera::Keychain::MacosSecurity::Keychain.create(kc_path, password: TEST_KEYCHAIN_PASS)
    kc.set_settings(timeout: 7200)
    existing = Aspera::Keychain::MacosSecurity::Keychain.list
    Aspera::Keychain::MacosSecurity::Keychain.search_list = [kc] + existing
    kc.unlock(password: TEST_KEYCHAIN_PASS)
  end
end

# Aspera::Rest::Client on the MCP endpoint (`/mcp`, as `/` is the discovery endpoint) that handles the MCP HTTP transport specifics:
#   1. Requests must accept both JSON and SSE, else HTTP 406 (`create` sets JSON only).
#   2. The Mcp-Session-Id header must be captured from the first response and replayed on subsequent calls.
#   3. Responses with notifications are SSE: the JSON-RPC response is the last `data:` frame.
class McpHttpClient < Aspera::Rest::Client
  ACCEPT = [Aspera::Mime::JSON, Aspera::Mime::EVENT_STREAM].join(', ')

  # @param port          [Integer] Local port where MCP server listens
  # @param extra_headers [Hash]    Optional additional request headers
  def initialize(port, extra_headers = {})
    super(base_url: "http://127.0.0.1:#{port}/mcp", headers: extra_headers)
    @mcp_session_id = nil
  end

  # Perform an HTTP call while managing session ID and format
  # @param ret     [Symbol] Return type (:data, :resp, :both)
  # @param kwargs  [Hash]   Additional arguments forwarded to super
  # @return [Object] Parsed response data, HTTP response, or both
  def call(ret: :data, **kwargs)
    headers = {'Accept' => ACCEPT}
    headers['Mcp-Session-Id'] = @mcp_session_id if @mcp_session_id
    kwargs[:headers] = (kwargs[:headers] || {}).merge(headers)
    data, http = super(**kwargs, ret: :both)
    @mcp_session_id ||= http['mcp-session-id']
    case ret
    when :data then data
    when :resp then http
    when :both then [data, http]
    end
  end

  private

  # Parse SSE or plain JSON responses
  # @param result_http [Net::HTTPResponse] HTTP response object
  # @param result_mime [String] MIME type string
  # @return [Object] Parsed JSON data
  def parse_response(result_http, result_mime)
    return super unless result_mime.eql?(Aspera::Mime::EVENT_STREAM)
    last_frame = result_http.body.to_s.scan(/^data: (.*)$/).last
    last_frame && JSON.parse(last_frame.first)
  end
end

# @return [Aspera::Rest::Client] Plain REST client for OAuth endpoints on the given port.
def oauth_api(port)
  Aspera::Rest::Client.new(base_url: "http://127.0.0.1:#{port}")
end

# Register a dynamic OAuth client (RFC 7591) on the given port.
# @param port        [Integer]
# @param client_name [String]
# @return [String] the allocated client_id
def mcp_oauth_register(port, client_name)
  data, res = oauth_api(port).create('oauth/register', {client_name: client_name, redirect_uris: [MCP_REDIRECT_URI]}, exception: false, ret: :both)
  raise "Expected 201 for registration, got #{res.code}" unless res.code == '201'
  client_id = data['client_id']
  raise 'Missing client_id in registration response' unless client_id
  client_id
end

# Build a PKCE verifier/challenge pair.
# @return [Array<String>] [verifier, challenge]
def mcp_pkce_pair
  verifier  = SecureRandom.urlsafe_base64(32)
  challenge = Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
  [verifier, challenge]
end

# Send a JSON-RPC request to the MCP endpoint on the given client.
# @param http_client [Aspera::Rest::Client] pre-built client (carries session state)
# @param method      [String]  JSON-RPC method name (e.g. "initialize", "tools/list")
# @param params      [Hash]    Method parameters
# @param id          [Integer] JSON-RPC request id
# @return [Object] `result` field of the JSON-RPC response
def mcp_call(http_client, method, params, id)
  Aspera::JsonRpc.request(http_client, method, [params], id)
end

# Full OAuth 2.0 / PKCE flow test against the MCP OAuth server (port 13780).
# Covers: discovery, dynamic client registration, PKCE authorize/allow with access code, token exchange,
# MCP call with bearer token, token refresh, and old-token revocation.
# @param t [TestEnv::Context] Test context
# @return [void]
def mcp_oauth_flow_post(t)
  sleep(1)
  api = oauth_api(13780)
  # 1. Discovery
  disc = api.read('.well-known/oauth-authorization-server')
  raise 'Missing authorization_endpoint'               unless disc['authorization_endpoint']
  raise 'Missing token_endpoint'                       unless disc['token_endpoint']
  raise 'Missing registration_endpoint'                unless disc['registration_endpoint']
  raise 'S256 not advertised'                          unless disc['code_challenge_methods_supported'].include?('S256')
  # 2. Dynamic client registration + PKCE
  client_id           = mcp_oauth_register(13780, 'test')
  verifier, challenge = mcp_pkce_pair
  state               = SecureRandom.hex(8)
  # 3. GET /oauth/authorize — expect consent HTML
  html, res_html = api.read(
    'oauth/authorize',
    {
      client_id: client_id, redirect_uri: MCP_REDIRECT_URI, response_type: 'code',
     state: state, code_challenge: challenge, code_challenge_method: 'S256'
    },
    ret: :both
  )
  raise "Expected 200 for consent page, got #{res_html.code}" unless res_html.code == '200'
  raise 'Expected HTML consent page'                          unless html.include?('allow')
  raise 'Expected access code field on consent page'          unless html.include?('name="consent_secret"')
  consent = {
    client_id: client_id, redirect_uri: MCP_REDIRECT_URI, state: state,
    code_challenge: challenge, code_challenge_method: 'S256', decision: 'allow'
  }
  # 4a. POST /oauth/authorize with a wrong access code — consent page again, no code issued
  res_refused = api.create('oauth/authorize', consent.merge(consent_secret: 'wrong'), content_type: Aspera::Mime::WWW, exception: false, ret: :resp)
  raise "Expected 401 for wrong access code, got #{res_refused.code}" unless res_refused.code == '401'
  # 4b. POST /oauth/authorize (simulate Allow click) — returns 302, must not follow redirect
  res_consent = api.create('oauth/authorize', consent.merge(consent_secret: MCP_AUTH_TOKEN), content_type: Aspera::Mime::WWW, exception: false, ret: :resp)
  raise "Expected 302 redirect, got #{res_consent.code}" unless res_consent.code == '302'
  location = res_consent['Location']
  raise 'Missing Location header' unless location
  code = Aspera::Rest.query_to_h(URI(location).query)['code']
  raise 'Missing code in redirect' unless code
  # 5. POST /oauth/token — exchange code for tokens
  tokens, res_token = api.create(
    'oauth/token',
    {grant_type: 'authorization_code', code: code, client_id: client_id, redirect_uri: MCP_REDIRECT_URI, code_verifier: verifier},
    content_type: Aspera::Mime::WWW, exception: false, ret: :both
  )
  raise "Expected 200 for token, got #{res_token.code}" unless res_token.code == '200'
  access_token  = tokens['access_token']
  refresh_token = tokens['refresh_token']
  raise 'Missing access_token'  unless access_token
  raise 'Missing refresh_token' unless refresh_token
  raise 'Wrong token_type'      unless tokens['token_type'] == 'Bearer'
  raise 'Missing expires_in'    if tokens['expires_in'].to_i <= 0
  # 6. Use access_token for an MCP initialize call
  mcp_call(McpHttpClient.new(13780, 'Authorization' => "Bearer #{access_token}"), 'initialize', MCP_INIT_PARAMS, 1)
  # 7. POST /oauth/token — refresh
  new_tokens, res_refresh = api.create(
    'oauth/token',
    {grant_type: 'refresh_token', refresh_token: refresh_token},
    content_type: Aspera::Mime::WWW, exception: false, ret: :both
  )
  raise "Expected 200 for refresh, got #{res_refresh.code}" unless res_refresh.code == '200'
  raise 'Missing new access_token after refresh'  unless new_tokens['access_token']
  raise 'Missing new refresh_token after refresh' unless new_tokens['refresh_token']
  raise 'Refresh token should rotate'             if new_tokens['refresh_token'] == refresh_token
  # 8. Old refresh token must be revoked
  res_reuse = api.create(
    'oauth/token', {
      grant_type:    'refresh_token',
      refresh_token: refresh_token
    },
    content_type: Aspera::Mime::WWW, exception: false, ret: :resp
  )
  raise "Expected 400 for reused refresh token, got #{res_reuse.code}" unless res_reuse.code == '400'
  t.stop_process(:mcp_oauth_flow)
end

# OAuth deny flow test (port 13781): registers a client, then posts decision=deny and
# verifies the redirect carries error=access_denied with the original state.
# @param t [TestEnv::Context] Test context
# @return [void]
def mcp_oauth_deny_post(t)
  sleep(1)
  api                = oauth_api(13781)
  client_id          = mcp_oauth_register(13781, 'test-deny')
  _, challenge       = mcp_pkce_pair
  state              = 'deny-state'
  # POST authorize with decision=deny — must redirect with error=access_denied
  res = api.create(
    'oauth/authorize', {
      client_id:             client_id,
      redirect_uri:          MCP_REDIRECT_URI,
      state:                 state,
      code_challenge:        challenge,
      code_challenge_method: 'S256',
      decision:              'deny'
    },
    content_type: Aspera::Mime::WWW, exception: false, ret: :resp
  )
  raise "Expected 302 on deny, got #{res.code}" unless res.code == '302'
  params = Aspera::Rest.query_to_h(URI(res['Location']).query)
  raise "Expected error=access_denied, got #{params}" unless params['error'] == 'access_denied'
  raise 'Expected state to be forwarded'              unless params['state'] == state
  t.stop_process(:mcp_oauth_deny)
end

# Secret entered on a web page (port 13782), with protocol 2026-07-28: a command with `@secret:` returns `input_required`
# with the URL of the page (URL mode elicitation), the page asks for the access code, and the retried call executes the command
# with the secret, hidden in the result.
# @param t [TestEnv::Context] Test context
# @return [void]
def mcp_http_secret_post(t)
  sleep(1)
  tool_name = 'execute_ascli_command'
  # Modern requests carry protocol version, method and name in headers too
  client = McpHttpClient.new(
    13782,
    'Authorization'        => "Bearer #{MCP_AUTH_TOKEN}",
    'MCP-Protocol-Version' => MCP_MODERN_VERSION,
    'Mcp-Method'           => 'tools/call',
    'Mcp-Name'             => tool_name
  )
  params = {
    name:      tool_name,
    arguments: {args: %w[config echo @secret:test]},
    _meta:     {
      'io.modelcontextprotocol/protocolVersion'    => MCP_MODERN_VERSION,
      'io.modelcontextprotocol/clientCapabilities' => {elicitation: {url: {}}}
    }
  }
  # 1. The command needs a secret: the client is asked to open the page
  first = mcp_call(client, 'tools/call', params, 1)
  raise "Expected input_required, got #{first}" unless first['resultType'] == 'input_required'
  request_id, request = first['inputRequests'].first
  raise "Expected URL mode elicitation, got #{request}" unless request['method'] == 'elicitation/create' && request.dig('params', 'mode') == 'url'
  page_path = URI(request.dig('params', 'url')).path.delete_prefix('/')
  # 2. The user enters the secret on the page, with the access code
  api = oauth_api(13782)
  html = api.read(page_path)
  raise 'Expected access code field on secret page' unless html.include?('name="access_code"')
  form = {secret: 'S3cret-value', decision: 'submit'}
  res_refused = api.create(page_path, form.merge(access_code: 'wrong'), content_type: Aspera::Mime::WWW, exception: false, ret: :resp)
  raise "Expected 401 for wrong access code, got #{res_refused.code}" unless res_refused.code == '401'
  res_page = api.create(page_path, form.merge(access_code: MCP_AUTH_TOKEN), content_type: Aspera::Mime::WWW, exception: false, ret: :resp)
  raise "Expected 200 for secret, got #{res_page.code}" unless res_page.code == '200'
  # 3. The client retries the call: the command is executed with the secret, hidden in the result
  final = mcp_call(client, 'tools/call', params.merge(inputResponses: {request_id => {action: 'accept'}}, requestState: first['requestState']), 2)
  text = final.dig('content', 0, 'text')
  # Placeholder is ASCII when the output of the server is not a terminal supporting Unicode
  raise "Expected the secret hidden in result, got #{final}" unless final['isError'] == false && ['🔑', '***'].include?(text)
  t.stop_process(:mcp_http_secret)
end

# Token-auth server test (port 13779): verifies that the MCP endpoint returns 401 without
# a bearer token and 200 with the correct token.
# @param t [TestEnv::Context] Test context
# @return [void]
def mcp_auth_token_server_post(t)
  sleep(1)
  # Without token: expect 401
  res_no_auth = McpHttpClient.new(13779).create('', {jsonrpc: '2.0', id: 1, method: 'initialize', params: MCP_INIT_PARAMS}, exception: false, ret: :resp)
  raise "Expected 401 without token, got #{res_no_auth.code}" unless res_no_auth.code == '401'
  raise 'Expected WWW-Authenticate header'                    unless res_no_auth['WWW-Authenticate']
  # With correct token: expect success
  mcp_call(McpHttpClient.new(13779, 'Authorization' => "Bearer #{MCP_AUTH_TOKEN}"), 'initialize', MCP_INIT_PARAMS, 1)
  t.stop_process(:mcp_auth_token_server)
end

# HTTP MCP server test (port 13778): calls initialize then tools/list and verifies that
# execute_ascli_command is advertised.
# @param t [TestEnv::Context] Test context
# @return [void]
def mcp_http_tools_list_post(t)
  sleep(1)
  client = McpHttpClient.new(13778)
  mcp_call(client, 'initialize', MCP_INIT_PARAMS, 1)
  tool_names = mcp_call(client, 'tools/list', {}, 2).fetch('tools', []).map { |tool| tool['name'] }
  raise "execute_ascli_command not listed: #{tool_names}" unless tool_names.include?('execute_ascli_command')
  t.stop_process(:mcp_http_tools_list)
end

# HTTP MCP server test (port 13777): calls initialize then tools/call execute_ascli_command
# and verifies the returned version matches Aspera::Cli::VERSION.
# @param t [TestEnv::Context] Test context
# @return [void]
def mcp_http_server_post(t)
  sleep(1)
  client = McpHttpClient.new(13777)
  mcp_call(client, 'initialize', MCP_INIT_PARAMS, 1)
  result = mcp_call(client, 'tools/call', {name: 'execute_ascli_command', arguments: {args: %w[config gem version]}}, 2)
  raise "Unexpected result: #{result}" unless result.dig('content', 0, 'text') == Aspera::Cli::VERSION
  t.stop_process(:mcp_http_server)
end

# stdio MCP server test: reads the output file and verifies initialize (id=1) and
# tools/call (id=2) responses are present and carry the expected version.
# @param t [TestEnv::Context] Test context
# @return [void]
def mcp_stdio_call_post(t)
  lines     = t.out_file.read.lines.map(&:chomp).reject(&:empty?)
  init_line = lines.find { |l| JSON.parse(l)['id'] == 1 rescue false }
  raise 'No initialize response found' unless init_line
  call_line = lines.find { |l| JSON.parse(l)['id'] == 2 rescue false }
  raise 'No tools/call response found' unless call_line
  result = JSON.parse(call_line)
  raise "Unexpected result: #{result}" unless result.dig('result', 'content', 0, 'text') == Aspera::Cli::VERSION
end
