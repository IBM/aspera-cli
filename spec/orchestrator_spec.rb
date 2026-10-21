# frozen_string_literal: true

require_relative 'spec_helper'
require 'aspera/cli/plugins/orchestrator'
require 'aspera/cli/parser'
require 'aspera/cli/context'
require 'aspera/cli/transfer_agent'
require 'securerandom'

RSpec.describe(Aspera::Cli::Plugins::Orchestrator) do
  let(:parser) { Aspera::Cli::Parser.new('orchestrator') }
  let(:context) do
    ctx = Aspera::Cli::Context.new
    ctx.man_header = false
    ctx.options = parser
    ctx
  end
  let(:orchestrator) { described_class.new(context: context) }
  # Values of secrets are generated, none in source
  let(:password) { SecureRandom.alphanumeric(12) }
  let(:apikey) { SecureRandom.alphanumeric(12) }

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
      parse_argv(%W[--url=https://orch.example.com --username=admin --password=#{password}])
      client = orchestrator.api_orch
      expect(client.base_url).to(eq('https://orch.example.com'))
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(username: 'admin', password: password))
    end

    it 'configures Rest::Client for basic auth with username and password' do
      parse_argv(%W[--url=https://orch.example.com --username=admin --password=#{password} --auth_style=basic])
      client = orchestrator.api_orch
      expect(client.base_url).to(eq('https://orch.example.com'))
      expect(client.auth_params).to(eq(type: :basic, username: 'admin', password: password))
    end

    it 'configures Rest::Client for query auth with username and password' do
      parse_argv(%W[--url=https://orch.example.com --username=admin --password=#{password} --auth_style=query])
      client = orchestrator.api_orch
      expect(client.auth_params).to(eq(type: :url, url_query: {'login' => 'admin', 'password' => password}))
    end

    it 'configures Rest::Client for token auth (JWT credentials) with username and password' do
      parse_argv(%W[--url=https://orch.example.com --username=admin --password=#{password} --auth_style=token])
      client = orchestrator.api_orch
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(username: 'admin', password: password))
    end

    it 'configures Rest::Client for query auth with apikey' do
      parse_argv(%W[--url=https://orch.example.com --apikey=#{apikey} --auth_style=query])
      client = orchestrator.api_orch
      expect(client.auth_params).to(eq(type: :url, url_query: {'apikey' => apikey}))
    end

    it 'configures Rest::Client for token auth with apikey' do
      parse_argv(%W[--url=https://orch.example.com --apikey=#{apikey} --auth_style=token])
      client = orchestrator.api_orch
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(apikey: apikey))
    end

    it 'does not include passwords or apikey in token cache id' do
      parse_argv(%W[--url=https://orch.example.com --username=admin --password=#{password} --auth_style=token])
      client = orchestrator.api_orch
      token_cache_id = client.oauth.instance_variable_get(:@token_cache_id)
      expect(token_cache_id).not_to(include(password))
      expect(token_cache_id).to(include('admin'))

      orchestrator.instance_variable_set(:@api_orch, nil)
      parse_argv(%W[--url=https://orch.example.com --apikey=#{apikey} --auth_style=token])
      client2 = orchestrator.api_orch
      token_cache_id2 = client2.oauth.instance_variable_get(:@token_cache_id)
      expect(token_cache_id2).not_to(include(apikey))
    end

    it 'raises error when using basic auth_style with apikey' do
      parse_argv(%W[--url=https://orch.example.com --apikey=#{apikey} --auth_style=basic])
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
    # plugin specifications are read from GitHub: not in unit tests
    before do
      allow(orchestrator).to(receive(:plugin_specs).and_return({}))
    end

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

  describe '#action_workflows_export' do
    it 'displays the workflow file without dependencies' do
      allow(orchestrator).to(receive(:call_ao).and_return(instance_double(Net::HTTPResponse, body: "---\n")))
      result = orchestrator.action_workflows_export(workflow_id: '1', export: {})
      expect(orchestrator).to(have_received(:call_ao).with('export_workflow/1', accept: nil, query: nil, http: true))
      expect(result).to(be_a(Aspera::Cli::Result::Text))
      expect(result.data).to(eq("---\n"))
    end

    it 'saves the package with dependencies in the destination folder' do
      Dir.mktmpdir do |dir|
        resp = instance_double(Net::HTTPResponse, body: 'binary')
        allow(resp).to(receive(:[]).with('Content-Disposition').and_return('attachment; filename="Workflow_wf_v9.wkf"'))
        allow(orchestrator).to(receive_messages(call_ao: resp, transfer: instance_double(Aspera::Cli::TransferAgent, destination_folder: dir)))
        result = orchestrator.action_workflows_export(workflow_id: '1', export: {'dependencies' => true})
        expect(orchestrator).to(have_received(:call_ao).with('export_workflow/1', accept: nil, query: {export_with_dependencies: true}, http: true))
        expect(File.binread(File.join(dir, 'Workflow_wf_v9.wkf'))).to(eq('binary'))
        expect(result.data).to(eq("Saved to: #{File.join(dir, 'Workflow_wf_v9.wkf')}"))
      end
    end
  end

  # Response of find_constraints: array of single-key objects
  def constraints_response(subwf: {}, templates: {}, nodes: {}, plugins: nil)
    [
      {'filename' => '/tmp/wf.yml'},
      {'add as revision' => nil},
      {'subwf constraints' => subwf},
      {'action template constraints' => templates},
      {'remote node constraints' => nodes},
      {'missing plugins' => plugins, 'Auto-enable missing plugins?' => plugins && [true, false]}
    ]
  end

  def stub_server(constraints, imported = {'workflow' => {'id' => 239}})
    allow(orchestrator).to(receive(:call_ao)) do |endpoint, **|
      endpoint.eql?('find_constraints') ? constraints : imported
    end
  end

  describe '#action_workflows_import_with_constraints' do
    it 'sends the ordered array expected by the API' do
      stub_server(constraints_response)
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

    it 'refuses to import when plugins are not enabled and not auto-enabled' do
      stub_server(constraints_response(plugins: ['Missing']))
      expect { orchestrator.action_workflows_import_with_constraints(payload: {'filename' => '/tmp/wf.yml'}) }
        .to(raise_error(Aspera::Cli::BadArgument, /plugins are not enabled: Missing/))
      expect(orchestrator).not_to(have_received(:call_ao).with('import_with_constraints', anything))
    end

    it 'imports when missing plugins are auto-enabled' do
      stub_server(constraints_response(plugins: ['Missing']))
      orchestrator.action_workflows_import_with_constraints(payload: {'filename' => '/tmp/wf.yml', 'auto_enable_missing_plugins' => true})
      expect(orchestrator).to(have_received(:call_ao).with('import_with_constraints', anything))
    end

    it 'refuses to import when some conflicts are not resolved' do
      stub_server(constraints_response(templates: {'Search Files' => ['Map'], 'Log' => ['Map']}))
      payload = {'filename' => '/tmp/wf.yml', 'action_template_constraints' => {'Search Files' => 'Map to the existing Global Template'}}
      expect { orchestrator.action_workflows_import_with_constraints(payload: payload) }
        .to(raise_error(Aspera::Cli::BadArgument, /action_template_constraints not resolved for: Log/))
    end

    it 'passes the file and the target workflow to find_constraints' do
      stub_server(constraints_response)
      orchestrator.action_workflows_import_with_constraints(payload: {'filename' => '/tmp/wf.yml', 'add_as_revision' => 239})
      expect(orchestrator).to(have_received(:call_ao).with('find_constraints', query: {file: '/tmp/wf.yml', wf_id: 239}))
    end
  end

  describe '#action_workflows_find_constraints' do
    it 'lists one row per conflict and per missing plugin' do
      stub_server(constraints_response(subwf: {'Sub' => ['Map']}, nodes: {'Baton' => ['Map']}, plugins: ['Missing']))
      result = orchestrator.action_workflows_find_constraints(filename: '/tmp/wf.yml')
      expect(result.data.map { |row| row.values_at('type', 'name') }).to(eq([
        %w[subwf_constraints Sub], %w[remote_node_constraints Baton], %w[missing_plugins Missing]
      ]))
    end

    it 'reports that nothing was found' do
      stub_server(constraints_response)
      result = orchestrator.action_workflows_find_constraints(filename: '/tmp/wf.yml')
      expect(result).to(be_a(Aspera::Cli::Result::Status))
      expect(result.data).to(match(/no conflict found/))
    end

    it 'fails on an unexpected response' do
      stub_server({'error' => 'x'})
      expect { orchestrator.action_workflows_find_constraints(filename: '/tmp/wf.yml') }.to(raise_error(Aspera::Cli::Error, /find_constraints/))
    end
  end

  describe '#action_workflows_check_import' do
    let(:specs) { {'CustomRuby' => {'attributes' => {}, 'inputs' => {}, 'outputs' => {}}} }

    # plugin specifications are read from GitHub: not in unit tests
    before do
      allow(orchestrator).to(receive(:plugin_specs).and_return(specs))
    end

    it 'checks templates and inputs with the plugin specifications' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        allow(Aspera::OrchestratorWorkflowChecker).to(receive(:check).and_call_original)
        orchestrator.action_workflows_check_import(file_path: path)
        expect(Aspera::OrchestratorWorkflowChecker).to(have_received(:check).with(hash_including(file_name: 'wf.yml', specs: specs)))
      end
    end

    it 'warns when the plugin specifications cannot be read' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        allow(orchestrator).to(receive(:plugin_specs).and_raise(StandardError, 'offline'))
        result = orchestrator.action_workflows_check_import(file_path: path)
        expect(result.data.last).to(include('severity' => 'warning', 'code' => 'plugins.specs_unavailable'))
        expect(result.data.last['message']).to(include('offline'))
      end
    end

    it 'reports a valid file and an invalid file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        result = orchestrator.action_workflows_check_import(file_path: path)
        expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
        expect(result.data.first.keys).to(include('severity', 'code', 'message'))
      end
    end

    it 'does not call Orchestrator' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        allow(orchestrator).to(receive(:call_ao))
        orchestrator.action_workflows_check_import(file_path: path)
        expect(orchestrator).not_to(have_received(:call_ao))
      end
    end
  end

  describe '#action_workflows_development' do
    let(:content) { "# Guide\n\nIntro\n\n## Recipes\n\nRecipe text\n\n## Known issues\n\nNone\n" }

    before do
      allow(Aspera::UriReader).to(receive(:read).and_return(content))
    end

    it 'reads the raw document of GitHub' do
      orchestrator.action_workflows_development(document: :templates)
      expect(Aspera::UriReader).to(have_received(:read).with(%r{^https://raw\.githubusercontent\.com/.+/action-template-reference\.md$}))
    end

    it 'displays the whole document without section' do
      result = orchestrator.action_workflows_development(document: :authoring)
      expect(result).to(be_a(Aspera::Cli::Result::Text))
      expect(result.data).to(eq(content))
    end

    it 'lists the table of contents' do
      result = orchestrator.action_workflows_development(document: :authoring, section: 'toc')
      expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
      expect(result.data.map { |e| e[:anchor] }).to(eq(%w[guide recipes known-issues]))
    end

    it 'displays one section' do
      result = orchestrator.action_workflows_development(document: :authoring, section: 'recipes')
      expect(result.data).to(eq("## Recipes\n\nRecipe text\n\n"))
    end

    it 'fails on an unknown section' do
      expect { orchestrator.action_workflows_development(document: :authoring, section: 'nope') }
        .to(raise_error(Aspera::Cli::Error, /Section not found: nope/))
    end
  end

  describe '#action_plugins_spec' do
    let(:content) do
      <<~YAML
        # header
        ---
        AscpClient:
          display_name: Ascp client
          category: File Transfer
          version: 1.6.2
          attributes:
            operation: {type: string, widget: select, values: [Download, Upload]}
          inputs:
            Operation: {type: string, required: true, if_blank: operation}
            Token: {type: string, required: true, if_blank: token, when: {use_token_authentication: {in: [true]}}}
          outputs:
            Session ID: {type: string}
          notes:
            - a note
        LocalFileWatcher:
          display_name: Local file watcher
          category: Triggers
          version: 1.9.3
          attributes: {}
          inputs: {}
          outputs: {}
      YAML
    end

    before do
      allow(Aspera::UriReader).to(receive(:read).and_return(content))
    end

    it 'reads the specifications of GitHub' do
      orchestrator.action_plugins_spec
      expect(Aspera::UriReader).to(have_received(:read).with(%r{^https://raw\.githubusercontent\.com/.+/plugins\.yml$}))
    end

    it 'lists the plugins without their sections' do
      result = orchestrator.action_plugins_spec
      expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
      expect(result.data.map { |e| e['name'] }).to(eq(%w[AscpClient LocalFileWatcher]))
      expect(result.data.first.keys).to(eq(%w[name display_name category version]))
    end

    it 'displays one plugin, with a case insensitive name' do
      result = orchestrator.action_plugins_spec(plugin: 'ascpclient')
      expect(result).to(be_a(Aspera::Cli::Result::SingleObject))
      expect(result.data['name']).to(eq('AscpClient'))
      expect(result.data['inputs']['Token']['when']).to(eq({'use_token_authentication' => {'in' => [true]}}))
    end

    it 'lists one section of a plugin' do
      result = orchestrator.action_plugins_spec(plugin: 'AscpClient', section: :inputs)
      expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
      expect(result.data.map { |e| e['name'] }).to(eq(%w[Operation Token]))
      expect(result.data.first).to(eq({'name' => 'Operation', 'type' => 'string', 'required' => true, 'if_blank' => 'operation'}))
    end

    it 'fails on an unknown plugin, with similar names' do
      expect { orchestrator.action_plugins_spec(plugin: 'Ascp') }
        .to(raise_error(Aspera::Cli::BadArgument, /Unknown plugin: Ascp, similar: AscpClient/))
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

  describe '#action_workstep_status' do
    it 'removes the fields that are YAML dumps of Ruby objects' do
      outputs = [{'value' => nil, 'name' => 'Title', 'id' => 9547, 'type' => 'string'}]
      response = {
        'work_step' => {
          'id' => 3994, 'status' => 'In Progress', 'status_details' => 'Faspex inbox watcher started',
          'prerequisites' => "---\n- !ruby/object:Prerequisite\n", 'work_inputs' => "--- []\n", 'journaling' => "---\n"
        },
        'outputs'   => outputs,
        'inputs'    => []
      }
      allow(orchestrator).to(receive(:call_ao).with('work_step_status/3994').and_return(response))
      expect(orchestrator.action_workstep_status(workstep_id: '3994').data).to(eq({
        'work_step' => {'id' => 3994, 'status' => 'In Progress', 'status_details' => 'Faspex inbox watcher started'},
        'outputs'   => outputs,
        'inputs'    => []
      }))
    end
  end
end
