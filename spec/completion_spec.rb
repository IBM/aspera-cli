# frozen_string_literal: true

# cspell:ignore COMPL serv
# Shell completion scripts displayed by `config completion <shell>`, and the commands they call.
# The Bash and PowerShell scripts are executed with `bash` and `pwsh`, if available.

require 'aspera/cli/runner'
require 'aspera/cli/plugins/config'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'tmpdir'
require 'yaml'

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

      # Home folder of the executed command: a configuration file with preset `mypreset`
      before(:all) do
        @home = Dir.mktmpdir
        File.write(File.join(@home, 'config.yaml'), {'config' => {'version' => Cli::VERSION}, 'mypreset' => {'url' => 'https://example.com', 'username' => 'myuser'}}.to_yaml)
      end

      after(:all) { FileUtils.remove_entry(@home) }

      # @param command [String] sub-command of `config completion`
      # @param words   [Array<String>] words given after `--`
      # @param env     [Hash] environment variables
      # @return [Array<String>] lines of output
      def run_completion(command, *words, env: {})
        cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Info::CMD_NAME), 'config', 'completion', command]
        cmd += ['--', *words] unless words.empty?
        output, status = Open3.capture2e(UTF8_LOCALE.merge('ASCLI_HOME' => @home).merge(env), *cmd, binmode: true)
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
          yield({'PATH' => [dir, ENV.fetch('PATH', '')].join(File::PATH_SEPARATOR), 'ASCLI_HOME' => @home})
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
          expect(run_words('node', 'access_keys', 'do')).to(eq(['<identifier>']))
          expect(run_words('config', 'preset', 'set', 'mypreset', 'url')).to(eq(['<String>']))
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
          expect(run_words('conf', 'pres', 'sh')).to(include('mypreset'))
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
          expect(run_candidates('node', 'access_keys', 'do', '')).to(eq([':hint <identifier>']))
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

        it 'proposes the keys of an option with dotted notation, from its schema, followed by = or .' do
          expect(run_candidates('--ts.dir')).to(include("--ts.direction=\tDirection of transfer (on client side)"))
          expect(run_candidates('--out.t')).to(include(start_with("--out.table.\t"), start_with("--out.format=\t")))
          expect(run_candidates('--out.table.')).to(include(start_with("--out.table.pivot=\t")))
        end

        it 'proposes the keys of option query from the schema of the command' do
          expect(run_candidates('faspex5', 'admin', 'accounts', 'list', '--query.')).to(include(start_with("--query.limit=\t")))
          expect(run_candidates('faspex5', 'admin', 'accounts', 'list', '--query.expand=')).to(eq(['--query.expand=true', '--query.expand=false', ':']))
        end

        it 'proposes the values of the key given by a plain value of an option' do
          expect(run_candidates('--ui=')).to(include('--ui=terminal', '--ui=browser'))
          expect(run_candidates('--transfer=')).to(include('--transfer=direct', '--transfer=node'))
          expect(run_candidates('--temp=')).to(eq([':folders --temp=']))
        end

        it 'proposes the values of a key of an option, from its schema' do
          expect(run_candidates('--ts.direction=')).to(eq(['--ts.direction=send', '--ts.direction=receive', ':']))
          expect(run_candidates('--ts.direction', '')).to(eq(%w[send receive :]))
          expect(run_candidates('--ts.target_rate_kbps', '')).to(eq([':hint <Integer> Specifies desired speed for the transfer']))
        end

        it 'gives the keys of the schema of a structure, required ones first' do
          expect(run_candidates('aoc', 'packages', 'send', '')).to(eq([':hint <Hash> name*, workspace_id*, archived, bcc_recipients, …']))
        end

        it 'proposes the keys of a structure built with @:, required ones first, then its end marker' do
          lines = run_candidates('aoc', 'packages', 'send', '@:', '')
          expect(lines.first(2)).to(eq(["name=\tPackage name (required)", "workspace_id=\tThe ID of the workspace from which this package was sent (required)"]))
          expect(lines).to(include(start_with("archived=\t"), start_with("recipients.0.\t")))
          expect(lines).not_to(include(start_with('END')))
          lines = run_candidates('aoc', 'packages', 'send', '@:', 'name=x', '')
          expect(lines.first).to(eq("END\tEnd of structure built with @:"))
          expect(lines).to(include(start_with("workspace_id=\t")))
          expect(lines).not_to(include(start_with('name=')))
          expect(run_candidates('aoc', 'packages', 'send', '@:', 'recipients.0.')).to(include(start_with("recipients.0.id=\t")))
          expect(run_candidates('aoc', 'packages', 'send', '@:STOP', 'name=x', '').first).to(eq("STOP\tEnd of structure built with @:"))
          # Without schema: end marker only
          expect(run_candidates('aoc', 'tier_restrictions', '--query=@:', 'a=b', '')).to(eq(["END\tEnd of structure built with @:", ':']))
          # Words of the structure are not arguments
          expect(run_candidates('aoc', 'packages', 'send', '@:', 'name=x', 'END', '')).to(eq([':files']))
        end

        it 'proposes the values of a key of a structure built with @:' do
          expect(run_candidates('aoc', 'packages', 'send', '@:', 'archived=')).to(eq(['archived=true', 'archived=false', ':']))
          expect(run_candidates('aoc', 'packages', 'send', '@:', 'name=')).to(eq([':hint <String> Package name']))
        end

        it 'proposes extended value modifiers, and the values they read' do
          lines = run_candidates('--ts=@')
          expect(lines).to(include("--ts=@json:\tDecode JSON", "--ts=@file:\tContent of local file", start_with("--ts=@:\t"), start_with("--ts=@preset:\t")))
          expect(run_candidates('--ts=@json:')).to(include(start_with("--ts=@json:@file:\t")))
          expect(run_candidates('--private-key=@file:')).to(eq([':files --private-key=@file:']))
          expect(run_candidates('config', 'echo', '@json:@file:')).to(eq([':files @json:@file:']))
          expect(run_candidates('--ts=@preset:')).to(include('--ts=@preset:mypreset'))
          expect(run_candidates('--ts=@preset:mypreset.')).to(include('--ts=@preset:mypreset.url', '--ts=@preset:mypreset.username'))
          expect(run_candidates('--password=@env:', env: {'COMPLETION_TEST_VAR' => 'x'})).to(include('--password=@env:COMPLETION_TEST_VAR'))
          expect(run_candidates('--password=@val:@')).to(eq([":hint #{ExtendedValue.instance.description(:val)}"]))
          # Argument not evaluated as extended value
          expect(run_candidates('config', 'completion', 'words', '@')).to(eq([':hint <String>']))
        end

        it 'asks for local files or folders where a path is expected' do
          expect(run_candidates('config', 'genkey', '')).to(eq([':files']))
          expect(run_candidates('--pid-file=')).to(eq([':files --pid-file=']))
          expect(run_candidates('--out.file=')).to(eq([':files --out.file=']))
          expect(run_candidates('--temp.folder=')).to(eq([':folders --temp.folder=']))
          # Destination of a download is local, of an upload remote
          expect(run_candidates('server', 'download', '--to-folder', '')).to(eq([':folders']))
          expect(run_candidates('server', 'upload', '--to-folder', '')).to(eq([':hint <String>']))
          # Remote path
          expect(run_candidates('server', 'ls', '')).to(eq([':hint <String>']))
        end

        it 'proposes presets, and their parameters' do
          expect(run_candidates('-P', '')).to(include('mypreset'))
          expect(run_candidates('config', 'preset', 'show', '')).to(include('mypreset'))
          expect(run_candidates('config', 'preset', 'get', 'mypreset', '')).to(eq(%w[url username :]))
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
          expect(complete_bash(bash, 'ascli aoc packages send @: name=x E', %w[ascli aoc packages send @ : name = x E])).to(eq(['END']))
        end

        it 'displays a hint without inserting it' do
          expect(complete_bash(bash, 'ascli node access_keys do ', ['ascli', 'node', 'access_keys', 'do', ''])).to(eq(['<identifier>', ' ']))
        end

        it 'completes local files where expected' do
          expect(complete_bash(bash, 'ascli server upload READ', %w[ascli server upload READ])).to(include('README.md'))
        end

        it 'completes local paths after the beginning of a word, split on = @ and :' do
          expect(complete_bash(bash, 'ascli --private-key=@file:READ', %w[ascli --private-key = @ file : READ])).to(eq(['README.md']))
          expect(complete_bash(bash, 'ascli --temp=li', %w[ascli --temp = li])).to(eq(['lib']))
        end

        it 'completes extended value modifiers and keys of structures' do
          # Readline replaces the word with `@`, a word break character that it keeps in the word (special prefix)
          expect(complete_bash(bash, 'ascli --ts=@js', %w[ascli --ts = @ js])).to(eq(['@json:']))
          expect(complete_bash(bash, 'ascli config echo @file:READ', %w[ascli config echo @ file : READ])).to(eq(['README.md']))
          expect(complete_bash(bash, 'ascli aoc packages send @: arch', %w[ascli aoc packages send @ : arch])).to(eq(['archived=']))
        end
      end

      describe 'Fish completion script', :fish do
        fish = executable.call('fish')

        it 'completes words, option values, extended value modifiers and local paths' do
          skip('fish not found') if fish.nil?
          # Activated as documented, then one line of completions per command line, with the cursor at the end, without descriptions
          script = <<~FISH
            ascli config completion fish | source
            for line in 'ascli serv' 'ascli --format=js' 'ascli --ts=@js' 'ascli --private-key=@file:READ' 'ascli --temp=li'
                # `string join` fails when given a single word
                complete --do-complete "$line" | string replace -r '\\t.*' '' | string join ' '; or true
            end
          FISH
          with_ascli_in_path do |env|
            output, status = Open3.capture2e(env, fish, '--no-config', '-c', script, chdir: source_root)
            expect(status).to(be_success, output)
            expect(output.lines.map(&:chomp)).to(eq(['server', '--format=json --format=jsonpp', '--ts=@json:', '--private-key=@file:README.md', '--temp=lib/']))
          end
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
            foreach ($line in 'ascli conf', 'ascli config completion ', 'ascli config COMPL', 'ascli --format=js', 'ascli node access_keys do ', 'ascli --ts.dire', "ascli aoc packages send '@:' name=x ", "ascli config echo '@js", "ascli config echo '@file:READ", 'ascli --private-key=@file:READ') {
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
            expect(lines[5]).to(eq('--ts.direction=|--ts.direction='))
            # Quoted word, as required for @: in PowerShell
            expect(lines[6].split('|').first.split).to(include('END', 'workspace_id='))
            # A word starting with @ is quoted: else it is splatting
            expect(lines[7]).to(eq("'@json:'|@json:"))
            # Local files after the beginning of the word
            expect(lines[8]).to(eq("'@file:README.md'|README.md"))
            expect(lines[9]).to(eq('--private-key=@file:README.md|README.md'))
          end
        end
      end
    end
  end
end
