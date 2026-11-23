# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `aoc`: commands, API, GraphQL queries, schemas, mounts of the Node and Ats commands, shims of the moved files.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Aoc
      RSpec.describe('Bundle aoc') do
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
          it 'are those of plugin aoc, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:aoc)).to(be_nil)
            expect(registry[:aoc].depends).to(eq(%i[node ats]))
            expect(registry[:aoc].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:aoc)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:aoc)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('aoc'))
          end

          it 'mount the Node commands on packages and files, and the Ats commands on admin ats' do
            %i[packages files].each do |name|
              expect(Commands.command_registry.mount_of([name])).to(have_attributes(plugin: Node::Commands))
            end
            expect(Commands.command_registry.mount_of(%i[admin ats])).to(have_attributes(plugin: Ats::Commands))
          end
        end

        describe 'API' do
          it 'is a REST client of Aspera on Cloud' do
            expect(Api.superclass).to(be(Rest::Client))
            expect(Api::SAAS_DOMAIN_PROD).to(eq('ibmaspera.com'))
          end
        end

        describe 'GraphQL' do
          it 'reads the queries of the bundle' do
            queries = Dir.children(File.join(bundle_folder, 'queries')).sort
            expect(queries).to(eq(%w[bss_subscription_account.graphql bss_subscription_usage.graphql]))
            rest = instance_double(Rest::Client)
            allow(rest).to(receive(:create).and_return({'data' => {'ok' => true}}))
            expect(GraphQL.execute(rest, 'bss_subscription_account', {organization_id: 'o1'})).to(eq({'ok' => true}))
            expect(rest).to(have_received(:create).with(nil, hash_including(variables: {organization_id: 'o1'})))
            expect { GraphQL.execute(rest, '../plugin', {}) }.to(raise_error(StandardError))
          end
        end

        describe 'schemas' do
          it 'give the AoC and Automation APIs (downloaded, vendor), no longer in the framework, and the options (owned)' do
            %i[aoc automation].each do |key|
              schema = registry.schema(key)
              expect(schema).to(have_attributes(bundle: :aoc, owned: false))
              expect(schema.file).to(start_with(File.join(bundle_folder, 'schemas', 'IBM Aspera on Cloud')))
              expect(schema.source['url']).to(end_with('-enhanced.yaml'))
              expect(Schema::Registry::LOCATIONS).not_to(include(key))
            end
            expect(registry.schema(:aoc_opts)).to(have_attributes(bundle: :aoc, file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            %i[AOC AUTOMATION PACKAGE_FOLDER_OPTIONS].each do |name|
              expect(Schema::Registry.const_defined?(name, false)).to(be(false))
            end
            expect(File.read(File.join(source_root, 'lib/aspera/cli/options.schema.yaml'))).not_to(include('PackageFolderOptions'))
          end

          it 'are readable by the key of the bundle' do
            expect(Schema::Registry.instance.reader(Schema::Registry.req_body(Commands::AOC_SCHEMA, 'packages.post')).current).to(be_a(Hash))
            expect(Schema::Registry.instance.reader(Schema::Registry.req_body(Commands::AUTOMATION_SCHEMA, 'actions.post')).current).to(be_a(Hash))
            expect(Schema::Registry.instance.reader(Commands::PACKAGE_FOLDER_OPTIONS).current).to(include('properties'))
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/aoc' => %w[Aspera::Cli::Plugins::Aoc Aspera::Plugins::Aoc::Commands aspera/plugins/aoc/commands],
            'aspera/api/aoc'         => %w[Aspera::Api::AoC Aspera::Plugins::Aoc::Api aspera/plugins/aoc/api],
            'aspera/graphql'         => %w[Aspera::GraphQL Aspera::Plugins::Aoc::GraphQL aspera/plugins/aoc/graphql]
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
