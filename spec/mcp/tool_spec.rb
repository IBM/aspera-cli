# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

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

require_relative '../../lib/aspera/cli/mcp/tool'
require_relative '../../lib/aspera/cli/result'
require 'securerandom'
require 'tmpdir'
require 'uri'

RSpec.describe(Aspera::Cli::Mcp::Tool) do
  # Minimal formatter stub that only implements filter_columns_on_select and query_result.
  let(:formatter_stub) do
    f = Object.new
    # no selection by default; individual examples may re-define this
    f.define_singleton_method(:filter_columns_on_select) { |data| data }
    # no query by default
    f.define_singleton_method(:query_result) { |result| result }
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
  # Main folder of the server
  # -----------------------------------------------------------------------
  describe 'main folder of the server' do
    after do
      described_class.main_folder = nil
      described_class.config_file = nil
      described_class.vault = nil
      described_class.vault_password = nil
    end

    it 'is given to the runner of each call' do
      described_class.main_folder = '/server/home'
      described_class.config_file = '/server/home/config.yaml'
      described_class.vault = {'default' => 'f'}
      described_class.vault_password = '<PASSWORD>'
      runner = instance_double(Aspera::Cli::Runner, run_with_result: Aspera::Cli::Result::Nothing.new, context: context_stub)
      allow(Aspera::Cli::Runner).to(receive(:new).and_return(runner))
      described_class.call(args: %w[config gem version])
      expect(Aspera::Cli::Runner).to(have_received(:new).with(array_including('config', 'gem', 'version'), main_folder: '/server/home', config_file: '/server/home/config.yaml', vault: {'default' => 'f'}, vault_password: '<PASSWORD>'))
    end

    it 'gives the configuration file of the server to the commands, and a value of the client is refused' do
      Dir.mktmpdir do |server_home|
        Dir.mktmpdir do |client_home|
          server_file = File.join(server_home, 'config.yaml')
          client_file = File.join(client_home, 'config.yaml')
          File.write(server_file, {'config' => {'version' => Aspera::Cli::VERSION}, 'p1' => {'key' => 'val'}}.to_yaml)
          Aspera::Cli::Security.instance.reset
          Aspera::Cli::Security.instance.lock('spec', default: :high)
          described_class.main_folder = server_home
          described_class.config_file = server_file
          resp = described_class.call(args: %w[config preset get p1 key])
          expect(resp.error?).to(be(false))
          expect(resp.content.first[:text]).to(eq('val'))
          resp = described_class.call(args: ['config', 'preset', 'get', 'p1', 'key', "--config-file=#{client_file}"])
          expect(resp.error?).to(be(true))
          expect(resp.content.first[:text]).to(include('option config_file: disabled by security level high'))
          expect(File.exist?(client_file)).to(be(false))
          # The configuration of the server is read-only for the client
          resp = described_class.call(args: %w[config preset set p1 key other])
          expect(resp.error?).to(be(true))
          expect(resp.content.first[:text]).to(include('command preset set: disabled by security level high'))
          expect(Aspera::Yaml.safe_load(File.read(server_file))['p1']).to(eq({'key' => 'val'}))
        ensure
          Aspera::Cli::Security.instance.reset
        end
      end
    end

    it 'resolves @vault: with the vault of the server, and a vault of the client is refused' do
      Dir.mktmpdir do |server_home|
        Dir.mktmpdir do |client_home|
          pw = SecureRandom.hex(8)
          vault = {'default' => 'f', 'stores' => {'f' => {'type' => 'file', 'file' => File.join(server_home, 'v.vault')}}}
          client_vault = {'default' => 'f', 'stores' => {'f' => {'type' => 'file', 'file' => File.join(client_home, 'v.vault')}}}
          # The server creates its vault, at level low
          Aspera::Cli::Security.instance.reset
          described_class.main_folder = server_home
          described_class.vault = vault
          described_class.vault_password = pw
          resp = described_class.call(args: ['config', 'vault', 'create', '@json:{"label":"lbl","password":"<SECRET>"}'])
          expect(resp.error?).to(be(false))
          Aspera::Cli::Security.instance.lock('spec', default: :high)
          resp = described_class.call(args: %w[config vault show lbl])
          expect(resp.error?).to(be(false))
          expect(resp.content.first[:text]).to(include('"label":"lbl"'))
          resp = described_class.call(args: ['config', 'vault', 'create', '@json:{"label":"x","password":"<SECRET>"}', "--vault=@json:#{client_vault.to_json}", "--vault-password=#{pw}"])
          expect(resp.error?).to(be(true))
          expect(resp.content.first[:text]).to(include('option vault: disabled by security level high'))
          resp = described_class.call(args: %w[config vault show lbl --vault-password=<PASSWORD>])
          expect(resp.error?).to(be(true))
          expect(resp.content.first[:text]).to(include('option vault_password', 'disabled by security level high'))
          expect(Dir.children(client_home)).to(be_empty)
        ensure
          Aspera::Cli::Security.instance.reset
        end
      end
    end

    it 'keeps the vault of the server when the client gives a vault in a preset (option preset)' do
      Dir.mktmpdir do |server_home|
        Dir.mktmpdir do |client_home|
          pw = SecureRandom.hex(8)
          client_file = File.join(client_home, 'x.vault')
          # Store of the server without file: vault.bin in its main folder
          described_class.main_folder = server_home
          described_class.vault = {'default' => 'f', 'stores' => {'f' => {'type' => 'file'}}}
          described_class.vault_password = pw
          # The server creates its vault, at level low
          Aspera::Cli::Security.instance.reset
          resp = described_class.call(args: ['config', 'vault', 'create', '@json:{"label":"a","password":"<SECRET>"}'])
          expect(resp.error?).to(be(false))
          expect(File.exist?(File.join(server_home, 'vault.bin'))).to(be(true))
          Aspera::Cli::Security.instance.lock('spec', default: :high)
          client_vault = {'stores' => {'f' => {'file' => client_file, 'password' => SecureRandom.hex(8)}}}
          resp = described_class.call(args: ['config', 'vault', 'show', 'a', '-P', "@json:#{{'vault' => client_vault}.to_json}"])
          expect(resp.error?).to(be(false))
          expect(resp.content.first[:text]).to(include('"label":"a"'))
          expect(File.exist?(client_file)).to(be(false))
        ensure
          Aspera::Cli::Security.instance.reset
        end
      end
    end

    it 'uses the vault of the server given by a preset of its configuration file' do
      Dir.mktmpdir do |server_home|
        pw = SecureRandom.hex(8)
        vault = {'default' => 'f', 'stores' => {'f' => {'type' => 'file'}}}
        config_file = File.join(server_home, 'config.yaml')
        # The server owner writes the preset at level low, and sets it as global default
        Aspera::Cli::Security.instance.reset
        described_class.main_folder = server_home
        described_class.config_file = config_file
        expect(described_class.call(args: ['config', 'preset', 'update', 'cfg', "--vault=@json:#{vault.to_json}", "--vault-password=#{pw}"]).error?).to(be(false))
        expect(described_class.call(args: %w[config preset set default config cfg]).error?).to(be(false))
        expect(described_class.call(args: ['config', 'vault', 'create', '@json:{"label":"lbl","password":"<SECRET>"}']).error?).to(be(false))
        # The server read its vault from the preset at startup (level low), and gives it to the calls: the preset is read again by each call at level high
        described_class.vault = vault
        described_class.vault_password = pw
        Aspera::Cli::Security.instance.lock('spec', default: :high)
        resp = described_class.call(args: %w[config vault show lbl])
        expect(resp.error?).to(be(false))
        expect(resp.content.first[:text]).to(include('"label":"lbl"'))
      ensure
        Aspera::Cli::Security.instance.reset
      end
    end

    it 'is the home of the command, at security level high, and a value of the client is refused' do
      Dir.mktmpdir do |server_home|
        Dir.mktmpdir do |client_home|
          Aspera::Cli::Security.instance.reset
          Aspera::Cli::Security.instance.lock('spec', default: :high)
          described_class.main_folder = server_home
          resp = described_class.call(args: %w[config folder])
          expect(resp.error?).to(be(false))
          expect(resp.content.first[:text]).to(include(File.realpath(server_home)).or(include(server_home)))
          resp = described_class.call(args: ['config', 'folder', "--home=#{client_home}"])
          expect(resp.error?).to(be(true))
          expect(resp.content.first[:text]).to(include('option home: disabled by security level high'))
        ensure
          Aspera::Cli::Security.instance.reset
        end
      end
    end
  end

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

  describe 'Result::Poll' do
    it 'refuses option poll: the command would display its results' do
      resp = call_with_result(Aspera::Cli::Result::Poll.new({'max' => 2}))
      expect(resp.error?).to(be(true))
      expect(resp.content.first[:text]).to(include('Option poll: not available in MCP server mode'))
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

    it 'hides a declared secret used as key name, in both text and structuredContent' do
      secret = SecureRandom.alphanumeric(12)
      Aspera::Secret::Hider.instance.add_secret_values(secret)
      resp = call_with_result(Aspera::Cli::Result::SingleObject.new({secret => 'value'}))
      expect(resp.content.first[:text]).not_to(include(secret))
      expect(resp.structured_content.keys.join).not_to(include(secret))
      expect(resp.structured_content.values).to(eq(['value']))
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
        arr.select { |i| i['keep'] }
      end
      f.define_singleton_method(:query_result) { |result| result }
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
  # --out.query (JMESPath) applied as on the command line
  # -----------------------------------------------------------------------
  describe '--out.query' do
    # Formatter with query `{s: status}`
    let(:formatter_stub) do
      f = Object.new
      f.define_singleton_method(:filter_columns_on_select) { |data| data }
      f.define_singleton_method(:query_result) { |result| Aspera::Cli::Result::SingleObject.new({'s' => result.data['status']}) }
      f
    end

    it 'returns the value of the query in text and structuredContent' do
      resp = call_with_result(Aspera::Cli::Result::SingleObject.new({'id' => '3910', 'status' => 'completed'}))
      expect(resp.structured_content).to(eq({'s' => 'completed'}))
      expect(JSON.parse(resp.content.first[:text])).to(eq({'s' => 'completed'}))
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

    it 'hides a declared secret value, even without key name' do
      Aspera::Environment.unicode = true
      secret = SecureRandom.alphanumeric(12)
      Aspera::Secret::Hider.instance.add_secret_values(secret)
      resp = call_with_result(Aspera::Cli::Result::Text.new("Bearer #{secret}"))
      expect(resp.content).to(eq([{type: 'text', text: 'Bearer 🔑'}]))
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

    it 'hides a declared short secret in the message' do
      short = SecureRandom.alphanumeric(6)
      Aspera::Secret::Hider.instance.add_secret_values(short)
      allow(Aspera::Cli::Runner).to(receive(:new).and_raise(RuntimeError, "no such preset: #{short}"))
      resp = described_class.call(args: ['bad'])
      expect(resp.content.first[:text]).to(start_with('RuntimeError: no such preset: '))
      expect(resp.content.first[:text]).not_to(include(short))
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
