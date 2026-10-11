# frozen_string_literal: true

# Stub the MCP gem classes so this spec can run without the optional `mcp` gem.
unless defined?(MCP::Server)
  module MCP
    class Configuration
      def initialize(**_kwargs); end
    end

    class Server
      attr_reader :name, :version, :description

      def initialize(name:, version:, tools:, configuration: nil, **opts)
        @name        = name
        @version     = version
        @description = opts[:description]
      end

      module Transports
        class StreamableHTTPTransport
          def initialize(_server, **_opts); end
        end

        class StdioTransport
          def initialize(_server, **_opts); end

          def open; end
        end
      end
    end

    class Tool
      class << self
        def tool_name(_name); end

        def description(_text); end

        def input_schema(**_kwargs); end
      end
    end
  end
end

require 'aspera/cli/plugins/mcp'

RSpec.describe(Aspera::Cli::Plugins::Mcp) do
  # Build a minimal plugin instance without a real CLI context.
  subject(:plugin) do
    described_class.allocate
  end

  # -------------------------------------------------------------------------
  # check_auth_config
  # -------------------------------------------------------------------------
  describe '#check_auth_config (private)' do
    let(:local_binds)    { %w[127.0.0.1 ::1 localhost] }
    let(:nonlocal_bind)  { '0.0.0.0' }

    context 'with a local bind address' do
      it 'accepts no auth at all' do
        local_binds.each do |bind|
          expect { plugin.send(:check_auth_config, nil, false, bind) }.not_to(raise_error)
        end
      end

      it 'accepts auth_token alone' do
        expect { plugin.send(:check_auth_config, 'tok', false, '127.0.0.1') }.not_to(raise_error)
      end

      it 'accepts oauth_enabled alone' do
        expect { plugin.send(:check_auth_config, nil, true, '127.0.0.1') }.not_to(raise_error)
      end
    end

    context 'with a non-local bind address' do
      it 'raises BadArgument when neither auth_token nor oauth_enabled is provided' do
        expect { plugin.send(:check_auth_config, nil, false, nonlocal_bind) }
          .to(raise_error(Aspera::Cli::BadArgument, /auth_token or oauth is required/))
      end

      it 'accepts auth_token' do
        expect { plugin.send(:check_auth_config, 'secret', false, nonlocal_bind) }.not_to(raise_error)
      end

      it 'accepts oauth_enabled' do
        expect { plugin.send(:check_auth_config, nil, true, nonlocal_bind) }.not_to(raise_error)
      end

      it 'accepts both auth_token and oauth_enabled together' do
        expect { plugin.send(:check_auth_config, 'secret', true, nonlocal_bind) }.not_to(raise_error)
      end
    end

    it 'raises BadArgument when auth_token is an empty string' do
      expect { plugin.send(:check_auth_config, '', false, '127.0.0.1') }
        .to(raise_error(Aspera::Cli::BadArgument, /must not be empty/))
    end
  end

  # -------------------------------------------------------------------------
  # pkce_valid?
  # -------------------------------------------------------------------------
  describe '#pkce_valid? (private)' do
    # Compute a valid S256 challenge for a known verifier
    let(:verifier) { 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk' }
    let(:challenge) do
      require 'openssl'
      require 'base64'
      Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
    end

    it 'returns true for a matching verifier/challenge pair' do
      expect(plugin.send(:pkce_valid?, verifier, challenge)).to(be(true))
    end

    it 'returns false for a wrong verifier' do
      expect(plugin.send(:pkce_valid?, 'wrong-verifier', challenge)).to(be(false))
    end

    it 'returns false for a tampered challenge' do
      expect(plugin.send(:pkce_valid?, verifier, challenge.reverse)).to(be(false))
    end
  end

  # -------------------------------------------------------------------------
  # oauth_metadata
  # -------------------------------------------------------------------------
  describe '#oauth_metadata (private)' do
    let(:base_url) { 'http://localhost:3000' }
    let(:metadata) { plugin.send(:oauth_metadata, base_url) }

    it 'includes the issuer equal to base_url' do
      expect(metadata[:issuer]).to(eq(base_url))
    end

    it 'points authorization_endpoint under base_url' do
      expect(metadata[:authorization_endpoint]).to(start_with(base_url))
      expect(metadata[:authorization_endpoint]).to(include('/oauth/authorize'))
    end

    it 'points token_endpoint under base_url' do
      expect(metadata[:token_endpoint]).to(start_with(base_url))
      expect(metadata[:token_endpoint]).to(include('/oauth/token'))
    end

    it 'advertises S256 as the only code challenge method' do
      expect(metadata[:code_challenge_methods_supported]).to(eq(['S256']))
    end

    it 'advertises authorization_code and refresh_token grant types' do
      expect(metadata[:grant_types_supported]).to(include('authorization_code', 'refresh_token'))
    end
  end

  # -------------------------------------------------------------------------
  # oauth_authorize_html
  # -------------------------------------------------------------------------
  describe '#oauth_authorize_html (private)' do
    # Stub WEBrick::HTTPUtils.escape_html before the call
    before do
      require 'webrick'
    end

    let(:params) do
      {
        'client_id'             => 'bob',
        'redirect_uri'          => 'http://localhost:9999/cb',
        'state'                 => 'xyz',
        'code_challenge'        => 'abc123',
        'code_challenge_method' => 'S256'
      }
    end
    let(:html) { plugin.send(:oauth_authorize_html, params, 'http://localhost:3000') }

    it 'contains the client_id' do
      expect(html).to(include('bob'))
    end

    it 'contains a form POSTing to /oauth/authorize' do
      expect(html).to(include('action="http://localhost:3000/oauth/authorize"'))
      expect(html).to(include('method="POST"'))
    end

    it 'embeds the PKCE challenge as a hidden field' do
      expect(html).to(include('name="code_challenge"'))
      expect(html).to(include('value="abc123"'))
    end

    it 'has Allow and Deny buttons' do
      expect(html).to(include('value="allow"'))
      expect(html).to(include('value="deny"'))
    end

    it 'escapes HTML in client_id to prevent XSS' do
      xss_params = params.merge('client_id' => '<script>alert(1)</script>')
      xss_html = plugin.send(:oauth_authorize_html, xss_params, 'http://localhost:3000')
      expect(xss_html).not_to(include('<script>'))
    end
  end
end
