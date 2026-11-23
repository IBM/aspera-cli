# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `server`: commands, `ascmd`, shims of the moved files.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Server
      RSpec.describe('Bundle server') do
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
          it 'are those of plugin server, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:server)).to(be_nil)
            expect(registry[:server].depends).to(eq([:transfer_agents]))
            expect(registry[:server].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:server)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:server)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('server'))
          end

          it 'use the ascmd of the bundle' do
            expect(AsCmd::OPERATIONS).to(include(:ls, :rm, :cp))
            expect(AsCmd::Error.superclass).to(be(StandardError))
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/server' => %w[Aspera::Cli::Plugins::Server Aspera::Plugins::Server::Commands aspera/plugins/server/commands],
            'aspera/ascmd'              => %w[Aspera::AsCmd Aspera::Plugins::Server::AsCmd aspera/plugins/server/ascmd]
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
