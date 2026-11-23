# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `preview`: commands, generator, schema of the options, shims of the moved files.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Preview
      RSpec.describe('Bundle preview') do
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
          it 'are those of plugin preview, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:preview)).to(be_nil)
            expect(registry[:preview].depends).to(eq([:node]))
            expect(registry[:preview].gems).to(eq(['marcel']))
            expect(Cli::Plugins::Factory.instance.plugin_source(:preview)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:preview)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('preview'))
          end
        end

        describe 'schemas' do
          it 'give the options of the generator, owned by ascli, no longer in the framework' do
            expect(registry.schema(:preview)).to(have_attributes(bundle: :preview, file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            expect(Schema::Registry::LOCATIONS).not_to(include(:preview))
            expect(Schema::Registry.const_defined?(:PREVIEW_OPTIONS, false)).to(be(false))
            expect(Schema::Registry.owned?(Generator::OPTIONS_SCHEMA)).to(be(true))
            expect(Generator::Options.members).to(include(:office_conversion, :video_conversion))
          end

          it 'keep the error images next to the generator' do
            %w[image_error.png video_error.png].each { |name| expect(File.exist?(File.join(bundle_folder, name))).to(be(true), name) }
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/preview' => %w[Aspera::Cli::Plugins::Preview Aspera::Plugins::Preview::Commands aspera/plugins/preview/commands],
            'aspera/preview/file_types'  => %w[Aspera::Preview::FileTypes Aspera::Plugins::Preview::FileTypes aspera/plugins/preview/file_types],
            'aspera/preview/generator'   => %w[Aspera::Preview::Generator Aspera::Plugins::Preview::Generator aspera/plugins/preview/generator],
            'aspera/preview/utils'       => %w[Aspera::Preview::Utils Aspera::Plugins::Preview::Utils aspera/plugins/preview/utils]
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
