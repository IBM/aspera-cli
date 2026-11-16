# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/cli/runner'

module Aspera
  module Cli
    RSpec.describe(Runner) do
      describe '#schema_help_lines' do
        # Fixed rendering, whatever the terminal running the tests: no colors, ASCII borders, no wrapping
        around do |example|
          colors = Rainbow.enabled
          Rainbow.enabled = false
          example.run
        ensure
          Rainbow.enabled = colors
        end

        before do
          allow(Environment).to(receive_messages(terminal_supports_unicode?: false, terminal_columns: nil))
        end

        it 'renders the properties of a Hash argument schema' do
          argument = ArgumentSpec.new(
            name: :mcp_options,
            type: [Hash],
            schema: 'opts:components.schemas.McpServerOptions'
          )

          lines = Runner.new([]).send(:schema_help_lines, argument)

          output = lines.join("\n")
          expect(output).to(include('| transport '))
          expect(output).to(include('Allowed values: '))
          expect(output).to(include('stdio'))
        end

        it 'renders the title of variants, prefixed by the discriminant value' do
          argument = ArgumentSpec.new(
            name: :action,
            type: [Hash],
            schema: Schema::Registry.req_body(Schema::Registry::AUTOMATION, 'actions.post')
          )

          output = Runner.new([]).send(:schema_help_lines, argument).join("\n")
          expect(output).to(include('| transfer: Creates a new action to send a file or folder '))
          expect(output).to(include('| api: Creates a new action that calls an API '))
          expect(output).not_to(include('&nbsp;'))
        end
      end

      describe '#schema_documentation' do
        it 'documents required fields, agents and ascp options of the transfer spec' do
          rows = Runner.new([]).send(:schema_documentation, Schema::Registry::TRANSFER_SPEC).rows
          direction = rows.find { |row| row['name'].eql?('direction') }
          expect(direction['description']).to(include('Required.'))
          expect(direction['description'].last).to(include('--mode'))
          expect(rows.map { |row| row['name'] }).not_to(include('fasp_url'))
        end
      end

      describe '#option_ui=' do
        let(:runner) { Runner.new([]) }
        let(:environment) { Environment.instance }

        around do |example|
          saved = [environment.url_method, environment.browser_command, environment.web_auth]
          example.run
        ensure
          environment.url_method, environment.browser_command, environment.web_auth = saved
        end

        it 'sets web_auth' do
          runner.send(:option_ui=, {web_auth: 'paste'})
          expect(environment.web_auth).to(eq(:paste))
          runner.send(:option_ui=, {web_auth: 'port'})
          expect(environment.web_auth).to(eq(:port))
        end

        it 'rejects an unknown web_auth' do
          expect { runner.send(:option_ui=, {web_auth: 'bad'}) }.to(raise_error(BadArgument))
        end

        {
          'text'      => :text,
          'terminal'  => :text,
          'graphical' => :graphical,
          'browser'   => :graphical
        }.each do |mode, method|
          it "maps mode #{mode} to #{method}" do
            runner.send(:option_ui=, {mode: mode})
            expect(environment.url_method).to(eq(method))
          end
        end

        it 'maps mode auto to the default mode' do
          runner.send(:option_ui=, {mode: 'auto'})
          expect(environment.url_method).to(eq(environment.default_gui_mode))
        end

        it 'sets the browser command' do
          runner.send(:option_ui=, {command: ['my_browser', '--flag']})
          expect(environment.browser_command).to(eq(['my_browser', '--flag']))
        end

        it 'clears the browser command with an empty array' do
          runner.send(:option_ui=, {command: ['x']})
          runner.send(:option_ui=, {command: []})
          expect(environment.browser_command).to(be_nil)
        end

        it 'rejects an unknown mode' do
          expect { runner.send(:option_ui=, {mode: 'bad'}) }.to(raise_error(BadArgument))
        end

        it 'rejects an unknown sub-option' do
          expect { runner.send(:option_ui=, {other: 'x'}) }.to(raise_error(BadArgument))
        end
      end

      describe '#option_temp=' do
        let(:runner) { Runner.new([]) }
        let(:manager) { TempFileManager.instance }

        around do |example|
          saved = [manager.global_temp, manager.cleanup_on_exit, manager.expiry_sec]
          example.run
        ensure
          manager.global_temp, manager.cleanup_on_exit, manager.expiry_sec = saved
        end

        it 'sets the folder' do
          runner.send(:option_temp=, {'folder' => '/tmp/x'})
          expect(manager.global_temp).to(eq('/tmp/x'))
        end

        it 'sets clean' do
          runner.send(:option_temp=, {'clean' => false})
          expect(manager.cleanup_on_exit).to(be(false))
        end

        {
          '30d'    => 2_592_000,
          '1h 30m' => 5_400,
          3600     => 3600,
          0        => 0,
          false    => nil,
          nil      => nil
        }.each do |expiry, seconds|
          it "maps expiry #{expiry.inspect} to #{seconds.inspect}" do
            runner.send(:option_temp=, {'expiry' => expiry})
            expect(manager.expiry_sec).to(eq(seconds))
          end
        end

        it 'rejects an invalid expiry' do
          expect { runner.send(:option_temp=, {'expiry' => '5x'}) }.to(raise_error(BadArgument, /Invalid duration/))
        end

        it 'rejects an unknown sub-option' do
          expect { runner.send(:option_temp=, {other: 'x'}) }.to(raise_error(BadArgument))
        end
      end

      describe '#display_schema' do
        let(:runner) { Runner.new([]) }
        let(:formatter) { instance_double(Formatter, display_results: nil) }

        before { runner.context.formatter = formatter }

        it 'displays the documentation of the schema in 3 columns' do
          runner.send(:display_schema, 'opts:components.schemas.McpServerOptions')
          expect(formatter).to(have_received(:display_results).with(
            an_object_satisfying { |result| result.is_a?(Result::ObjectList) && result.fields.eql?(%w[name type description]) }
          ))
        end

        it 'warns and displays nothing without schema' do
          allow(Log.log).to(receive(:warn))
          runner.send(:display_schema, nil)
          expect(Log.log).to(have_received(:warn))
          expect(formatter).not_to(have_received(:display_results))
        end
      end

      describe '#run: unprocessed values after an error' do
        # Error messages logged by a complete execution of the command line
        def logged_errors(*argv)
          messages = []
          allow(Log.log).to(receive(:error)) { |*args, &block| messages.push(block ? block.call : args.first) }
          Dir.mktmpdir do |home|
            # Home folder by env var: an option on command line may not be consumed yet when the error occurs
            stub_const('ENV', ENV.to_h.merge('ASCLI_HOME' => home))
            expect { Runner.new(argv).run }.to(raise_error(SystemExit))
          end
          messages
        end

        %w[ascp-logs temp ui].each do |name|
          it "reports only the schema error for an unknown key of --#{name}" do
            messages = logged_errors('config', 'ascp', 'logs', 'summary', "--#{name}.foo=1")
            expect(messages.size).to(eq(1))
            expect(messages.first).to(include('is a disallowed additional property'))
          end
        end

        it 'does not change the message of an error on a normal option' do
          messages = logged_errors('config', 'ascp', 'logs', 'summary', '--format=foo')
          expect(messages.first).to(start_with('Argument: unknown value for format: foo'))
          expect(messages.size).to(eq(1))
        end

        it 'still reports unprocessed values without error' do
          expect(logged_errors('config', 'echo', '1', '2')).to(eq(['Argument: unprocessed values: ["2"]']))
        end
      end

      describe '.result_transfer' do
        it 'raises on an unexpected result type' do
          expect { Runner.result_transfer('done') }.to(raise_error(/Unexpected transfer result type: String/))
        end
      end

      describe '.result_transfer_multiple' do
        it 'converts each status to text' do
          table = [
            {'id' => 1, Runner::STATUS_FIELD => Transfer::Result::Success.new},
            {'id' => 2, Runner::STATUS_FIELD => Transfer::Result::Async.new(job_id: 'j1')},
            {'id' => 3, Runner::STATUS_FIELD => 'other'}
          ]
          expect(Runner.result_transfer_multiple(table).data.map { |item| item[Runner::STATUS_FIELD] }).to(eq(%w[success async:j1 other]))
        end
      end

      describe '#option_log=' do
        it 'sets the logger type and format' do
          allow(Log.instance).to(receive(:logger_type=))
          allow(Log.instance).to(receive(:formatter=))
          Runner.new([]).send(:option_log=, {'type' => 'stdout', 'format' => 'standard'})
          expect(Log.instance).to(have_received(:logger_type=).with(:stdout))
          expect(Log.instance).to(have_received(:formatter=).with('standard'))
        end
      end

      context 'with a temporary home folder' do
        let(:home) { Dir.mktmpdir }

        before do
          stub_const('ENV', ENV.to_h.merge('ASCLI_HOME' => home))
          allow(Log.log).to(receive_messages(warn: nil, info: nil))
        end

        after { FileUtils.rm_rf(home) }

        describe '#run_with_result: help of a leaf command' do
          def help(*argv) = Runner.new(argv + ['-h']).run_with_result.data

          it 'shows typed arguments' do
            text = help('config', 'preset', 'get')
            expect(text).to(include('COMMAND: config preset get <name> <param_name>'))
            expect(text).to(match(/ARGUMENTS:\n +name +identifier\n +param_name +String/))
          end

          it 'shows the schema of a Hash argument' do
            text = help('config', 'preset', 'lookup')
            expect(text).to(include('(schema shown below)'))
            expect(text).to(include('SCHEMA: criteria'))
          end

          it 'shows the file list of upload and download commands' do
            expect(help('node', 'upload', '--url=https://localhost')).to(include('[source_file]...  Source file(s) to upload'))
            expect(help('node', 'download', '--url=https://localhost')).to(include('[source_file]...  Remote path(s) to download'))
          end

          it 'lists plugins without command' do
            expect(Runner.new(['-h']).run_with_result.data).to(match(/PLUGINS\n.* node +/m))
            expect(Runner.new(['help']).run_with_result.data).to(match(/PLUGINS\n.* node +/m))
          end

          it 'shows an argument with several types' do
            expect(help('node', 'access_keys', 'do', 'self', 'find', '--url=https://localhost')).to(include('[filter]  File name filter'))
          end

          it 'gives a tip for list commands with a query schema' do
            expect(help('faspex5', 'admin', 'workgroups', 'list', '--url=https://localhost')).to(include('TIP: use --query=help'))
          end
        end

        describe '#show_usage' do
          it 'displays the help and exits with success' do
            runner = Runner.new([])
            runner.send(:init_agents_and_options)
            formatter = instance_double(Formatter, display_message: nil)
            runner.context.formatter = formatter
            expect { runner.show_usage }.to(raise_error(SystemExit) { |e| expect(e.status).to(eq(0)) })
            expect(formatter).to(have_received(:display_message).with(:error, /PLUGINS/))
          end
        end

        describe '#run_with_result: lock port' do
          it 'does not execute the command if another instance holds the port' do
            warnings = []
            allow(Log.log).to(receive(:warn)) { |*args, &block| warnings.push(block ? block.call : args.first) }
            server = TCPServer.new('127.0.0.1', 0)
            port = server.addr[1]
            expect(Runner.new(['config', 'echo', 'hello', "--lock-port=#{port}"]).run_with_result).to(be_nil)
            expect(warnings).to(include(/Another instance is already running/))
          ensure
            server&.close
          end
        end

        describe '#run' do
          it 'exits with code interrupted on Ctrl-C' do
            runner = Runner.new(%w[config echo hello])
            runner.context.formatter = instance_double(Formatter, display_message: nil, format_type: :table)
            allow(runner).to(receive(:run_with_result).and_raise(Interrupt))
            allow(Log.log).to(receive(:error))
            expect { runner.run }.to(raise_error(SystemExit) { |e| expect(e.status).to(eq(ExitCode::INTERRUPTED)) })
          end

          it 'displays the full exception in debug mode' do
            runner = Runner.new(%w[config echo hello])
            runner.context.formatter = instance_double(Formatter, display_message: nil, format_type: :table)
            allow(runner).to(receive(:run_with_result).and_raise(Cli::Error, 'failure'))
            allow(Log.log).to(receive_messages(error: nil, debug?: true))
            expect { expect { runner.run }.to(raise_error(SystemExit)) }.to(output(/failure/).to_stderr)
          end
        end
      end

      describe 'free-form schema' do
        let(:schema) { 'opts:components.schemas.OrchestratorInitiateParameters' }

        it 'is displayed as its description' do
          runner = Runner.new([])
          formatter = instance_double(Formatter, display_message: nil)
          runner.context.formatter = formatter
          runner.send(:display_schema, schema)
          expect(formatter).to(have_received(:display_message).with(:data, String))
        end

        it 'is shown as its description in the help of an argument' do
          lines = Runner.new([]).send(:schema_help_lines, ArgumentSpec.new(name: :params, type: [Hash], schema: schema))
          expect(lines.first).to(include('SCHEMA: params'))
        end
      end
    end
  end
end
