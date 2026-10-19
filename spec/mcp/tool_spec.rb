# frozen_string_literal: true

# Stub MCP::Tool and MCP::Tool::Response before loading mcp/tool.rb so that
# the file can be required even when the optional 'mcp' gem is not installed.
module MCP
  class Tool
    # DSL class methods used at class-body evaluation time in Mcp::Tool
    class << self
      def tool_name(_name); end unless method_defined?(:tool_name) || respond_to?(:tool_name)
      def description(_text); end unless method_defined?(:description) || respond_to?(:description)
      def input_schema(**_kwargs); end unless method_defined?(:input_schema) || respond_to?(:input_schema)
    end

    unless defined?(MCP::Tool::Response)
      class Response
        attr_reader :content, :structured_content

        def initialize(content, structured_content: nil, error: false)
          @content            = content
          @structured_content = structured_content
          @error              = error
        end

        def error?
          @error
        end
      end
    end
  end

  class Server
    unless defined?(MCP::Server::InputRequiredResult)
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

require 'aspera/cli/mcp/tool'
require 'aspera/cli/result'
require 'securerandom'
require 'uri'

RSpec.describe(Aspera::Cli::Mcp::Tool) do
  # Minimal formatter stub that only implements filter_columns_on_select.
  # When select_filter is nil the method is a no-op, otherwise it applies the Hash filter.
  let(:formatter_stub) do
    f = Object.new
    f.define_singleton_method(:filter_columns_on_select) do |data|
      # no-op by default; individual examples may re-define this
    end
    f
  end

  let(:context_stub) { instance_double(Aspera::Cli::Context, formatter: formatter_stub) }

  # Helper: stub Runner so Mcp::Tool.call never spawns a real CLI execution.
  # @param result [Aspera::Cli::Result] the result to return from run_with_result
  def call_with_result(result)
    runner = instance_double(Aspera::Cli::Runner, run_with_result: result, context: context_stub)
    allow(Aspera::Cli::Runner).to(receive(:new).and_return(runner))
    described_class.call(args: %w[config gem version])
  end

  before { described_class.max_text_bytes = nil } # reset between examples

  # -----------------------------------------------------------------------
  # Result::Nothing / Result::Empty  →  empty text content, no structured
  # -----------------------------------------------------------------------
  describe 'Result::Nothing' do
    it 'returns a single empty text content block' do
      resp = call_with_result(Aspera::Cli::Result::Nothing.new)
      expect(resp.content).to(eq([{type: 'text', text: ''}]))
      expect(resp.structured_content).to(be_nil)
    end
  end

  describe 'Result::Empty' do
    it 'returns a single empty text content block' do
      resp = call_with_result(Aspera::Cli::Result::Empty.new)
      expect(resp.content).to(eq([{type: 'text', text: ''}]))
    end
  end

  # -----------------------------------------------------------------------
  # Result::SingleObject  →  JSON object, also in structuredContent
  # -----------------------------------------------------------------------
  describe 'Result::SingleObject' do
    it 'returns JSON text and the object as structuredContent' do
      data = {'key' => 'value'}
      resp = call_with_result(Aspera::Cli::Result::SingleObject.new(data))
      expect(resp.content.size).to(eq(1))
      expect(JSON.parse(resp.content.first[:text])).to(eq(data))
      expect(resp.structured_content).to(eq(data))
    end

    it 'hides secrets in both text and structuredContent' do
      secret = SecureRandom.alphanumeric(12)
      data = {'username' => 'john', 'password' => secret} # HashiCorpIgnore
      resp = call_with_result(Aspera::Cli::Result::SingleObject.new(data))
      expect(resp.content.first[:text]).not_to(include(secret))
      expect(resp.structured_content['password']).not_to(eq(secret))
      expect(resp.structured_content['username']).to(eq('john'))
    end
  end

  # -----------------------------------------------------------------------
  # Result::ObjectList — short list (no truncation)
  # -----------------------------------------------------------------------
  describe 'Result::ObjectList below limit' do
    it 'returns one content block with all items, wrapped in structuredContent' do
      data = [{'a' => 1}, {'a' => 2}]
      described_class.max_text_bytes = 10_000
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.content.size).to(eq(1))
      expect(JSON.parse(resp.content.first[:text])).to(eq(data))
      expect(resp.structured_content).to(eq({items: data}))
    end
  end

  # -----------------------------------------------------------------------
  # Result::ObjectList — truncation by byte size
  # -----------------------------------------------------------------------
  describe 'Result::ObjectList above byte limit' do
    # Each item serializes to ~10 bytes: {"n":1} = 7 bytes + separator.
    # Setting max_text_bytes to 20 fits at most 2 items.
    let(:data) { [{'n' => 1}, {'n' => 2}, {'n' => 3}, {'n' => 4}] }
    before { described_class.max_text_bytes = 20 }

    it 'returns two content blocks' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.content.size).to(eq(2))
    end

    it 'first block contains only the items that fit within the byte limit' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      parsed = JSON.parse(resp.content.first[:text])
      expect(parsed.size).to(be < data.size)
      expect(JSON.generate(parsed).bytesize).to(be <= 20)
    end

    it 'second block is a WARNING mentioning the counts' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      warning = resp.content.last[:text]
      expect(warning).to(match(/WARNING/))
      expect(warning).to(include('of 4'))
    end

    it 'structuredContent contains all items' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.structured_content[:items].size).to(eq(4))
    end
  end

  # -----------------------------------------------------------------------
  # --select filter applied before truncation
  # -----------------------------------------------------------------------
  describe '--select filter applied before byte truncation' do
    let(:data) { [{'n' => 1, 'keep' => true}, {'n' => 2, 'keep' => false}, {'n' => 3, 'keep' => true}] }

    # Override formatter_stub to apply a keep=true filter for this describe block.
    let(:formatter_stub) do
      f = Object.new
      f.define_singleton_method(:filter_columns_on_select) do |arr|
        arr.select! { |i| i['keep'] }
      end
      f
    end

    it 'only matching items appear in text content' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      parsed = JSON.parse(resp.content.first[:text])
      expect(parsed.all? { |i| i['keep'] }).to(be(true))
      expect(parsed.size).to(eq(2))
    end

    it 'structuredContent also contains only the filtered items' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.structured_content[:items].size).to(eq(2))
      expect(resp.structured_content[:items].all? { |i| i['keep'] }).to(be(true))
    end
  end

  # -----------------------------------------------------------------------
  # Result::ValueList — treated as array (same truncation logic)
  # -----------------------------------------------------------------------
  describe 'Result::ValueList truncation' do
    it 'also emits a WARNING when truncated' do
      data = %w[a b c d e]
      described_class.max_text_bytes = 10 # too small for all 5 items
      resp = call_with_result(Aspera::Cli::Result::ValueList.new(data, name: 'item'))
      expect(resp.content.size).to(eq(2))
      expect(resp.content.last[:text]).to(match(/WARNING/))
    end
  end

  # -----------------------------------------------------------------------
  # Result::Text  →  plain text passthrough (else branch)
  # -----------------------------------------------------------------------
  describe 'Result::Text' do
    it 'returns the raw text without structuredContent' do
      resp = call_with_result(Aspera::Cli::Result::Text.new('hello'))
      expect(resp.content).to(eq([{type: 'text', text: 'hello'}]))
      expect(resp.structured_content).to(be_nil)
    end
  end

  # -----------------------------------------------------------------------
  # Error handling — StandardError
  # -----------------------------------------------------------------------
  describe 'when Runner raises a StandardError' do
    it 'returns an error response with the message' do
      allow(Aspera::Cli::Runner).to(receive(:new).and_raise(RuntimeError, 'boom'))
      resp = described_class.call(args: ['bad'])
      expect(resp.error?).to(be(true))
      expect(resp.content.first[:text]).to(include('boom'))
    end
  end

  # -----------------------------------------------------------------------
  # Error handling — SystemExit with non-zero status
  # -----------------------------------------------------------------------
  describe 'when Runner raises SystemExit with non-zero status' do
    it 'returns an error response' do
      allow(Aspera::Cli::Runner).to(receive(:new).and_raise(SystemExit.new(1)))
      resp = described_class.call(args: ['bad'])
      expect(resp.error?).to(be(true))
      expect(resp.content.first[:text]).to(include('1'))
    end
  end

  # -----------------------------------------------------------------------
  # Error handling — SystemExit with status 0
  # -----------------------------------------------------------------------
  describe 'when Runner raises SystemExit with status 0' do
    it 'returns a non-error response' do
      allow(Aspera::Cli::Runner).to(receive(:new).and_raise(SystemExit.new(0)))
      resp = described_class.call(args: ['help'])
      expect(resp.error?).to(be(false))
    end
  end

  # -----------------------------------------------------------------------
  # @secret: entered by the user on a web page (URL mode elicitation)
  # -----------------------------------------------------------------------
  describe '@secret: in arguments' do
    let(:web_secret) { Aspera::Cli::Mcp::Secrets.web_secret(base_url: 'http://localhost:3000') }
    # Minimal stand-in for MCP::ServerContext of a 2026-07-28 client
    let(:context_class) do
      Struct.new(:request_state, :input_responses, :client_capabilities, keyword_init: true) do
        def input_response(key) = input_responses&.[](key)
        def modern? = true
      end
    end
    let(:capabilities) { {elicitation: {url: {}}} }

    before do
      described_class.web_secret = web_secret
      # The command displays the secret
      runner = instance_double(Aspera::Cli::Runner, context: context_stub)
      allow(runner).to(receive(:run_with_result) { Aspera::Cli::Result::Text.new("pw=#{Aspera::Cli::Mcp::Secrets.value('pw')}") })
      allow(Aspera::Cli::Runner).to(receive(:new).and_return(runner))
    end

    after { described_class.web_secret = nil }

    it 'asks the client to open the page, then executes the command with the secret, hidden in result' do
      # Placeholder of hidden secret depends on Unicode support
      Aspera::Environment.unicode = true
      args = %w[config echo @secret:pw]
      first = described_class.call(args: args, server_context: context_class.new(client_capabilities: capabilities))
      expect(first).to(be_a(MCP::Server::InputRequiredResult))
      request_id, request = first.input_requests.first
      expect(request[:params][:url]).to(eq(web_secret.url(request_id)))
      # The user enters the secret on the page
      page_request = Struct.new(:request_method, :path, :body).new('POST', "/secret/#{request_id}", URI.encode_www_form(secret: SecureRandom.alphanumeric(12), decision: 'submit'))
      web_secret.handle(page_request, Struct.new(:status, :body) { def []=(*); end }.new)
      retry_context = context_class.new(client_capabilities: capabilities, request_state: first.request_state, input_responses: {request_id => {action: 'accept'}})
      resp = described_class.call(args: args, server_context: retry_context)
      expect(resp.error?).to(be(false))
      expect(resp.content).to(eq([{type: 'text', text: 'pw=🔑'}]))
      expect(web_secret.prompt(request_id)).to(be_nil)
    ensure
      Aspera::Environment.unicode = nil
    end

    it 'returns an error if the client does not support URL mode elicitation' do
      resp = described_class.call(args: %w[config echo @secret:pw], server_context: context_class.new(client_capabilities: {elicitation: {}}))
      expect(resp.error?).to(be(true))
      expect(resp.content.first[:text]).to(include('requires an MCP client supporting URL mode elicitation'))
    end
  end
end
