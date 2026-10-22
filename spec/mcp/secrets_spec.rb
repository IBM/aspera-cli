# frozen_string_literal: true

# Stub the result class of the MCP gem so this spec can run without the optional `mcp` gem.
unless defined?(MCP::Server::InputRequiredResult)
  module MCP
    class Server
      class InputRequiredResult
        attr_reader :input_requests, :request_state

        def initialize(input_requests: nil, request_state: nil)
          @input_requests = input_requests
          @request_state  = request_state
        end
      end
    end
  end
end

require 'aspera/cli/mcp/secrets'
require 'json'
require 'uri'
require 'securerandom'

RSpec.describe(Aspera::Cli::Mcp::Secrets) do
  let(:web_secret) { Aspera::Cli::Mcp::Secrets.web_secret(base_url: 'http://localhost:3000') }
  # Value of the secret is generated, none in source
  let(:secret) { SecureRandom.alphanumeric(12) }

  before { require 'webrick' }

  # Simulate the user entering the secret on the page
  def enter_secret(request_id, secret)
    page_request = Struct.new(:request_method, :path, :body).new('POST', "/secret/#{request_id}", URI.encode_www_form(secret: secret, decision: 'submit'))
    web_secret.handle(page_request, Struct.new(:status, :body) { def []=(*); end }.new)
  end

  # -------------------------------------------------------------------------
  # Secrets of a tool call, over rounds of multi round-trip requests
  # -------------------------------------------------------------------------
  describe Aspera::Cli::Mcp::Secrets::Call do
    # Minimal stand-in for MCP::ServerContext
    let(:context_class) do
      Struct.new(:request_state, :client_capabilities, :input_responses, :modern, :completed, keyword_init: true) do
        def input_response(key) = input_responses&.[](key)
        def modern? = modern
        def report_progress(*); end

        def notify_elicitation_complete(elicitation_id:)
          (self.completed ||= []).push(elicitation_id)
        end
      end
    end
    let(:capabilities) { {elicitation: {url: {}}} }
    let(:first_round) { context_class.new(client_capabilities: capabilities, modern: true) }

    # @return [MCP::Server::InputRequiredResult] result of first round of a call needing a secret
    def request_secret(context = first_round)
      call = described_class.new(web_secret, context)
      prompt = catch(Aspera::Cli::Mcp::Secrets::THROW_TAG) { call.value('pw') }
      call.input_required(prompt)
    end

    # @return [Struct] context of the second round, with the action of the user in the client
    def second_round(result, action: 'accept', modern: true)
      request_id = result.input_requests.keys.first
      context_class.new(client_capabilities: capabilities, modern: modern, request_state: result.request_state, input_responses: {request_id => {action: action}})
    end

    it 'throws the prompt when the secret was not requested yet' do
      expect(catch(Aspera::Cli::Mcp::Secrets::THROW_TAG) { described_class.new(web_secret, first_round).value('pw') }).to(eq('pw'))
    end

    it 'needs client support of URL mode elicitation' do
      expect(described_class.new(web_secret, first_round).url_elicitation?).to(be(true))
      expect(described_class.new(web_secret, context_class.new(client_capabilities: {'elicitation' => {'url' => {}}})).url_elicitation?).to(be(true))
      expect(described_class.new(web_secret, context_class.new(client_capabilities: {elicitation: {}})).url_elicitation?).to(be(false))
      expect(described_class.new(web_secret, nil).url_elicitation?).to(be(false))
      expect(described_class.new(nil, first_round).url_elicitation?).to(be(false))
    end

    it 'requests the URL of the page, with the request in the state' do
      result = request_secret
      request_id, request = result.input_requests.first
      expect(request[:method]).to(eq('elicitation/create'))
      expect(request[:params]).to(include(mode: 'url', url: web_secret.url(request_id)))
      expect(request[:params]).not_to(have_key(:elicitationId))
      expect(request[:params][:message]).to(include('pw'))
      expect(JSON.parse(result.request_state)).to(eq([request_id]))
    end

    it 'gives the secret entered on the page on next round, then hides it and forgets it' do
      # Placeholder of hidden secret depends on Unicode support
      Aspera::Environment.unicode = true
      result = request_secret
      request_id = result.input_requests.keys.first
      enter_secret(request_id, secret)
      call = described_class.new(web_secret, second_round(result))
      expect(call.value('pw')).to(eq(secret))
      expect(Aspera::SecretHider.instance.hidden_copy({'a' => ["x #{secret} y"], 'b' => 1})).to(eq({'a' => ['x 🔑 y'], 'b' => 1}))
      call.finish
      expect(web_secret.prompt(request_id)).to(be_nil)
    ensure
      Aspera::Environment.unicode = nil
    end

    it 'adds elicitation identifier and completion notification for 2025-11-25 clients' do
      result = request_secret(context_class.new(client_capabilities: capabilities, modern: false))
      request_id, request = result.input_requests.first
      expect(request[:params][:elicitationId]).to(eq(request_id))
      enter_secret(request_id, secret)
      context = second_round(result, modern: false)
      described_class.new(web_secret, context).value('pw')
      expect(context.completed).to(eq([request_id]))
    end

    it 'fails when the user declines in the client' do
      result = request_secret
      call = described_class.new(web_secret, second_round(result, action: 'decline'))
      expect { call.value('pw') }.to(raise_error(Aspera::Cli::Error, /refused in MCP client: decline/))
    end

    it 'fails when the command changed between rounds' do
      result = request_secret
      call = described_class.new(web_secret, second_round(result))
      expect { call.value('other') }.to(raise_error(Aspera::Cli::BadArgument, /command changed/))
    end

    it 'refuses an invalid request state' do
      expect { described_class.new(web_secret, context_class.new(request_state: '{"a":1}')) }.to(raise_error(Aspera::Cli::BadArgument, /Invalid request state/))
    end
  end

  describe '.value' do
    it 'is available only during a tool call' do
      expect { described_class.value('pw') }.to(raise_error(Aspera::Cli::BadArgument, /only in MCP tool calls/))
    end

    it 'uses the secrets of the tool call in progress, with default prompt' do
      call = described_class::Call.new(web_secret, nil)
      prompt = catch(described_class::THROW_TAG) { described_class.with_call(call) { described_class.value('') } }
      expect(prompt).to(eq('secret'))
    end
  end
end
