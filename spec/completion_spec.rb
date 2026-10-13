# frozen_string_literal: true

# Shell completion scripts displayed by `config completion <shell>`.
# The PowerShell script is executed with `pwsh`, if available.

require 'aspera/cli/runner'
require 'aspera/cli/plugins/config'
require 'open3'
require 'rbconfig'
require 'tmpdir'

module Aspera
  module Cli
    RSpec.describe(Plugins::Config) do
      completion_folder = described_class.const_get(:COMPLETION_FOLDER)

      described_class.const_get(:COMPLETION_SHELLS).each do |shell, extension|
        it "has a completion script and command for #{shell}" do
          expect(File).to(exist(File.join(completion_folder, "#{Info::CMD_NAME}.#{extension}")))
          expect(described_class.command_registry.children_of(%i[completion])).to(include(shell))
        end
      end

      describe 'completion words action' do
        let(:root) { File.expand_path('..', __dir__) }

        def run_words(*words)
          cmd = [RbConfig.ruby, "-I#{root}/lib", File.join(root, 'bin', Info::CMD_NAME), 'config', 'completion', 'words']
          cmd += ['--', *words] unless words.empty?
          output, status = Open3.capture2e(*cmd)
          expect(status.exitstatus).to(eq(0))
          output.lines.map(&:chomp)
        end

        it 'proposes plugin names before options at root' do
          results = run_words
          expect(results).to(include('config', 'server', 'node', '--interactive', '--format', '--help'))
          expect(results).not_to(include('--ssh-keys'))
          plugin_idx = results.index('config')
          option_idx = results.index('--interactive')
          expect(plugin_idx).to(be < option_idx)
        end

        it 'proposes sub-commands before plugin options for a plugin' do
          results = run_words('server')
          expect(results).to(include('ls', 'upload', 'download', '--url', '--username', '--password', '--ssh-keys'))
          expect(results).not_to(include('--clean-temp'))
          cmd_idx = results.index('ls')
          option_idx = results.index('--url')
          expect(cmd_idx).to(be < option_idx)
        end

        it 'proposes only sub-commands under deeper paths' do
          results = run_words('aoc', 'user')
          expect(results).to(include('workspaces', 'profile', 'preferences', 'notifications', 'contacts', 'settings'))
          expect(results.none? { |r| r.start_with?('-') }).to(be(true))

          preset_results = run_words('config', 'preset')
          expect(preset_results).to(include('list', 'overview', 'delete', 'show'))
          expect(preset_results.none? { |r| r.start_with?('-') }).to(be(true))
        end

        it 'proposes allowed values for an enum option' do
          results = run_words('--format')
          expect(results).to(eq(%w[text nagios ruby json jsonpp yaml table csv image]))
        end

        it 'proposes placeholder for typed options' do
          expect(run_words('--lock-port')).to(eq(['<Integer>']))
          expect(run_words('server', '--url')).to(eq(['<String>']))
          expect(run_words('--vault')).to(eq(['<Hash>']))
        end

        it 'proposes allowed values for positional arguments with enum' do
          expect(run_words('config', 'documentation')).to(eq(%w[github local toc]))
          expect(run_words('config', 'ascp', 'schema')).to(eq(%w[desktop node direct transferd httpgw connect]))
        end

        it 'proposes placeholder for positional arguments with type' do
          expect(run_words('config', 'preset', 'show')).to(eq(['<identifier>']))
          expect(run_words('config', 'preset', 'get', 'mypreset')).to(eq(['<String>']))
          expect(run_words('config', 'vault', 'create')).to(eq(['<Hash>']))
          expect(run_words('config', 'vault', 'import')).to(eq(['<Array>']))
        end
      end

      describe 'PowerShell completion script', :powershell do
        pwsh = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'pwsh') }.find { |f| File.executable?(f) }

        it 'completes commands at any depth' do
          skip('pwsh not found') if pwsh.nil?
          skip('ascli wrapper is a shell script') if Environment.instance.os.eql?(Environment::OS_WINDOWS)
          root = File.expand_path('..', __dir__)
          Dir.mktmpdir do |dir|
            # ascli of this source tree, found in PATH by the completer
            wrapper = File.join(dir, Info::CMD_NAME)
            File.write(wrapper, %Q(#!/bin/sh\nexec "#{RbConfig.ruby}" -I"#{root}/lib" "#{root}/bin/#{Info::CMD_NAME}" "$@"\n))
            File.chmod(0o755, wrapper)
            # Activated as documented, then one line of completions per command line, with the cursor at the end (the word completed is compared without case)
            script = <<~PS1
              ascli config completion powershell | Out-String | Invoke-Expression
              foreach ($line in 'ascli conf', 'ascli config completion ', 'ascli config COMPL') {
                  (TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches.CompletionText -join ' '
              }
            PS1
            env = {'PATH' => [dir, ENV.fetch('PATH', '')].join(File::PATH_SEPARATOR)}
            output, status = Open3.capture2e(env, pwsh, '-NoProfile', '-NonInteractive', '-Command', script)
            expect(status).to(be_success, output)
            lines = output.lines.map(&:chomp)
            expect(lines[0]).to(eq('config'))
            expect(lines[1].split).to(include('words', 'bash', 'powershell'))
            expect(lines[2]).to(eq('completion'))
          end
        end
      end
    end
  end
end
