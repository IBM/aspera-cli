# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `orchestrator`: commands, workflow checker, schemas, shims of the moved files.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Orchestrator
      RSpec.describe('Bundle orchestrator') do
        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        # @param script [String] Ruby code run in another process: the former constants are not defined in the process of the specs
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def run_ruby(script)
          Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
        end

        describe 'commands' do
          it 'are those of plugin orchestrator, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:orchestrator)).to(be_nil)
            expect(registry[:orchestrator].depends).to(eq([:transfer_agents]))
            expect(registry[:orchestrator].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:orchestrator)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:orchestrator)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('orchestrator'))
          end

          it 'load the workflow checker only when a workflow is checked' do
            _stdout, stderr, status = run_ruby("require 'aspera/plugins/orchestrator/commands'\nexit(defined?(Aspera::Plugins::Orchestrator::WorkflowChecker) ? 1 : 0)\n")
            expect(status.success?).to(be(true), stderr)
          end
        end

        describe 'schemas' do
          it 'give the Orchestrator API (downloaded, vendor), no longer in the framework, and the options (owned)' do
            schema = registry.schema(:orchestrator)
            expect(schema).to(have_attributes(bundle: :orchestrator, owned: false))
            expect(schema.file).to(eq(File.join(bundle_folder, 'schemas', 'IBM Aspera Orchestrator API-v1-enhanced.yaml')))
            expect(schema.source['url']).to(end_with('-enhanced.yaml'))
            expect(Schema::Registry::LOCATIONS).not_to(include(:orchestrator))
            expect(registry.schema(:orchestrator_opts)).to(have_attributes(bundle: :orchestrator, file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            expect(File.read(File.join(source_root, 'lib/aspera/cli/options.schema.yaml'))).not_to(include('Orchestrator'))
          end

          it 'are readable by the key of the bundle' do
            expect(Schema::Registry.instance.reader(Schema::Registry.query_params(Commands::API_SCHEMA, 'api/workflows_list')).current).to(be_a(Hash))
            %w[WorkflowStart InitiateParameters WorkflowExport WorkflowImport ImportWithConstraints ReloadPluginSet].each do |name|
              expect(Schema::Registry.instance.reader("orchestrator_opts:components.schemas.Orchestrator#{name}").current).to(include('type'))
            end
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/orchestrator'    => %w[Aspera::Cli::Plugins::Orchestrator Aspera::Plugins::Orchestrator::Commands aspera/plugins/orchestrator/commands],
            'aspera/orchestrator_workflow_checker' => %w[Aspera::OrchestratorWorkflowChecker Aspera::Plugins::Orchestrator::WorkflowChecker aspera/plugins/orchestrator/workflow_checker]
          }.freeze

          it 'warn once when loaded, and give the moved constants under their former names' do
            MOVED.each do |path, (former, current, new_path)|
              stdout, stderr, status = run_ruby("2.times { require #{path.inspect} }\nputs Object.const_get(#{former.inspect}).name\n")
              expect(status.success?).to(be(true), stderr)
              expect(stdout.chomp).to(eq(current))
              expect(stderr.scan("#{path} is deprecated: use #{new_path} (removed in 5.0)").length).to(eq(1), stderr)
              # `-w`: warning of `deprecate_constant`, and no other warning
              expect(stderr.lines(chomp: true).grep(/warning:/)).to(eq(["-e:2: warning: constant #{former} is deprecated"]), stderr)
            end
          end
        end
      end
    end
  end
end
