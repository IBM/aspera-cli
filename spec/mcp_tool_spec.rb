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
  # Helper: stub Runner so McpTool.call never spawns a real CLI execution.
  def call_with_result(result)
    runner = instance_double(Aspera::Cli::Runner, run_with_result: result)
    allow(Aspera::Cli::Runner).to(receive(:new).and_return(runner))
    described_class.call(args: %w[config gem version])
  end

  before{described_class.max_items = nil} # reset between examples

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
      described_class.max_items = 10
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.content.size).to(eq(1))
      expect(JSON.parse(resp.content.first[:text])).to(eq(data))
      expect(resp.structured_content).to(eq({items: data}))
    end
  end

  # -----------------------------------------------------------------------
  # Result::ObjectList — truncation
  # -----------------------------------------------------------------------
  describe 'Result::ObjectList above limit' do
    before{described_class.max_items = 2}

    let(:data){[{'n' => 1}, {'n' => 2}, {'n' => 3}, {'n' => 4}]}

    it 'returns two content blocks' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.content.size).to(eq(2))
    end

    it 'first block contains only the first max_items items' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(JSON.parse(resp.content.first[:text])).to(eq(data.first(2)))
    end

    it 'second block is a WARNING mentioning the counts' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      warning = resp.content.last[:text]
      expect(warning).to(match(/WARNING/))
      expect(warning).to(include('2 of 4'))
    end

    it 'structuredContent contains all items' do
      resp = call_with_result(Aspera::Cli::Result::ObjectList.new(data))
      expect(resp.structured_content[:items].size).to(eq(4))
    end
  end

  # -----------------------------------------------------------------------
  # Result::ValueList — treated as array (same truncation logic)
  # -----------------------------------------------------------------------
  describe 'Result::ValueList truncation' do
    it 'also emits a WARNING when truncated' do
      data = %w[a b c d e]
      described_class.max_items = 2
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
