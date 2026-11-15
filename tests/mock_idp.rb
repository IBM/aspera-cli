#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/aspera/web_server_simple'
require_relative '../lib/aspera/web_page'
require_relative '../lib/aspera/servlet_helpers'
require_relative '../lib/aspera/mime'
require_relative '../lib/aspera/log'
require 'optparse'
require 'securerandom'
require 'webrick'
require 'json'
require 'openssl'

# Mock Identity Provider and Faspex 5 API server for local testing of `--auth=web`.
# Supports authorization code grant, token refresh, and basic Faspex 5 endpoints.
class MockIdpServlet < WEBrick::HTTPServlet::AbstractServlet
  include Aspera::ServletHelpers

  HTML_TEMPLATE_PATH = File.expand_path('../lib/aspera/oauth/server/authorize.html.erb', __dir__)

  # @param server      [WEBrick::HTTPServer] WEBrick server instance
  # @param access_code [String, nil] Access code required on consent page (positional: WEBrick passes mount arguments as is)
  def initialize(server, access_code = nil)
    super(server)
    @access_code = access_code
  end

  # WEBrick creates a new servlet instance for each request: the state is shared at class level.
  @mutex          = Mutex.new
  @pending_codes  = {}
  @access_tokens  = {}
  @refresh_tokens = {}

  class << self
    attr_reader :mutex, :pending_codes, :access_tokens, :refresh_tokens
  end

  def mutex = self.class.mutex

  def pending_codes = self.class.pending_codes

  def access_tokens = self.class.access_tokens

  def refresh_tokens = self.class.refresh_tokens

  def do_GET(req, res)
    case req.path
    when %r{(?:/aspera/faspex)?/auth/authorize$}
      handle_authorize_get(req, res)
    when %r{(?:/aspera/faspex)?/api/v5/inbox_all/packages$}, %r{(?:/aspera/faspex)?/api/v5/packages$}
      handle_packages_get(req, res)
    when %r{(?:/aspera/faspex)?/api/v5/configuration/ping$}, %r{(?:/aspera/faspex)?/health$}
      handle_health_get(res)
    when '/'
      res.status = 200
      res['Content-Type'] = 'text/plain'
      res.body = 'Mock IdP ready'
    else
      res.status = 404
      res.body = 'Not found'
    end
  end

  def do_POST(req, res)
    case req.path
    when %r{(?:/aspera/faspex)?/auth/authorize$}
      handle_authorize_post(req, res)
    when %r{(?:/aspera/faspex)?/auth/token$}
      handle_token_post(req, res)
    else
      res.status = 404
      res.body = 'Not found'
    end
  end

  private

  def handle_authorize_get(req, res)
    params = req.query
    res.status = 200
    Aspera::WebPage.secure_headers(res)
    res.body = Aspera::WebPage.render(
      HTML_TEMPLATE_PATH,
      title:                 'Mock IdP Authorization',
      description:           'the Mock Faspex 5 service',
      action_url:            req.path,
      client_id:             params['client_id'].to_s,
      redirect_uri:          params['redirect_uri'].to_s,
      redirect_origin:       params['redirect_uri'].to_s,
      state:                 params['state'].to_s,
      code_challenge:        params['code_challenge'].to_s,
      code_challenge_method: params['code_challenge_method'].to_s,
      secret_required:       !@access_code.nil?,
      error:                 nil
    )
  end

  def handle_authorize_post(req, res)
    params       = WEBrick::HTTPUtils.parse_query(req.body.to_s)
    client_id    = params['client_id']
    redirect_uri = params['redirect_uri']
    state        = params['state']
    decision     = params['decision']

    if decision != 'allow'
      sep = redirect_uri.include?('?') ? '&' : '?'
      res.status = 302
      res['Location'] = "#{redirect_uri}#{sep}error=access_denied&state=#{WEBrick::HTTPUtils.escape_form(state.to_s)}"
      return
    end

    if @access_code
      consent_secret = params['consent_secret']
      unless consent_secret && OpenSSL.secure_compare(consent_secret.to_s, @access_code)
        res.status = 401
        Aspera::WebPage.secure_headers(res)
        res.body = Aspera::WebPage.render(
          HTML_TEMPLATE_PATH,
          title:                 'Mock IdP Authorization',
          description:           'the Mock Faspex 5 service',
          action_url:            req.path,
          client_id:             client_id.to_s,
          redirect_uri:          redirect_uri.to_s,
          redirect_origin:       redirect_uri.to_s,
          state:                 state.to_s,
          code_challenge:        params['code_challenge'].to_s,
          code_challenge_method: params['code_challenge_method'].to_s,
          secret_required:       true,
          error:                 'Invalid access code'
        )
        return
      end
    end

    code = SecureRandom.urlsafe_base64(24)
    mutex.synchronize do
      pending_codes[code] = {
        client_id:    client_id,
        redirect_uri: redirect_uri,
        expires_at:   Time.now + 120
      }
    end

    sep = redirect_uri.include?('?') ? '&' : '?'
    res.status = 302
    res['Location'] = "#{redirect_uri}#{sep}code=#{WEBrick::HTTPUtils.escape_form(code)}&state=#{WEBrick::HTTPUtils.escape_form(state.to_s)}"
  end

  def handle_token_post(req, res)
    params     = WEBrick::HTTPUtils.parse_query(req.body.to_s)
    grant_type = params['grant_type']

    case grant_type
    when 'authorization_code'
      handle_token_authorization_code(params, res)
    when 'refresh_token'
      handle_token_refresh(params, res)
    else
      json_error(res, 400, 'unsupported_grant_type', "Unsupported grant_type: #{grant_type}")
    end
  end

  def handle_token_authorization_code(params, res)
    code   = params['code']
    stored = mutex.synchronize { pending_codes.delete(code) }
    if stored.nil? || stored[:expires_at] < Time.now
      json_error(res, 400, 'invalid_grant', 'Authorization code expired or unknown')
      return
    end

    issue_token_response(res)
  end

  def handle_token_refresh(params, res)
    rt     = params['refresh_token']
    stored = mutex.synchronize { refresh_tokens.delete(rt) }
    if stored.nil? || stored[:expires_at] < Time.now
      json_error(res, 400, 'invalid_grant', 'Refresh token expired or unknown')
      return
    end

    mutex.synchronize { access_tokens.delete(stored[:access_token]) }
    issue_token_response(res)
  end

  def issue_token_response(res)
    access_token  = SecureRandom.urlsafe_base64(32)
    refresh_token = SecureRandom.urlsafe_base64(48)
    now           = Time.now

    mutex.synchronize do
      access_tokens[access_token]   = now + 3600
      refresh_tokens[refresh_token] = {access_token: access_token, expires_at: now + 86_400}
    end

    json_response(
      res, 200, {
        'access_token'  => access_token,
        'token_type'    => 'Bearer',
        'expires_in'    => 3600,
        'refresh_token' => refresh_token
      },
      headers: {'Cache-Control' => 'no-store'}
    )
  end

  def handle_packages_get(req, res)
    token = authorization(req, 'Bearer')
    valid = mutex.synchronize { access_tokens[token] && access_tokens[token] > Time.now }
    unless valid
      json_error(res, 401, 'unauthorized', 'Invalid or expired bearer token', headers: {'WWW-Authenticate' => 'Bearer realm="MockIdP"'})
      return
    end

    packages = [
      {
        'id'           => 'mock_pkg_1',
        'title'        => 'Mock Package 1',
        'status'       => 'completed',
        'release_date' => '2026-01-01T00:00:00Z',
        'total_bytes'  => 1024,
        'total_files'  => 1,
        'sender'       => {'name' => 'mock_user'},
        'recipients'   => [{'name' => 'mock_recipient'}]
      }
    ]
    json_response(res, 200, {'packages' => packages, 'total_count' => packages.length})
  end

  def handle_health_get(res)
    res['X-IBM-Aspera'] = '5.0.0'
    json_response(res, 200, {'status' => 'ok', 'version' => '5.0.0'})
  end
end

options = {port: 13_783, access_code: nil, pid_file: nil, https: false}
OptionParser.new do |opts|
  opts.banner = 'Usage: mock_idp.rb [options]'
  opts.on('--port=PORT', Integer, 'Port to listen on') { |v| options[:port] = v }
  opts.on('--https', 'Use HTTPS with a self-signed certificate (the login page of `config web_login` shall be https)') { options[:https] = true }
  opts.on('--access-code=CODE', 'Access code for consent') { |v| options[:access_code] = v }
  opts.on('--pid-file=PATH', 'Path to write PID file') { |v| options[:pid_file] = v }
end.parse!

if options[:pid_file]
  File.write(options[:pid_file], Process.pid)
  at_exit { File.delete(options[:pid_file]) if File.exist?(options[:pid_file]) }
end

uri = URI.parse("#{options[:https] ? 'https' : 'http'}://127.0.0.1:#{options[:port]}")
server = Aspera::WebServerSimple.new(uri)
server.mount('/', MockIdpServlet, options[:access_code])
server.start
