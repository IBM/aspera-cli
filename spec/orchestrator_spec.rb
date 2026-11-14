# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/aspera/cli/plugins/orchestrator'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/transfer_agent'
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

    it 'sends the folder, publication and sub-workflow options' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'wf.yml')
        File.write(path, "---\n")
        allow(orchestrator).to(receive(:call_ao).and_return({'workflow' => {'id' => 1}}))
        file_fields = [['import_file', "---\n", {filename: 'wf.yml'}], ['import_file_name', 'wf.yml']]
        {
          {'folder_id' => 12, 'publish' => true, 'link_to_subworkflows' => true} => [%w[folder_id 12], %w[publish_workflow true], %w[link_to_subworkflows true]],
          # false is sent, to override the server default, except for link_to_subworkflows (any value is true)
          {'publish' => false, 'link_to_subworkflows' => false}                  => [%w[publish_workflow false]]
        }.each do |import, fields|
          orchestrator.action_workflows_import(file_path: path, import: import)
          expect(orchestrator).to(have_received(:call_ao).with('import_workflow', body: file_fields + fields, content_type: Aspera::Mime::MULTIPART))
        end
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

    it 'suggests an export without dependencies when the export with dependencies fails' do
      error = Aspera::Rest::CallError.new({messages: ['Minitar::Writer::WriteBoundaryOverflow']})
      allow(orchestrator).to(receive(:call_ao).and_raise(error))
      allow(Aspera::Log.log).to(receive(:warn))
      expect { orchestrator.action_workflows_export(workflow_id: '1', export: {'dependencies' => true}) }.to(raise_error(error))
      expect(Aspera::Log.log).to(have_received(:warn).with(/export the workflow and each sub-workflow without dependencies/))
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

  describe 'command workflows development' do
    let(:content) { "# Guide\n\nIntro\n\n## Recipes\n\nRecipe text\n\n## Known issues\n\nNone\n" }

    # Run the action of a command of the registry
    def run_doc(document, command, **args)
      spec = described_class.command_registry[[:workflows, :development, document, command]]
      orchestrator.invoke_action(orchestrator.action_for(spec), [], args)
    end

    before do
      allow(Aspera::UriReader).to(receive(:read).and_return(content))
    end

    it 'lists the documents' do
      registry = described_class.command_registry
      expect(registry.children_of(%i[workflows development]).keys).to(eq(%i[guide templates manual]))
      expect(registry.children_of(%i[workflows development guide]).keys).to(eq(%i[toc full section]))
    end

    it 'reads the raw document of GitHub' do
      run_doc(:templates, :full)
      expect(Aspera::UriReader).to(have_received(:read).with(%r{^https://raw\.githubusercontent\.com/.+/action-template-reference\.md$}))
    end

    it 'displays the whole document' do
      result = run_doc(:guide, :full)
      expect(result).to(be_a(Aspera::Cli::Result::Text))
      expect(result.data).to(eq(content))
    end

    it 'lists the table of contents' do
      result = run_doc(:guide, :toc)
      expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
      expect(result.data.map { |e| e['anchor'] }).to(eq(%w[guide recipes known-issues]))
    end

    it 'lists the table of contents up to the level of the document, or the given level' do
      allow(Aspera::UriReader).to(receive(:read).and_return("# Manual\n\n## Category\n\n### Plugin\n\n#### Detail\n"))
      {nil => %w[manual category plugin], 4 => %w[manual category plugin detail], 1 => %w[manual]}.each do |level, anchors|
        result = run_doc(:manual, :toc, level: level)
        expect(result.data.map { |e| e['anchor'] }).to(eq(anchors))
      end
      expect(Aspera::UriReader).to(have_received(:read).with(%r{/Orchestrator_Plugin_Manual\.md$}).at_least(:once))
    end

    it 'displays one section' do
      result = run_doc(:guide, :section, name: 'recipes')
      expect(result.data).to(eq("## Recipes\n\nRecipe text\n\n"))
    end

    it 'fails on an unknown section' do
      expect { run_doc(:guide, :section, name: 'nope') }
        .to(raise_error(Aspera::Cli::Error, /Section not found: nope/))
    end

    it 'reads the guide through the short link first' do
      run_doc(:guide, :full)
      expect(Aspera::UriReader).to(have_received(:read).with('https://ibm.biz/aspera-orchestrator-book'))
    end

    context 'when the short link fails' do
      before do
        allow(Aspera::UriReader).to(receive(:read_fail_fast).and_raise(StandardError, 'unreachable'))
      end

      it 'falls back to GitHub on error' do
        result = run_doc(:guide, :full)
        expect(result.data).to(eq(content))
        expect(Aspera::UriReader).to(have_received(:read).with(%r{^https://raw\.githubusercontent\.com/.+/orchestrator-development-guide\.md$}))
      end

      it 'falls back to GitHub on HTML page' do
        allow(Aspera::UriReader).to(receive(:read_fail_fast).and_return("<!DOCTYPE html>\n<html></html>"))
        result = run_doc(:guide, :full)
        expect(result.data).to(eq(content))
      end

      it 'accepts a document starting with a comment' do
        allow(Aspera::UriReader).to(receive(:read_fail_fast).and_return("<!-- gfm2pdf\n-->\n# Guide\n"))
        result = run_doc(:guide, :full)
        expect(result.data).to(start_with('<!-- gfm2pdf'))
      end
    end
  end

  describe 'commands calling one endpoint' do
    # Run the action of a command of the registry
    def run(path, **args)
      spec = described_class.command_registry[path]
      orchestrator.invoke_action(orchestrator.action_for(spec), [], args)
    end

    before do
      allow(orchestrator).to(receive(:call_ao))
    end

    it 'deletes a work order, whose answer is a JSON string with a leading space' do
      allow(orchestrator).to(receive(:call_ao).and_return(" Work order '12' was deleted"))
      result = run(%i[workorders delete], workorder_id: '12')
      expect(orchestrator).to(have_received(:call_ao).with('work_order_destroy/12'))
      expect(result).to(be_a(Aspera::Cli::Result::Status))
      expect(result.data).to(eq("Work order '12' was deleted"))
    end

    it 'resets a work step' do
      allow(orchestrator).to(receive(:call_ao).and_return({'workstep_reset' => true}))
      run(%i[worksteps reset], workstep_id: '5,6')
      expect(orchestrator).to(have_received(:call_ao).with('workstep_reset/5,6'))
    end

    it 'activates and deactivates a monitor of a type' do
      allow(orchestrator).to(receive(:call_ao).and_return({'description' => 'activated'}))
      run(%i[monitors activate], type: :workflow, monitor_id: 'abc')
      run(%i[monitors deactivate], type: :node, monitor_id: 'def')
      expect(orchestrator).to(have_received(:call_ao).with('activate_monitor/abc', query: {monitor_type: :workflow}))
      expect(orchestrator).to(have_received(:call_ao).with('deactivate_monitor/def', query: {monitor_type: :node}))
    end

    it 'lists the tasks of the current user by default' do
      allow(orchestrator).to(receive(:call_ao).and_return({'user' => 'admin', 'tasks' => [{'id' => 1}]}))
      result = run(%i[tasks list], user: 'self')
      expect(orchestrator).to(have_received(:call_ao).with('list_tasks/self'))
      expect(result.data).to(eq([{'id' => 1}]))
    end

    it 'shows a task, with the step name given twice as expected by Orchestrator' do
      allow(orchestrator).to(receive(:call_ao).and_return({'task' => {'id' => 1}}))
      run(%i[tasks show], task_id: 'WO3', step_name: 'Ask')
      expect(orchestrator).to(have_received(:call_ao).with('task_details/WO3', query: {step_name: 'Ask', Step_name: 'Ask'}))
      run(%i[tasks show], task_id: '4')
      expect(orchestrator).to(have_received(:call_ao).with('task_details/4', query: {}))
    end

    it 'submits the values of the user inputs of a task' do
      allow(orchestrator).to(receive(:call_ao).and_return({'task' => {'id' => 1}}))
      run(%i[tasks submit], task_id: '1', inputs: {'Filename' => 'tron.avi'})
      expect(orchestrator).to(have_received(:call_ao).with('submit_task/1', query: {'outputs[Filename]': 'tron.avi'}))
    end

    it 'controls a process and shows the processes of all nodes' do
      allow(orchestrator).to(receive(:call_ao).and_return({'node' => [{'process' => [{'class' => 'engine'}]}, {'process' => [{'class' => 'worker'}]}]}))
      result = run(%i[control], process: :worker, operation: :stop, worker_ids: '1,2')
      expect(orchestrator).to(have_received(:call_ao).with('control_process/worker', query: {command: :stop, worker_id: '1,2'}, accept: Aspera::Mime::XML, xml_opts: {'ForceArray' => %w[node process]}))
      expect(result.data).to(eq([{'class' => 'engine'}, {'class' => 'worker'}]))
    end

    it 'lists alerts' do
      allow(orchestrator).to(receive(:call_ao).and_return([{'id' => 1}]))
      result = run(%i[alerts list])
      expect(orchestrator).to(have_received(:call_ao).with('alerts/0'))
      expect(result.data).to(eq([{'id' => 1}]))
    end

    it 'gives the statistics, or the message when there is none' do
      allow(orchestrator).to(receive(:call_ao).and_return([{'Date' => '2026-11-01'}], 'No Statistics found. Change the filter and try again.'))
      expect(run(%i[workorders stats]).data).to(eq([{'Date' => '2026-11-01'}]))
      result = run(%i[worksteps stats])
      expect(orchestrator).to(have_received(:call_ao).with('work_order_stats/0'))
      expect(orchestrator).to(have_received(:call_ao).with('work_step_stats/0'))
      expect(result).to(be_a(Aspera::Cli::Result::Status))
      expect(result.data).to(eq('No Statistics found. Change the filter and try again.'))
    end

    it 'manages the items of a queue' do
      allow(orchestrator).to(receive(:call_ao).and_return({'queued_items' => [{'id' => 21}]}))
      expect(run(%i[queues items], queue: 'q1').data).to(eq([{'id' => 21}]))
      run(%i[queues add], queue: 'q1', item: 'file.txt')
      run(%i[queues move], operation: :first, item_id: '21')
      run(%i[queues lookup])
      expect(orchestrator).to(have_received(:call_ao).with('queued_items/q1'))
      expect(orchestrator).to(have_received(:call_ao).with('queue_item/q1', query: {queued_item: 'file.txt'}))
      expect(orchestrator).to(have_received(:call_ao).with('reorder_queued_item', query: {operation: :first, queued_item_id: '21'}))
      expect(orchestrator).to(have_received(:call_ao).with('lookup_queued_item'))
    end

    it 'encodes the name of a queue or a user in the path' do
      allow(orchestrator).to(receive(:call_ao).and_return({}))
      run(%i[queues items], queue: 'my queue')
      run(%i[queues add], queue: 'my queue', item: 'file.txt')
      run(%i[tasks list], user: 'my user')
      expect(orchestrator).to(have_received(:call_ao).with('queued_items/my%20queue'))
      expect(orchestrator).to(have_received(:call_ao).with('queue_item/my%20queue', query: {queued_item: 'file.txt'}))
      expect(orchestrator).to(have_received(:call_ao).with('list_tasks/my%20user'))
    end

    it 'moves several queued items and lists the moved items' do
      allow(orchestrator).to(receive(:call_ao).and_return({'queued_items' => [{'queued_item' => {'id' => 1}, 'queue_data' => {}}, {'queued_item' => {'id' => 2}, 'queue_data' => {}}]}))
      result = run(%i[queues bulk_move], operation: :last, item_ids: '1,2')
      expect(orchestrator).to(have_received(:call_ao).with('bulk_reorder_queue', query: {operation: :last, queued_item_ids: '1,2'}))
      expect(result.data).to(eq([{'id' => 1}, {'id' => 2}]))
    end

    it 'deletes a queued item, using the XML answer because the JSON one is not valid JSON' do
      xml = "<?xml version=\"1.0\"?>\n<DeleteQueuedItem>\n  <Success>Item with id 21 was succesfully deleted.</Success>\n</DeleteQueuedItem>\n"
      api = instance_double(Aspera::Rest::Client, call: [nil, instance_double(Net::HTTPResponse, body: xml)])
      allow(orchestrator).to(receive(:api_orch).and_return(api))
      allow(orchestrator).to(receive(:call_ao).and_call_original)
      result = run(%i[queues delete], queue: 'q1', item_id: '21')
      expect(api).to(have_received(:call).with(hash_including(subpath: 'api/delete_queued_item', query: {queue_name: 'q1', queued_item_id: '21', format: 'xml'})))
      expect(result).to(be_a(Aspera::Cli::Result::Status))
      expect(result.data).to(eq('Item with id 21 was succesfully deleted.'))
    end

    it 'changes resources and capacity of a pool' do
      allow(orchestrator).to(receive(:call_ao).and_return({'ManagedResource' => {'id' => 1}}))
      run(%i[pools add_resource], pool_name: 'p', resource_name: '10.0.0.1')
      run(%i[pools resource_capacity], pool_name: 'p', resource_name: '10.0.0.1', capacity: 3)
      run(%i[pools online], pool_name: 'p', resource_name: '10.0.0.1')
      run(%i[pools offline], pool_name: 'p', resource_name: '10.0.0.1')
      query = {pool_name: 'p', resource_name: '10.0.0.1'}
      expect(orchestrator).to(have_received(:call_ao).with('add_resource/0', query: query, json_opts: {allow_duplicate_key: true}))
      expect(orchestrator).to(have_received(:call_ao).with('edit_resource_capacity/3', query: query, json_opts: {allow_duplicate_key: true}))
      expect(orchestrator).to(have_received(:call_ao).with('resource_online/0', query: query))
      expect(orchestrator).to(have_received(:call_ao).with('resource_offline/0', query: query))
      allow(orchestrator).to(receive(:call_ao).and_return({'ManagedResource' => [{'id' => 1}]}))
      expect(run(%i[pools capacity], pool_name: 'p', capacity: 5).data).to(eq([{'id' => 1}]))
      expect(orchestrator).to(have_received(:call_ao).with('edit_pool_capacity/5', query: {pool_name: 'p'}, json_opts: {allow_duplicate_key: true}))
    end

    it 'reloads, enables and imports plugins' do
      allow(orchestrator).to(receive(:call_ao).and_return({'All Plugins' => true}))
      run(%i[plugins reload])
      run(%i[plugins reload], plugin: 'Adi3Parser')
      run(%i[plugins enable])
      run(%i[plugins import], file_path: '/tmp/p.zip')
      expect(orchestrator).to(have_received(:call_ao).with('reload_plugin', query: {}))
      expect(orchestrator).to(have_received(:call_ao).with('reload_plugin', query: {action_type: 'Adi3Parser'}))
      expect(orchestrator).to(have_received(:call_ao).with('enable_plugin/0', query: {}))
      expect(orchestrator).to(have_received(:call_ao).with('import_plugin/0', query: {file: '/tmp/p.zip'}))
    end

    it 'queries workflows by sub-workflow, step type and test run' do
      allow(orchestrator).to(receive(:call_ao).and_return({'parent_workflows' => %w[A B]}, [{'wf_id' => '1'}], {'Test_run_id' => 'u'}, {'Test_run_id' => 'u'}))
      expect(run(%i[workflows parents], workflow_id: '7').data).to(eq(%w[A B]))
      expect(run(%i[workflows steps], step_type: 'CustomRuby').data).to(eq([{'wf_id' => '1'}]))
      run(%i[workflows test_step], workflow_id: '7')
      run(%i[workflows test_status], test_run_id: 'u')
      expect(orchestrator).to(have_received(:call_ao).with('list_by_subworkflow/7'))
      expect(orchestrator).to(have_received(:call_ao).with('retrieve_steps/0', query: {type: 'CustomRuby'}))
      expect(orchestrator).to(have_received(:call_ao).with('test_step/7'))
      expect(orchestrator).to(have_received(:call_ao).with('test_step_status/u'))
    end

    it 'creates a user, and shows the portlets and the statistics of the execution queue' do
      allow(orchestrator).to(receive(:call_ao).and_return({'create_user' => {'success' => "User 'jdoe' was successfully created."}}))
      result = run(%i[users create], user: {'login' => 'jdoe'})
      expect(orchestrator).to(have_received(:call_ao).with('create_user/0', body: {'login' => 'jdoe'}))
      expect(result.data).to(eq("User 'jdoe' was successfully created."))
      allow(orchestrator).to(receive(:call_ao).and_return({'Portlet' => [{'name' => 'x'}]}))
      expect(run(%i[portlets list]).data).to(eq([{'name' => 'x'}]))
      allow(orchestrator).to(receive(:call_ao).and_return({'ready' => 1}))
      run(%i[queues stats])
      expect(orchestrator).to(have_received(:call_ao).with('execution_queue_stats/0'))
    end
  end

  describe 'command plugins spec' do
    let(:content) do
      <<~YAML
        # header
        ---
        AscpClient:
          display_name: Ascp client
          category: File Transfer
          version: 1.6.2
          manual_anchor: ascp-client
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

    # Run the action of a command of the registry
    def run_spec(command, **args)
      spec = described_class.command_registry[[:plugins, :spec, command]]
      orchestrator.invoke_action(orchestrator.action_for(spec), [], args)
    end

    before do
      allow(Aspera::UriReader).to(receive(:read).and_return(content))
    end

    it 'has commands toc and show' do
      expect(described_class.command_registry.children_of(%i[plugins spec]).keys).to(eq(%i[toc show]))
    end

    it 'reads the specifications of GitHub' do
      run_spec(:toc)
      expect(Aspera::UriReader).to(have_received(:read).with(%r{^https://raw\.githubusercontent\.com/.+/plugins\.yml$}))
    end

    it 'lists the plugins without their sections' do
      result = run_spec(:toc)
      expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
      expect(result.data.map { |e| e['name'] }).to(eq(%w[AscpClient LocalFileWatcher]))
      expect(result.data.first.keys).to(eq(%w[name display_name category version manual_anchor]))
    end

    it 'displays one plugin, with a case insensitive name' do
      result = run_spec(:show, plugin: 'ascpclient')
      expect(result).to(be_a(Aspera::Cli::Result::SingleObject))
      expect(result.data['name']).to(eq('AscpClient'))
      expect(result.data['inputs']['Token']['when']).to(eq({'use_token_authentication' => {'in' => [true]}}))
    end

    it 'lists one section of a plugin' do
      result = run_spec(:show, plugin: 'AscpClient', section: :inputs)
      expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
      expect(result.data.map { |e| e['name'] }).to(eq(%w[Operation Token]))
      expect(result.data.first).to(eq({'name' => 'Operation', 'type' => 'string', 'required' => true, 'if_blank' => 'operation'}))
    end

    it 'fails on an unknown plugin, with similar names' do
      expect { run_spec(:show, plugin: 'Ascp') }
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

  describe '#action_worksteps_status' do
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
      expect(orchestrator.action_worksteps_status(workstep_id: '3994').data).to(eq({
        'work_step' => {'id' => 3994, 'status' => 'In Progress', 'status_details' => 'Faspex inbox watcher started'},
        'outputs'   => outputs,
        'inputs'    => []
      }))
    end
  end

  describe '#action_monitors_list' do
    it 'calls list_monitors with an id in the path, and unwraps monitors of work orders' do
      allow(orchestrator).to(receive(:call_ao).and_return([{'monitor-workorder' => {'id' => 1}}, {'id' => 2, 'remote_node_name' => 'localhost'}]))
      expect(orchestrator.action_monitors_list(type: :node).data).to(eq([{'id' => 1}, {'id' => 2, 'remote_node_name' => 'localhost'}]))
      expect(orchestrator).to(have_received(:call_ao).with('list_monitors/0', query: {monitor_type: :node}))
    end
  end

  describe '#action_journal_files' do
    it 'lists the files of the packages, with the package name, and the files without package' do
      report = {
        'Journal'  => {'name' => 'journal', 'id' => 1},
        'Packages' => [{'name' => 'pkg', 'id' => 7, 'files' => [{'file_id' => 1, 'file' => '/a.mp4'}]}],
        'Files'    => [{'file_id' => 2, 'file' => '/b.xml'}]
      }
      allow(orchestrator).to(receive(:call_ao).with('journal_files/journal').and_return(report))
      expect(orchestrator.action_journal_files(book: 'journal').data)
        .to(eq([{'package' => 'pkg', 'file_id' => 1, 'file' => '/a.mp4'}, {'file_id' => 2, 'file' => '/b.xml'}]))
    end

    it 'encodes the name of the book in the path' do
      allow(orchestrator).to(receive(:call_ao).with('journal_files/my%20book').and_return({}))
      expect(orchestrator.action_journal_files(book: 'my book').data).to(eq([]))
    end
  end

  describe '#api_query_schema' do
    it 'finds the path of the endpoint in the OpenAPI description, with or without id' do
      expect(orchestrator.send(:api_query_schema, 'journal_files/journal', 'GET')).to(eq('orchestrator:paths./api/journal_files/{id}.get.parameters'))
      expect(orchestrator.send(:api_query_schema, 'workflows_list', 'GET')).to(eq('orchestrator:paths./api/workflows_list.get.parameters'))
      expect(orchestrator.send(:api_query_schema, 'workflows_status/12', 'GET')).to(eq('orchestrator:paths./api/workflows_status.get.parameters'))
      expect(orchestrator.send(:api_query_schema, 'no_such_endpoint', 'GET')).to(be_nil)
    end

    it 'gives the query parameters, including shared ones' do
      properties = Aspera::Schema::Registry.instance.reader(orchestrator.send(:api_query_schema, 'journal_files/journal', 'GET'))['properties']
      expect(properties.keys).to(include('status', 'file', 'package', 'package_id', 'details', 'format'))
    end
  end
end
