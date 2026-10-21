# frozen_string_literal: true

require_relative 'spec_helper'
require 'aspera/orchestrator_workflow_checker'
require 'stringio'
require 'zlib'
require 'rubygems/package'

RSpec.describe(Aspera::OrchestratorWorkflowChecker) do
  # Plain format, one step: the example of the Workflow Authoring Guide
  let(:workflow) do
    <<~YAML
      ---
      - !ruby/object:Workflow
        attributes:
          name: hello
          run_as: SYSTEM
      - !ruby/object:Whiteboard
        attributes:
          error_free: true
          xml_export: |
            <?xml version="1.0" encoding="UTF-8"?>
            <Workflow id="0">
            <Start x="100" y="50" id="start"><Parameters><Parameter id="p_who"/></Parameters></Start>
            <Error x="900" y="350" id="error"><Synch_factor>0</Synch_factor><Prerequisites></Prerequisites></Error>
            <End x="900" y="50" id="end"><Synch_factor>0</Synch_factor><Prerequisites><Prerequisite id="step1" status="Complete"/></Prerequisites></End>
            <Fail x="900" y="200" id="fail"><Synch_factor>0</Synch_factor><Prerequisites></Prerequisites></Fail>
            <Steps>
            <Step x="400" y="50" id="step1"><Action_id>1</Action_id><Step_name>Say hello</Step_name><Step_type>CustomRuby</Step_type><Synch_factor>0</Synch_factor><Prerequisites><Prerequisite id="start" status="true"/></Prerequisites><Parameters></Parameters><Inputs><Input name="person"><Map_to type="parameter" name="who"/></Input></Inputs><Outputs></Outputs></Step>
            </Steps>
            <Parameters><Parameter x="100" y="200" id="p_who"><Name>who</Name><Value>world</Value><Value_type>string</Value_type></Parameter></Parameters>
            <Notes></Notes>
            </Workflow>
      - CustomRuby__1: !ruby/object:CustomRuby
          attributes:
            name: W0__Say hello
            execute_code: "outputs['message'] = 'Hello'"
      - CustomRuby__1: []
      - {}
      - CustomRuby: 0.7.0
    YAML
  end

  def check(content, file_name: 'wf.yml')
    described_class.check(file_name: file_name, content: content)
  end

  def codes(response)
    response['issues'].map { |issue| issue['code'] }
  end

  # @return [String] bytes of a `.wkf` package with the given files
  def package(files)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        files.each { |name, content| tar.add_file_simple(name, 0o644, content.bytesize) { |entry| entry.write(content) } }
      end
    end
    io.string
  end

  describe '.check' do
    it 'returns a Hash that can be serialized as JSON' do
      response = check(workflow)
      expect(response).to(eq({'valid' => true, 'file_name' => 'wf.yml', 'issues' => []}))
      expect(JSON.parse(JSON.generate(response))).to(eq(response))
    end

    it 'gives for each issue a severity, a stable code, a path and a message' do
      response = check(workflow.sub('<Prerequisite id="start" status="true"/>', ''))
      expect(response['valid']).to(be(false))
      expect(response['issues']).to(eq([{
        'severity' => 'error',
        'code'     => 'graph.step_orphan',
        'path'     => 'graph/Step[Say hello]',
        'message'  => 'no prerequisite, the step never runs (orphaned)'
      }]))
    end

    it 'is valid with only warnings' do
      response = check(workflow.sub('name: W0__Say hello', "name: W0__Say hello\n      flag: false"))
      expect(codes(response)).to(eq(['template.boolean']))
      expect(response['valid']).to(be(true))
    end

    it 'refuses another extension' do
      expect(codes(check(workflow, file_name: 'wf.txt'))).to(eq(['file.extension']))
    end
  end

  describe 'file' do
    it 'reports invalid YAML' do
      expect(codes(check("- [\n"))).to(eq(['yaml.invalid']))
    end

    it 'reports an empty file' do
      expect(codes(check(''))).to(eq(['yaml.empty']))
    end

    it 'reports a file that is not a list' do
      expect(codes(check("a: 1\n"))).to(eq(['yaml.not_list']))
    end

    it 'reports a wrong number of elements' do
      expect(codes(check(workflow.sub(/^- CustomRuby: 0.7.0\n/, '').sub("- {}\n", '')))).to(include('yaml.element_count'))
    end

    it 'accepts the 5 elements of files exported by Orchestrator' do
      expect(check(workflow.sub(/^- CustomRuby: 0.7.0\n/, ''))['valid']).to(be(true))
    end

    it 'reports a workflow without name' do
      expect(codes(check(workflow.sub('name: hello', 'run_as: SYSTEM')))).to(include('workflow.name_missing'))
    end

    it 'reports a whiteboard that cannot be published' do
      expect(codes(check(workflow.sub('error_free: true', 'error_free: false')))).to(eq(['whiteboard.error_free']))
    end

    it 'warns on an unknown attribute' do
      expect(codes(check(workflow.sub('run_as: SYSTEM', "run_as: SYSTEM\n    bad_attribute: 1")))).to(eq(['workflow.attribute_unknown']))
    end

    it 'reports a template that is not tagged with the class of its key' do
      expect(codes(check(workflow.sub('CustomRuby__1: !ruby/object:CustomRuby', 'CustomRuby__1: !ruby/object:Filter')))).to(include('template.tag'))
    end
  end

  describe 'graph' do
    it 'reports invalid XML' do
      expect(codes(check(workflow.sub('</Workflow>', '')))).to(eq(['graph.xml_invalid']))
    end

    it 'reports a missing terminal node' do
      expect(codes(check(workflow.sub(%r{<Fail .*</Fail>\n}, '')))).to(include('graph.terminal_count'))
    end

    it 'reports a step without template' do
      expect(codes(check(workflow.sub('CustomRuby__1: !ruby', 'CustomRuby__9: !ruby')))).to(eq(['graph.template_missing']))
    end

    it 'reports a step that nothing follows' do
      response = check(workflow.sub('<Prerequisite id="step1" status="Complete"/>', ''))
      expect(codes(response)).to(eq(%w[graph.step_no_output graph.no_termination]))
    end

    it 'reports a prerequisite on an unknown node' do
      expect(codes(check(workflow.sub('id="start" status', 'id="nowhere" status')))).to(include('graph.prerequisite_unknown'))
    end

    it 'reports a negative Synch_factor' do
      expect(codes(check(workflow.sub('<Synch_factor>0</Synch_factor><Prerequisites><Prerequisite id="start"', '<Synch_factor>-1</Synch_factor><Prerequisites><Prerequisite id="start"')))).to(eq(['graph.synch_factor_negative']))
    end

    it 'reports an input mapped to an undefined parameter' do
      expect(codes(check(workflow.sub('name="who"/>', 'name="other"/>')))).to(eq(['graph.parameter_undefined']))
    end

    it 'reports a parameter not linked to Start' do
      expect(codes(check(workflow.sub('<Parameter id="p_who"/>', '')))).to(eq(['graph.parameter_not_linked']))
    end

    it 'reports an unknown output reference' do
      mapped = workflow.sub('<Map_to type="parameter" name="who"/>', '<Map_to type="output" name="x" step_type="CustomRuby" action_id="1" step_name="Nope"/>')
      expect(codes(check(mapped))).to(include('graph.output_unknown'))
    end

    it 'reports a parameter of unknown type' do
      expect(codes(check(workflow.sub('<Value_type>string', '<Value_type>text')))).to(eq(['graph.parameter_type']))
    end
  end

  describe 'with plugin specifications' do
    # Format of plugins.yml (plugin documentation): attributes, inputs and outputs, and conditions on attributes
    let(:specs) do
      {
        'CustomRuby' => {
          'attributes' => {
            'execute_code'        => {'type' => 'mediumtext'},
            'mandatory_inputs'    => {'type' => 'text', 'widget' => 'type_map', 'declares' => 'required_inputs'},
            'typed_outputs'       => {'type' => 'text', 'widget' => 'type_map', 'declares' => 'outputs'},
            'source_control_type' => {'type' => 'string', 'widget' => 'select', 'values' => %w[github bitbucket]},
            'use_cached'          => {'type' => 'boolean'},
            'folder'              => {'type' => 'string', 'placeholders' => true}
          },
          'inputs'     => {'Folder' => {'type' => 'string', 'required' => true, 'if_blank' => 'folder', 'when' => {'source_control_type' => {'in' => ['bitbucket']}}}},
          'outputs'    => {'Step_information' => {'type' => 'hash'}},
          'notes'      => ['Inputs are partly defined by template fields: see the template attributes.']
        }
      }
    end

    def check_with_specs(content, plugin_specs = specs)
      described_class.check(file_name: 'wf.yml', content: content, specs: plugin_specs)
    end

    # @return [String] the workflow with these lines added to the attributes of its template
    def with_attributes(*lines, content: workflow)
      content.sub('name: W0__Say hello', (['name: W0__Say hello'] + lines).join("\n      "))
    end

    let(:declared) { with_attributes(%q(mandatory_inputs: "{'person'=>'string'}")) }

    it 'accepts an input declared by the template' do
      expect(check_with_specs(declared)).to(eq({'valid' => true, 'file_name' => 'wf.yml', 'issues' => []}))
    end

    it 'warns on an input that the plugin does not have with this template' do
      response = check_with_specs(workflow)
      expect(codes(response)).to(eq(['step.input_unknown']))
      expect(response['valid']).to(be(true))
    end

    it 'reports a required input that is not mapped' do
      response = check_with_specs(with_attributes(%q(mandatory_inputs: "{'person'=>'string', 'age'=>'int'}")))
      expect(response['issues'].map { |issue| [issue['code'], issue['message']] }).to(eq([['step.input_missing', 'required input age is not mapped']]))
    end

    it 'evaluates the conditions of an input on the attributes of the template' do
      bitbucket = with_attributes('source_control_type: bitbucket', content: declared)
      expect(check_with_specs(bitbucket)['issues'].map { |issue| issue['message'] }).to(eq(['required input Folder is not mapped']))
      expect(check_with_specs(with_attributes('folder: /tmp', content: bitbucket))['issues']).to(be_empty)
    end

    it 'takes placeholders of an attribute as required inputs' do
      response = check_with_specs(with_attributes('folder: /data/<%= sub %>', content: declared))
      expect(response['issues'].map { |issue| issue['message'] }).to(eq(['required input sub is not mapped']))
    end

    it 'reports an unknown attribute' do
      expect(codes(check_with_specs(with_attributes('execute_cod: 1', content: declared)))).to(eq(['template.attribute_unknown']))
    end

    it 'reports a value that is not allowed' do
      response = check_with_specs(with_attributes('source_control_type: gitlab', content: declared))
      expect(response['issues'].map { |issue| [issue['severity'], issue['message']] })
        .to(eq([['error', 'source_control_type: gitlab is not an allowed value: github, bitbucket']]))
    end

    it 'warns on a boolean that is read as true' do
      response = check_with_specs(with_attributes('use_cached: yes', content: declared))
      expect(response['issues'].map { |issue| [issue['severity'], issue['message']] }).to(eq([['warning', 'use_cached: yes is read as true: write 1 or 0']]))
    end

    it 'reports a plugin class name with a wrong case' do
      wrong_case = declared.gsub('CustomRuby__1', 'Customruby__1').sub('object:CustomRuby', 'object:Customruby').sub('<Step_type>CustomRuby', '<Step_type>Customruby')
      expect(codes(check_with_specs(wrong_case))).to(eq(['template.plugin_case']))
    end

    it 'warns on a plugin that is not in the specifications, and does not check it' do
      expect(codes(check_with_specs(workflow, {}))).to(eq(['template.plugin_unknown']))
    end

    it 'warns on a mapped output that the source step does not produce' do
      mapped = declared.sub('<Map_to type="parameter" name="who"/>', '<Map_to type="output" name="message" step_type="CustomRuby" action_id="1" step_name="Say hello"/>')
      expect(codes(check_with_specs(mapped))).to(eq(['step.output_not_produced']))
    end
  end

  describe 'package' do
    let(:manifest) { "---\n- Workflow_hello__1.yml\n" }

    it 'checks the workflows listed in the manifest' do
      response = check(package('x/Workflow_hello__1.yml' => workflow, 'x/Workflow_hello__1.txt' => manifest), file_name: 'wf.wkf')
      expect(response).to(eq({'valid' => true, 'file_name' => 'wf.wkf', 'issues' => []}))
    end

    it 'gives the file of the package where an issue is' do
      bad = workflow.sub('error_free: true', 'error_free: false')
      response = check(package('x/Workflow_hello__1.yml' => bad, 'x/Workflow_hello__1.txt' => manifest), file_name: 'wf.wkf')
      expect(response['issues']).to(eq([{
        'severity' => 'error', 'code' => 'whiteboard.error_free', 'file' => 'Workflow_hello__1.yml', 'path' => 'whiteboard',
        'message'  => 'error_free is not true: the workflow cannot be published'
      }]))
    end

    it 'reports a file listed but not in the package' do
      response = check(package('x/Workflow_hello__1.txt' => manifest), file_name: 'wf.wkf')
      expect(codes(response)).to(eq(['package.file_missing']))
    end

    it 'reports a package without manifest' do
      expect(codes(check(package('x/other.yml' => workflow), file_name: 'wf.wkf'))).to(eq(['package.manifest_missing']))
    end

    it 'reports a file that is not an archive' do
      expect(codes(check('not an archive', file_name: 'wf.wkf'))).to(eq(['package.archive']))
    end
  end
end
