# frozen_string_literal: true

# Stub MCP::Tool and MCP::Tool::Response before loading mcp_tool.rb so that
# the file can be required even when the optional 'mcp' gem is not installed.
unless defined?(MCP::Tool)
  module MCP
    class Tool
      # DSL class methods used at class-body evaluation time in McpTool
      class << self
        def tool_name(_name); end
        def description(_text); end
        def input_schema(**_kwargs); end
      end

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
end

require 'aspera/cli/mcp_tool'
require 'aspera/cli/result'

RSpec.describe(Aspera::Cli::McpTool) do
  # Minimal formatter stub that only implements filter_columns_on_select.
  # When select_filter is nil the method is a no-op, otherwise it applies the Hash filter.
  let(:formatter_stub) do
    f = Object.new
    f.define_singleton_method(:filter_columns_on_select) do |data|
      # no-op by default; individual examples may re-define this
    end
    f
  end

  let(:context_stub){instance_double(Aspera::Cli::Context, formatter: formatter_stub)}

  # Helper: stub Runner so McpTool.call never spawns a real CLI execution.
  # @param result [Aspera::Cli::Result] the result to return from run_with_result
  def call_with_result(result)
    runner = instance_double(Aspera::Cli::Runner, run_with_result: result, context: context_stub)
    allow(Aspera::Cli::Runner).to(receive(:new).and_return(runner))
    described_class.call(args: %w[config gem version])
  end

  before{described_class.max_text_bytes = nil} # reset between examples

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
    let(:data){[{'n' => 1}, {'n' => 2}, {'n' => 3}, {'n' => 4}]}
    before{described_class.max_text_bytes = 20}

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
    let(:data){[{'n' => 1, 'keep' => true}, {'n' => 2, 'keep' => false}, {'n' => 3, 'keep' => true}]}

    # Override formatter_stub to apply a keep=true filter for this describe block.
    let(:formatter_stub) do
      f = Object.new
      f.define_singleton_method(:filter_columns_on_select) do |arr|
        arr.select!{ |i| i['keep'] }
      end
      f
    end

    it 'only matching items appear in text content' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      parsed = JSON.parse(resp.content.first[:text])
      expect(parsed.all?{ |i| i['keep'] }).to(be(true))
      expect(parsed.size).to(eq(2))
    end

    it 'structuredContent also contains only the filtered items' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.structured_content[:items].size).to(eq(2))
      expect(resp.structured_content[:items].all?{|i| i['keep']}).to(be(true))
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
end
