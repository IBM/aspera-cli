# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `faspio`: commands, shims of the moved files.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Faspio
      RSpec.describe('Bundle faspio') do
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
          it 'are those of plugin faspio, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:faspio)).to(be_nil)
            expect(registry[:faspio].depends).to(eq([]))
            expect(registry[:faspio].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:faspio)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:faspio)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('faspio'))
          end
        end

        describe 'API schema' do
          it 'is the vendor schema of the bundle (downloaded), not in LOCATIONS' do
            schema = registry.schema(:faspio)
            expect(schema).not_to(be_nil)
            expect(schema.key).to(eq(:faspio))
            expect(schema.owned).to(be(false))
            expect(schema.source['url']).to(end_with('-enhanced.yaml'))
            expect(schema.file).to(eq(File.join(bundle_folder, 'schemas', 'IBM Aspera faspio Gateway API-1.0.0-enhanced.yaml')))
            expect(Schema::Registry.known?(:faspio)).to(be(true))
            expect(Schema::Registry.owned?('faspio')).to(be(false))
            expect(Schema::Registry::LOCATIONS).not_to(include(:faspio))
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/faspio' => %w[Aspera::Cli::Plugins::Faspio Aspera::Plugins::Faspio::Commands aspera/plugins/faspio/commands]
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
