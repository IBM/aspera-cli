# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Faspex5::Api — no server needed.

require 'spec_helper'
require_relative '../api'
require_relative '../../../line_logger'
require 'base64'
require 'json'
require 'logger'
require 'securerandom'
require 'stringio'
require 'webrick'

RSpec.describe(Aspera::Plugins::Faspex5::Api) do
  describe 'web authentication' do
    # @return [Aspera::OAuth::Web]
    def web_oauth(**kwargs)
      described_class.new(url: 'https://faspex.example.com/aspera/faspex', auth: :web, client_id: 'CLIENT', redirect_uri: 'http://localhost:12345', **kwargs).oauth
    end

    it 'uses PKCE' do
      expect(web_oauth.instance_variable_get(:@pkce)).to(be(true))
    end

    it 'sends the client secret when it is set (API client with HTTP basic auth)' do
      client_secret = SecureRandom.hex
      expect(web_oauth(client_secret: client_secret).params).to(eq({client_id: 'CLIENT', client_secret: client_secret}))
    end

    it 'sends no client secret when it is not set' do
      expect(web_oauth.params).to(eq({client_id: 'CLIENT'}))
    end
  end

  describe 'public link authentication' do
    let(:log) { Aspera::Log.instance }
    let(:output) { StringIO.new }
    # In-memory token cache
    let(:store) do
      Class.new do
        def initialize; @data = {}; end
        def get(id); @data[id]; end
        def put(id, value); @data[id] = value; end
        def delete(id); @data.delete(id); end
        def garbage_collect(_category, _max_age); nil; end
      end.new
    end

    # Local Faspex: the public link redirects to the page of the package, with the same context; the context (with the passcode) is exchanged for a code,
    # in the URL of the redirect (`Location` and body) with the state (the context), then for a token.
    # Authorization at `/auth` (FaspexPubLink alone) and `/aspera/faspex/auth` (Api with the link). Each code is recorded in `@codes`.
    around do |example|
      factory = Aspera::OAuth::Factory.instance
      parameters = Aspera::Rest::Parameters.instance
      saved = {persist: factory.instance_variable_get(:@persist), session_cb: parameters.session_cb, logger: log.logger}
      factory.persist_mgr = store
      @codes = []
      codes = @codes
      server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      server.mount_proc('/') do |req, res|
        res.status = 302
        res['Location'] = "/aspera/faspex/public/package?#{req.query_string}"
      end
      server.mount_proc('/aspera/faspex/public/package') { |_req, res| res.body = '<html></html>' }
      server.mount_proc('/aspera/faspex/config.js') { |_req, res| res.body = "window.config = {\n  client_id: 'app',\n  redirect_uri: '/aspera/faspex/callback'\n}\n" }
      server.mount_proc('/aspera/faspex/api/v5/account') do |_req, res|
        res['Content-Type'] = 'application/json'
        res.body = JSON.generate({'name' => 'external'})
      end
      # Invitation (create or list): its access URL is a public link with its context, the last one of `@access_urls`
      @access_urls = []
      access_urls = @access_urls
      server.mount_proc('/aspera/faspex/api/v5/invitations') do |req, res|
        invitation = {'id' => '1', 'public' => true, 'recipient_type' => 'user', 'access_url' => access_urls.last}
        res['Content-Type'] = 'application/json'
        res.status = 201 if req.request_method.eql?('POST')
        res.body = JSON.generate(req.request_method.eql?('POST') ? invitation : {'invitations' => [invitation], 'total_count' => 1})
      end
      %w[/auth /aspera/faspex/auth].each do |path|
        server.mount_proc("#{path}/authorize_public_link") do |req, res|
          codes.push(SecureRandom.alphanumeric(16))
          res.status = 302
          res['Location'] = "https://127.0.0.1/aspera/faspex/callback?code=#{codes.last}&state=#{URI.encode_www_form_component(req.query['state'])}"
          res.body = %Q(<a href="#{res['Location']}">Found</a>.)
        end
        server.mount_proc("#{path}/token") do |_req, res|
          res['Content-Type'] = 'application/json'
          res.body = JSON.generate({'access_token' => SecureRandom.alphanumeric(16), 'token_type' => 'bearer', 'expires_in' => 3600})
        end
      end
      thread = Thread.new { server.start }
      sleep(0.01) until server.status.eql?(:Running)
      @base_url = "http://127.0.0.1:#{server.config[:Port]}"
      @url = "#{@base_url}/auth"
      log.instance_variable_set(:@logger, Logger.new(output))
      log.formatter = ->(_s, _d, _p, m) { "#{m}\n" }
      # As `ascli` at level trace2 (Cli::Http#update_session): debug output of Net::HTTP
      parameters.session_cb = ->(http) { http.set_debug_output(Aspera::LineLogger.new(:trace2)) if log.logger.trace2? }
      example.run
    ensure
      factory.instance_variable_set(:@persist, saved[:persist])
      parameters.session_cb = saved[:session_cb]
      log.instance_variable_set(:@logger, saved[:logger])
      server&.shutdown
      thread&.join
    end

    it 'hides the code in logs, at all levels' do
      %i[debug trace1 trace2].each do |level|
        log.level = level
        Aspera::Plugins::Faspex5::FaspexPubLink.new(context: "context_#{level}", redirect_uri: 'https://127.0.0.1/aspera/faspex/callback', base_url: @url, params: {client_id: 'app'}).token
      end
      expect(@codes.size).to(eq(3))
      @codes.each { |code| expect(output.string).not_to(include(code)) }
      expect(output.string).to(include('"code"', 'callback?code=', 'Location: https://127.0.0.1/aspera/faspex/callback?code=', 'grant_type=authorization_code&code='))
    end

    it 'hides the passcode of the link, and its context, in logs, at all levels' do
      # A passcode and a context for each level: the registry of secrets is shared
      links = %i[debug trace1 trace2].map do |level|
        log.level = level
        passcode = SecureRandom.alphanumeric(16)
        # base64 with padding, URL-encoded in the link
        context = Base64.strict_encode64(JSON.generate({'resource' => 'packages', 'type' => 'received_package', 'id' => '1', 'passcode' => passcode}))
        api = described_class.new(url: "#{@base_url}/?context=#{URI.encode_www_form_component(context)}", auth: :public_link)
        expect(api.pub_link_context['passcode']).to(eq(passcode))
        api.read('account')
        {passcode: passcode, context: context}
      end
      expect(@codes.size).to(eq(3))
      links.each do |link|
        # without padding: also URL-encoded
        expect(output.string).not_to(include(link[:passcode], link[:context].delete('=')))
      end
      # The link is shown, but its context
      expect(output.string).to(include(
        "Client.new(#{@base_url}/?context=", 'GET /aspera/faspex/public/package?context=', '"passcode"', 'authorize_public_link?response_type=code&state=', 'callback?code=', '"name"'
      ))
    end

    it 'hides the context of the access URL of an invitation in logs, at all levels, and returns it' do
      # A context for each level: the registry of secrets is shared
      contexts = %i[debug trace1 trace2].map do |level|
        log.level = level
        # Passcode to send a package to a user: base64 with padding, not URL-encoded
        context = Base64.strict_encode64(JSON.generate({'resource' => 'invitations', 'type' => 'external_upload_to_user', 'id' => '1', 'passcode' => SecureRandom.alphanumeric(16)}))
        @access_urls.push("#{@base_url}/aspera/faspex/public/send?context=#{context}")
        api = described_class.new(url: "#{@base_url}/aspera/faspex", auth: :boot, password: SecureRandom.alphanumeric(16))
        expect(api.create('invitations', {'email_address' => 'john@example.com'})['access_url']).to(eq(@access_urls.last))
        expect(api.read('invitations')['invitations'].first['access_url']).to(eq(@access_urls.last))
        context
      end
      contexts.each { |context| expect(output.string).not_to(include(context.delete('='))) }
      expect(output.string).to(include('"access_url": "', "#{@base_url}/aspera/faspex/public/send?context="))
    end
  end
end
