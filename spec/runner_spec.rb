# frozen_string_literal: true

require 'aspera/cli/runner'

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

        it 'renders the title of variants without discriminant' do
          argument = ArgumentSpec.new(
            name: :action,
            type: [Hash],
            schema: Schema::Registry.req_body(Schema::Registry::AUTOMATION, 'actions.post')
          )

          output = Runner.new([]).send(:schema_help_lines, argument).join("\n")
          expect(output).to(include('| Creates a new action to send a file or folder '))
          expect(output).to(include('| Creates a new action that calls an API '))
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
          saved = [environment.url_method, environment.browser_command]
          example.run
        ensure
          environment.url_method, environment.browser_command = saved
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
    end
  end
end
