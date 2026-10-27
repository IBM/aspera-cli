# frozen_string_literal: true

# cspell:ignore COMPL serv
# Shell completion scripts displayed by `config completion <shell>`, and the commands they call.
# The Bash and PowerShell scripts are executed with `bash` and `pwsh`, if available.

require 'aspera/cli/runner'
require 'aspera/cli/plugins/config'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'tmpdir'

module Aspera
  module Cli
    RSpec.describe(Plugins::Config) do
      completion_folder = described_class.const_get(:COMPLETION_FOLDER)
      # Path of executable in PATH, or nil
      executable = ->(name) { ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }.find { |f| File.executable?(f) } }

      # @return [String] root folder of this source tree
      def source_root
        File.expand_path('..', __dir__)
      end

      # Locale forced in the executed command, so that the output (Unicode characters, see `Environment.char`) does not depend on the actual environment
      UTF8_LOCALE = Environment::I18N_VARS.to_h { |var| [var, var.eql?('LC_ALL') ? 'en_US.UTF-8' : nil] }.freeze

      # @param command [String] sub-command of `config completion`
      # @param words   [Array<String>] words given after `--`
      # @param env     [Hash] environment variables
      # @return [Array<String>] lines of output
      def run_completion(command, *words, env: {})
        cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Info::CMD_NAME), 'config', 'completion', command]
        cmd += ['--', *words] unless words.empty?
        output, status = Open3.capture2e(UTF8_LOCALE.merge(env), *cmd, binmode: true)
        output.force_encoding(Encoding::UTF_8)
        expect(status.exitstatus).to(eq(0), output)
        output.lines.map(&:chomp)
      end

      # Execute the block with `ascli` of this source tree in `PATH`, as called by completion scripts
      # @yieldparam env [Hash] environment variables
      def with_ascli_in_path
        Dir.mktmpdir do |dir|
          wrapper = File.join(dir, Info::CMD_NAME)
          File.write(wrapper, %Q(#!/bin/sh\nexec "#{RbConfig.ruby}" -I"#{source_root}/lib" "#{source_root}/bin/#{Info::CMD_NAME}" "$@"\n))
          File.chmod(0o755, wrapper)
          yield({'PATH' => [dir, ENV.fetch('PATH', '')].join(File::PATH_SEPARATOR)})
        end
      end

      described_class.const_get(:COMPLETION_SHELLS).each do |shell, extension|
        it "has a completion script and command for #{shell}" do
          expect(File).to(exist(File.join(completion_folder, "#{Info::CMD_NAME}.#{extension}")))
          expect(described_class.command_registry.children_of(%i[completion])).to(include(shell))
        end
      end

      describe 'completion words action' do
        def run_words(*words, env: {})
          run_completion('words', *words, env: env)
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
          expect(run_words('config', 'ascp', 'schema')).to(eq(%w[connect desktop direct httpgw node transferd]))
        end

        it 'proposes placeholder for positional arguments with type' do
          expect(run_words('config', 'preset', 'show')).to(eq(['<identifier>']))
          expect(run_words('config', 'preset', 'get', 'mypreset')).to(eq(['<String>']))
          expect(run_words('config', 'vault', 'create')).to(eq(['<Hash> label*, username, password, url, description']))
          expect(run_words('config', 'vault', 'import')).to(eq(['<Array>']))
        end

        it 'skips values of options given in a separate word' do
          expect(run_words('server', '--url', 'https://x', 'ls')).to(eq(['<String>']))
          expect(run_words('--format', 'json', 'server')).to(include('ls', 'upload'))
          expect(run_words('-P', 'mypreset', 'server')).to(include('ls', 'upload'))
        end

        it 'joins option and value split on = by bash' do
          expect(run_words('--format', '=')).to(eq(%w[text nagios ruby json jsonpp yaml table csv image]))
          expect(run_words('--format', '=', 'json', 'server')).to(include('ls', 'upload'))
        end

        it 'proposes the arguments of an intermediate command before its sub-commands' do
          expect(run_words('node', 'access_keys', 'do')).to(eq(['<identifier>']))
          expect(run_words('node', 'access_keys', 'do', 'myid')).to(include('ls', 'upload', 'permission'))
          expect(run_words('node', 'access_keys', 'do', 'myid', 'ls')).to(eq(['<String>']))
        end

        it 'does not propose deprecated options' do
          expect(run_words).not_to(include('--display', '--output', '--table-style', '--flat-hash'))
        end

        it 'proposes nothing after an unknown word' do
          expect(run_words('nope')).to(eq([]))
          expect(run_words('server', 'nope')).to(eq([]))
          expect(run_words('config', 'preset', 'get', 'a', 'b')).to(eq([]))
        end

        it 'does not evaluate extended values in words' do
          expect(run_words('@env:COMPLETION_TEST_WORD', env: {'COMPLETION_TEST_WORD' => 'server'})).to(eq([]))
        end

        it 'accepts a unique prefix of plugin, command or alias, and proposes aliases' do
          expect(run_words('serv')).to(include('ls', 'browse', 'rm', 'delete'))
          expect(run_words('serv', 'br')).to(eq(['<String>']))
          expect(run_words('conf', 'pres', 'sh')).to(eq(['<identifier>']))
        end
      end

      describe 'completion candidates action' do
        def run_candidates(*words, env: {})
          run_completion('candidates', *words, env: env)
        end

        it 'lists candidates with their description, then the directive' do
          lines = run_candidates('server', '')
          expect(lines).to(include("upload\tUpload files to server", "ls\tList files", "browse\tList files"))
          expect(lines.last).to(eq(':'))
        end

        it 'proposes all options for a word at cursor starting with a dash' do
          words = run_candidates('server', 'ls', '-')[0..-2].map { |l| l.split("\t").first }
          expect(words).to(include('--url', '--username', '--format'))
          expect(words).to(all(start_with('--')))
        end

        it 'proposes the values of an option with its prefix' do
          expect(run_candidates('--format=j')).to(eq(%w[text nagios ruby json jsonpp yaml table csv image].map { |v| "--format=#{v}" } + [':']))
        end

        it 'gives the type of an expected value as hint' do
          expect(run_candidates('config', 'preset', 'show', '')).to(eq([':hint <identifier>']))
          expect(run_candidates('server', '--url=')).to(eq([':hint <String>']))
        end

        it 'asks for local files after the arguments of an upload' do
          expect(run_candidates('server', 'upload', '')).to(eq([':files']))
          expect(run_candidates('aoc', 'packages', 'send', '')).to(eq([':hint <Hash> name*, workspace_id*, archived, bcc_recipients, …']))
          expect(run_candidates('aoc', 'packages', 'send', '@json:{}', '')).to(eq([':files']))
        end

        it 'does not evaluate extended values in words' do
          expect(run_candidates('@env:COMPLETION_TEST_WORD', '', env: {'COMPLETION_TEST_WORD' => 'server'})).to(eq([':']))
        end

        it 'proposes the keys of an option with dotted notation, from its schema' do
          expect(run_candidates('--ts.dir')).to(include("--ts.direction\tDirection of transfer (on client side)"))
          expect(run_candidates('--out.table.')).to(include(start_with("--out.table.pivot\t")))
        end

        it 'proposes the values of a key of an option, from its schema' do
          expect(run_candidates('--ts.direction=')).to(eq(['--ts.direction=send', '--ts.direction=receive', ':']))
          expect(run_candidates('--ts.direction', '')).to(eq(%w[send receive :]))
          expect(run_candidates('--ts.target_rate_kbps', '')).to(eq([':hint <Integer> Specifies desired speed for the transfer']))
        end

        it 'gives the keys of the schema of a structure, required ones first' do
          expect(run_candidates('aoc', 'packages', 'send', '')).to(eq([':hint <Hash> name*, workspace_id*, archived, bcc_recipients, …']))
        end

        it 'proposes the end marker of a structure built with @:' do
          expect(run_candidates('aoc', 'packages', 'send', '@:', '')).to(eq([':hint <path=value> name*, workspace_id*, archived, bcc_recipients, …']))
          expect(run_candidates('aoc', 'packages', 'send', '@:', 'name=x', '')).to(eq(["END\tEnd of structure built with @:", ':']))
          expect(run_candidates('aoc', 'packages', 'send', '@:STOP', 'name=x', '')).to(eq(["STOP\tEnd of structure built with @:", ':']))
          expect(run_candidates('aoc', 'tier_restrictions', '--query=@:', 'a=b', '')).to(eq(["END\tEnd of structure built with @:", ':']))
          # Words of the structure are not arguments
          expect(run_candidates('aoc', 'packages', 'send', '@:', 'name=x', 'END', '')).to(eq([':files']))
        end
      end

      describe 'Bash completion script', :bash do
        bash = executable.call('bash')

        # @param line       [String]        command line, the cursor is at the end
        # @param comp_words [Array<String>] words as split by bash: also on characters of COMP_WORDBREAKS
        # @return [Array<String>] COMPREPLY
        def complete_bash(bash, line, comp_words)
          script = <<~BASH
            source #{Shellwords.escape(File.join(source_root, 'lib/aspera/cli/completion', "#{Info::CMD_NAME}.bash"))}
            COMP_LINE=#{Shellwords.escape(line)}
            COMP_POINT=${#COMP_LINE}
            COMP_WORDS=(#{comp_words.map { |w| Shellwords.escape(w) }.join(' ')})
            COMP_CWORD=#{comp_words.length - 1}
            _ascli_complete
            printf '%s\n' "${COMPREPLY[@]}"
          BASH
          with_ascli_in_path do |env|
            output, status = Open3.capture2e(env, bash, '--norc', '--noprofile', '-c', script, chdir: source_root)
            expect(status).to(be_success, output)
            return output.lines.map(&:chomp)
          end
        end

        before { skip('bash not found') if bash.nil? || Environment.instance.os.eql?(Environment::OS_WINDOWS) }

        it 'completes a word' do
          expect(complete_bash(bash, 'ascli serv', %w[ascli serv])).to(eq(['server']))
          expect(complete_bash(bash, 'ascli serv br', %w[ascli serv br])).to(eq(['browse']))
        end

        it 'completes the value of an option, with words split on = and :' do
          expect(complete_bash(bash, 'ascli --format=js', %w[ascli --format = js])).to(eq(%w[json jsonpp]))
          expect(complete_bash(bash, 'ascli server --url=https://h:443 l', %w[ascli server --url = https : //h : 443 l])).to(eq(['ls']))
        end

        it 'completes the end marker of a structure built with @:, split on @ and :' do
          expect(complete_bash(bash, 'ascli aoc packages send @: name=x ', ['ascli', 'aoc', 'packages', 'send', '@', ':', 'name', '=', 'x', ''])).to(eq(['END']))
        end

        it 'displays a hint without inserting it' do
          expect(complete_bash(bash, 'ascli config preset show ', ['ascli', 'config', 'preset', 'show', ''])).to(eq(['<identifier>', ' ']))
        end

        it 'completes local files where expected' do
          expect(complete_bash(bash, 'ascli server upload READ', %w[ascli server upload READ])).to(include('README.md'))
        end
      end

      describe 'PowerShell completion script', :powershell do
        pwsh = executable.call('pwsh')

        it 'completes commands at any depth, option values, and displays hints' do
          skip('pwsh not found') if pwsh.nil?
          skip('ascli wrapper is a shell script') if Environment.instance.os.eql?(Environment::OS_WINDOWS)
          # Activated as documented, then one line of completions per command line, with the cursor at the end (the word completed is compared without case)
          script = <<~PS1
            ascli config completion powershell | Out-String | Invoke-Expression
            foreach ($line in 'ascli conf', 'ascli config completion ', 'ascli config COMPL', 'ascli --format=js', 'ascli config preset show ', 'ascli --ts.dire', "ascli aoc packages send '@:' name=x ") {
                $matches = (TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches
                ($matches.CompletionText -join ' ') + '|' + ($matches.ListItemText -join ' ')
            }
          PS1
          with_ascli_in_path do |env|
            output, status = Open3.capture2e(env, pwsh, '-NoProfile', '-NonInteractive', '-Command', script)
            expect(status).to(be_success, output)
            lines = output.lines.map(&:chomp)
            expect(lines[0]).to(eq('config|config'))
            expect(lines[1].split('|').first.split).to(include('words', 'candidates', 'bash', 'powershell'))
            expect(lines[2]).to(eq('completion|completion'))
            expect(lines[3]).to(eq('--format=json --format=jsonpp|--format=json --format=jsonpp'))
            # Not changed, so that no file path is completed
            expect(lines[4]).to(eq(' |<identifier>'))
            expect(lines[5]).to(eq('--ts.direction|--ts.direction'))
            # Quoted word, as required for @: in PowerShell
            expect(lines[6]).to(eq('END|END'))
          end
        end
      end
    end
  end
end
