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

      describe 'PowerShell completion script' do
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
