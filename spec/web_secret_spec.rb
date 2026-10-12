# frozen_string_literal: true

require 'aspera/cli/web_secret'
require 'net/http'
require 'uri'

RSpec.describe(Aspera::Cli::WebSecret) do
  subject(:web_secret) { described_class.new(base_url: 'http://localhost:3000') }

  before { require 'webrick' }

  # Minimal stand-in for WEBrick::HTTPResponse
  let(:response_class) do
    Class.new do
      attr_accessor :status, :body

      def initialize = @headers = {}
      def [](key) = @headers[key]

      def []=(key, value)
        @headers[key] = value
      end
    end
  end
  let(:request_class) { Struct.new(:request_method, :path, :body) }
  let(:id) { web_secret.create('my password') }

  # @return [Object] response to request on the page of the secret request
  def page(method, form = nil, request_id: id)
    res = response_class.new
    web_secret.handle(request_class.new(method, "#{described_class::PATH_PREFIX}#{request_id}", form && URI.encode_www_form(form)), res)
    res
  end

  describe 'page' do
    it 'is under the base URL' do
      expect(web_secret.url(id)).to(eq("http://localhost:3000/secret/#{id}"))
    end

    it 'shows a form with the prompt, without access code by default' do
      res = page('GET')
      expect(res.status).to(eq(200))
      expect(res.body).to(include('name="secret"'))
      expect(res.body).to(include('my password'))
      expect(res.body).to(include('to execute your command'))
      expect(res.body).not_to(include('name="access_code"'))
    end

    it 'names the requester of the command' do
      web_secret = described_class.new(name: 'ascli MCP server', requester: 'AI assistant')
      res = response_class.new
      web_secret.handle(request_class.new('GET', "/secret/#{web_secret.create('pw')}", nil), res)
      expect(res.body).to(include('requested by the AI assistant'))
      expect(res.body).to(include('the AI assistant does not see it'))
    end

    it 'sets anti-framing, no-cache and no-referrer headers' do
      res = page('GET')
      expect(res['X-Frame-Options']).to(eq('DENY'))
      expect(res['Cache-Control']).to(eq('no-store'))
      expect(res['Referrer-Policy']).to(eq('no-referrer'))
    end

    it 'escapes HTML in the prompt' do
      res = page('GET', request_id: web_secret.create('<script>alert(1)</script>'))
      expect(res.body).not_to(include('<script>alert(1)</script>'))
      expect(res.body).to(include('&lt;script&gt;'))
    end

    it 'receives the secret, then the request is answered' do
      res = page('POST', {secret: 'pass word', decision: 'submit'})
      expect(res.body).to(include('Secret received'))
      expect(res.body).to(include('return to your terminal'))
      expect(web_secret.wait_value(id)).to(eq('pass word'))
      expect(page('GET').status).to(eq(404))
    end

    it 'receives the cancellation' do
      res = page('POST', {decision: 'cancel'})
      expect(res.body).to(include('cancelled'))
      expect { web_secret.wait_value(id) }.to(raise_error(Aspera::Cli::Error, /cancelled/))
    end

    it 'refuses an unknown request' do
      expect(page('GET', request_id: 'unknown').status).to(eq(404))
    end

    it 'forgets deleted requests' do
      web_secret.delete([id])
      expect(web_secret.prompt(id)).to(be_nil)
      expect { web_secret.wait_value(id) }.to(raise_error(Aspera::Cli::Error, /expired/))
    end

    context 'with an access code' do
      subject(:web_secret) { described_class.new(base_url: 'http://localhost:3000', access_code: 'code') }

      it 'asks for the access code' do
        expect(page('GET').body).to(include('name="access_code"'))
      end

      it 'refuses a wrong access code' do
        res = page('POST', {secret: 's', access_code: 'wrong', decision: 'submit'})
        expect(res.status).to(eq(401))
        expect(res.body).to(include('Invalid access code'))
        expect(web_secret.prompt(id)).to(eq('my password'))
        expect(page('GET').status).to(eq(200))
      end

      it 'receives the secret with the right access code' do
        page('POST', {secret: 's', access_code: 'code', decision: 'submit'})
        expect(web_secret.wait_value(id)).to(eq('s'))
      end

      it 'does not need the access code to cancel' do
        page('POST', {decision: 'cancel'})
        expect { web_secret.wait_value(id) }.to(raise_error(Aspera::Cli::Error, /cancelled/))
      end
    end
  end

  describe '.ask' do
    # The user enters the secret in the browser, served by the local web server
    def browser_enters(form)
      allow(Aspera::Environment.instance).to(receive(:open_uri)) do |url|
        Thread.new { Net::HTTP.post_form(URI(url), form) }
      end
    end

    it 'opens the page served by a local web server and returns the secret' do
      browser_enters('secret' => 'S3cret', 'decision' => 'submit')
      expect(described_class.ask('pw')).to(eq('S3cret'))
      expect(Aspera::Environment.instance).to(have_received(:open_uri).with(%r{\Ahttp://127\.0\.0\.1:\d+/secret/}))
    end

    it 'fails when the user cancels' do
      browser_enters('decision' => 'cancel')
      expect { described_class.ask('pw') }.to(raise_error(Aspera::Cli::Error, /cancelled/))
    end
  end
end
