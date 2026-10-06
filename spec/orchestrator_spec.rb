# frozen_string_literal: true

require_relative 'spec_helper'
require 'aspera/cli/plugins/orchestrator'
require 'aspera/cli/parser'
require 'aspera/cli/context'

RSpec.describe(Aspera::Cli::Plugins::Orchestrator) do
  let(:parser) { Aspera::Cli::Parser.new('orchestrator') }
  let(:context) do
    ctx = Aspera::Cli::Context.new
    ctx.man_header = false
    ctx.options = parser
    ctx
  end
  let(:orchestrator) { described_class.new(context: context) }

  before do
    described_class.declare_options(parser, target: orchestrator)
  end

  describe '#api_orch' do
    def parse_argv(argv)
      p = Aspera::Cli::Parser.new('orchestrator', argv)
      described_class.declare_options(p, target: orchestrator)
      p.parse_options!
      context.options = p
    end

    it 'configures Rest::Client for token auth (JWT credentials) with username and password by default' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret])
      client = orchestrator.api_orch
      expect(client.base_url).to(eq('https://orch.example.com'))
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(username: 'admin', password: 'secret'))
    end

    it 'configures Rest::Client for basic auth with username and password' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret --auth_style=basic])
      client = orchestrator.api_orch
      expect(client.base_url).to(eq('https://orch.example.com'))
      expect(client.auth_params).to(eq(type: :basic, username: 'admin', password: 'secret'))
    end

    it 'configures Rest::Client for query auth with username and password' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret --auth_style=query])
      client = orchestrator.api_orch
      expect(client.auth_params).to(eq(type: :url, url_query: {'login' => 'admin', 'password' => 'secret'}))
    end

    it 'configures Rest::Client for token auth (JWT credentials) with username and password' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret --auth_style=token])
      client = orchestrator.api_orch
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(username: 'admin', password: 'secret'))
    end

    it 'configures Rest::Client for query auth with apikey' do
      parse_argv(%w[--url=https://orch.example.com --apikey=mykey123 --auth_style=query])
      client = orchestrator.api_orch
      expect(client.auth_params).to(eq(type: :url, url_query: {'apikey' => 'mykey123'}))
    end

    it 'configures Rest::Client for token auth with apikey' do
      parse_argv(%w[--url=https://orch.example.com --apikey=mykey123 --auth_style=token])
      client = orchestrator.api_orch
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(apikey: 'mykey123'))
    end

    it 'does not include passwords or apikey in token cache id' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=my_secret_password --auth_style=token])
      client = orchestrator.api_orch
      token_cache_id = client.oauth.instance_variable_get(:@token_cache_id)
      expect(token_cache_id).not_to(include('my_secret_password'))
      expect(token_cache_id).to(include('admin'))

      orchestrator.instance_variable_set(:@api_orch, nil)
      parse_argv(%w[--url=https://orch.example.com --apikey=my_super_secret_key --auth_style=token])
      client2 = orchestrator.api_orch
      token_cache_id2 = client2.oauth.instance_variable_get(:@token_cache_id)
      expect(token_cache_id2).not_to(include('my_super_secret_key'))
    end

    it 'raises error when using basic auth_style with apikey' do
      parse_argv(%w[--url=https://orch.example.com --apikey=mykey123 --auth_style=basic])
      expect { orchestrator.api_orch }.to(raise_error(Aspera::Cli::BadArgument, /basic auth style cannot be used with apikey/))
    end
  end

  describe '#call_ao' do
    it 'parses an XML response with the given XmlSimple options' do
      xml = '<?xml version="1.0"?><work_order_output>' \
        '<variable id="1"><value_type>string</value_type><value>x</value></variable>' \
        '<variable id="2"><value_type>string</value_type><value></value></variable>' \
        '</work_order_output>'
      api = instance_double(Aspera::Rest::Client, call: [nil, instance_double(Net::HTTPResponse, body: xml)])
      allow(orchestrator).to(receive(:api_orch).and_return(api))
      result = orchestrator.send(:call_ao, 'work_order_output/1', accept: Aspera::Mime::XML, xml_opts: {'ForceArray' => %w[variable], 'SuppressEmpty' => nil})
      expect(result['variable']).to(eq([
        {'id' => '1', 'value_type' => 'string', 'value' => 'x'},
        {'id' => '2', 'value_type' => 'string', 'value' => nil}
      ]))
    end
  end

  describe '#action_workflows_import' do
    it 'uploads the file as a multipart form' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        allow(orchestrator).to(receive(:call_ao).and_return({'workflow' => {'id' => 1}}))
        result = orchestrator.action_workflows_import(file_path: path)
        expect(orchestrator).to(have_received(:call_ao).with(
          'import_workflow',
          body:         [['import_file', "---\n", {filename: 'wf.yml'}], ['import_file_name', 'wf.yml']],
          content_type: Aspera::Mime::MULTIPART
        ))
        expect(result.data).to(eq({'id' => 1}))
      end
    end

    it 'raises an error when plugins cannot be enabled' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        allow(orchestrator).to(receive(:call_ao).and_return({'plugins' => ['Missing'], 'missing_deps' => ['gem_x']}))
        expect { orchestrator.action_workflows_import(file_path: path) }
          .to(raise_error(Aspera::Cli::Error, 'Plugins could not be enabled: Missing (missing dependencies: gem_x)'))
      end
    end

    it 'raises an error when dependencies are not packed' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        dependencies = {'SubWorkflow__1' => [{'entity' => 'Workflow', 'id_key' => 'id', 'id_value' => 12}]}
        allow(orchestrator).to(receive(:call_ao).and_return({'dependencies' => dependencies, 'file' => path, 'workflow' => {}}))
        expect { orchestrator.action_workflows_import(file_path: path) }
          .to(raise_error(Aspera::Cli::Error, /not included in the file.*: Workflow 12$/))
      end
    end
  end

  describe '#action_workflows_import_with_constraints' do
    it 'sends the ordered array expected by the API' do
      allow(orchestrator).to(receive(:call_ao).and_return({'workflow' => {'id' => 239}}))
      result = orchestrator.action_workflows_import_with_constraints(payload: {'filename' => '/tmp/wf.yml', 'add_as_revision' => 239})
      expect(orchestrator).to(have_received(:call_ao).with('import_with_constraints', body: [
        {'filename' => '/tmp/wf.yml'},
        {'add as revision' => 239},
        {'subwf constraints' => {}},
        {'action template constraints' => {}},
        {'remote node constraints' => {}},
        {'Auto-enable missing plugins?' => nil}
      ]))
      expect(result.data).to(eq({'id' => 239}))
    end
  end

  describe '#action_workflows_start' do
    {
      'work order information'   => [{'work_order' => {'id' => 1}}, Aspera::Cli::Result::SingleObject],
      'explicit output (string)' => ['HELLO', Aspera::Cli::Result::Text],
      'explicit output (flag)'   => [true, Aspera::Cli::Result::Text]
    }.each do |label, (response, result_class)|
      it "returns #{label}" do
        allow(orchestrator).to(receive(:call_ao).and_return(response))
        result = orchestrator.action_workflows_start(workflow_id: '1', parameters: {}, execution: {'synchronous' => true})
        expect(result).to(be_a(result_class))
        expect(result.data).to(eq(response))
      end
    end
  end
end
