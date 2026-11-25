# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `xfer`: modules mounted on plugin config, service `transfer` and helper of the bundles that transfer files,
# extension point `agent`, and bundles of a plugin folder that use its hooks.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/context'
require_relative '../../../cli/info'
require_relative '../../../cli/plugins/config'
require_relative '../../../yaml'
require_relative '../helper'
require_relative '../transfer_agent'
require 'fileutils'
require 'json_schemer'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

module Aspera
  module Plugins
    module Xfer
      RSpec.describe('Bundle xfer') do
        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        describe 'modules mounted on plugin config' do
          let(:commands) { Cli::Plugins::Config.command_registry }

          it 'are the modules of the manifest, in its order' do
            mounts = registry.mounts(:config).select { |mount| mount.bundle.eql?(:xfer) }
            expect(mounts.map(&:constant)).to(eq(%w[SyncActions AscpLogsActions AscpActions TransferActions ConfigCommands]))
            expect(Cli::Plugins::Config.ancestors).to(include(SyncActions, AscpLogsActions, AscpActions, TransferActions, ConfigCommands))
          end

          it 'place the command trees where config had them: sync before gem, the others before transferd' do
            top = commands.children_of([]).keys
            expect(top.each_cons(3).to_a).to(include(%i[image sync gem]))
            expect(top.last(5)).to(eq(%i[completion ascp agents transfer transferd]))
            expect(commands.children_of([:ascp]).keys).to(eq(%i[show info install spec schema errors logs products]))
            expect(commands.children_of([:agents]).keys).to(eq(%i[list show parameters jobs]))
            expect(commands.children_of([:sync]).keys).to(eq(%i[spec admin logs translate]))
          end

          it 'declare their options before the options of config' do
            expect(Cli::Plugins::Config.option_specs.keys.first(3)).to(eq(%i[sql ascp_logs preset]))
            expect(Cli::Plugins::Config.option_specs[:ascp_logs].schema).to(eq(AscpLogsActions::OPTIONS_SCHEMA))
            expect(Schema::Registry.instance.reader(AscpLogsActions::OPTIONS_SCHEMA)['properties']).to(include('period', 'thresholds'))
          end

          it 'place the options of ascp before the option smtp of config' do
            expect(Cli::Plugins::Config.option_specs.keys.each_cons(5).to_a).to(include(%i[plugin_folder sdk_url locations_url sdk_folder smtp]))
          end
        end

        describe 'errors' do
          it 'of transfers have their own exit code' do
            expect(Cli::ExitCode.error_category(Aspera::Transfer::Error.new('failed'))).to(eq({label: 'Transfer', code: Cli::ExitCode::TRANSFER}))
          end

          it 'have hints' do
            hints = Cli::Hints.instance_variable_get(:@added).map { |hint| [hint[:exception], hint[:match]] }
            expect(hints).to(include([Aspera::Transfer::Error, 'Remote host is not who we expected'], [RuntimeError, /Wrong remote host:/]))
            lines = []
            allow(Log.log).to(receive(:info)) { |&block| lines.push(block.call) }
            Cli::Hints.hint_for(Aspera::Transfer::Error.new('Remote host is not who we expected'), nil)
            expect(lines.join("\n")).to(include('#error-remote-host-is-not-who-we-expected', '"sshfp":null'))
          end
        end

        describe 'service transfer' do
          it 'is the transfer agent of the bundle' do
            service = registry.service(:transfer)
            expect(service).to(have_attributes(bundle: :xfer, file: 'transfer_agent.rb', constant: 'TransferAgent'))
            expect(registry.load_entry(service)).to(be(TransferAgent))
          end

          it 'is given to the commands of the bundles by the helper' do
            transfer = instance_double(TransferAgent)
            context = instance_double(Cli::Context)
            allow(context).to(receive(:service).with(:transfer).and_return(transfer))
            plugin = Class.new do
              include Helper

              define_method(:context) { context }
            end.new
            expect(plugin.transfer).to(be(transfer))
          end
        end

        describe 'extension point agent' do
          let(:schema) { JSONSchemer.schema(Aspera::Yaml.safe_load(File.read(File.join(bundle_folder, registry[:xfer].extension_points[:agent])))) }
          let(:entry) { {'name' => 'spec_agent', 'short' => 's', 'options_schema' => 'schemas/agent_options.yaml'} }

          it 'is declared by the bundle' do
            expect(registry[:xfer].extension_points).to(eq({agent: 'schemas/agent_extension.schema.yaml'}))
          end

          it 'accepts an entry with a name, a letter and the schema of the parameters of the agent' do
            expect(schema.valid?(entry)).to(be(true))
          end

          it 'refuses an entry with a missing field, an invalid name, letter or file, or another field' do
            [
              entry.except('short'), entry.except('options_schema'), entry.merge('name' => 'Spec'), entry.merge('short' => 'ss'),
              entry.merge('short' => 'S'), entry.merge('options_schema' => '../options.yaml'), entry.merge('other' => 1)
            ].each do |invalid|
              expect(schema.valid?(invalid)).to(be(false), invalid.inspect)
            end
          end
        end

        describe 'bundles of a plugin folder' do
          let(:home) { Dir.mktmpdir }
          let(:folder) { Dir.mktmpdir }

          after do
            FileUtils.rm_rf(home)
            FileUtils.rm_rf(folder)
          end

          # @param name     [String] Name of the bundle
          # @param manifest [Hash]   Fields of the manifest
          # @param files    [Hash]   Content of the files of the bundle, by name, inside `Aspera::Plugins::<Name>`
          def write_bundle(name, manifest, files)
            bundle = File.join(folder, name)
            FileUtils.mkdir_p(bundle)
            File.write(File.join(bundle, BundleRegistry::MANIFEST), {'name' => name, 'title' => name}.merge(manifest).to_yaml)
            files.each do |file, body|
              File.write(File.join(bundle, file), file.end_with?('.rb') ? "module Aspera\n  module Plugins\n    module #{name.snake_to_capital}\n#{body}\n    end\n  end\nend\n" : body)
            end
          end

          # @param args [Array<String>] Arguments of the command line
          # @return [Array(String, String, Process::Status)] Output, error output and status of `ascli` with the plugin folder
          def run_cli(*args)
            cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Cli::Info::CMD_NAME), *args, "--plugin-folder=#{folder}", '--version-check-days=0']
            Open3.capture3({'ASCLI_HOME' => home}, *cmd)
          end

          before do
            write_bundle('spec_bundle_mounter', {'mounts' => [{'target' => 'config', 'file' => 'mount.rb', 'module' => 'Mount'}]}, 'mount.rb' => <<~RUBY)
              module Mount
                def self.included(base)
                  base.option(:spec_mounted_option, description: 'Option of a mount')
                  base.class_exec do
                    command :spec_mounted, description: 'Mounted command', action: ->(**) { Aspera::Cli::Result::Text.new("mounted \#{options.get_option(:spec_mounted_option)}") }
                  end
                end
              end
            RUBY
            entry = {'name' => 'spec_user', 'short' => 'u', 'file' => 'agent.rb', 'class' => 'Agent', 'options_schema' => 'agent_options.yaml'}
            write_bundle(
              'spec_bundle_agent', {'depends' => %w[xfer], 'extensions' => {'agent' => [entry]}},
              'agent.rb'           => 'class Agent; end',
              'agent_options.yaml' => {'type' => 'object', 'properties' => {'color' => {'type' => 'string'}}}.to_yaml
            )
          end

          it 'mount commands and options on config' do
            stdout, stderr, status = run_cli('config', 'spec_mounted', '--spec-mounted-option=yes')
            expect(status.exitstatus).to(eq(0), stderr)
            expect(stdout).to(eq("mounted yes\n"))
          end

          it 'provide agents, known when option transfer is read, also in its Hash form checked with the schema of the entry' do
            stdout, stderr, status = run_cli('config', 'agents', 'list', '--format=csv', '--fields=name,short', '--transfer=@json:{"agent":"spec_user","color":"blue"}')
            expect(status.exitstatus).to(eq(0), stderr)
            expect(stdout.lines(chomp: true)).to(include('spec_user,u'))
            _, stderr, status = run_cli('config', 'echo', 'x', '--transfer=@json:{"agent":"spec_user","color":1}')
            expect(status.exitstatus).not_to(eq(0))
            expect(stderr).to(include('/color` is not a string'))
          end
        end
      end
    end
  end
end
