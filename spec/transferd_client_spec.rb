# frozen_string_literal: true

# Client commands of plugin `transferd` (`info`, `transfers show|cancel`): no daemon and no gem `grpc` required, the client is a fake.

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'json'
require 'aspera/cli/runner'
require 'aspera/cli/plugins/transferd'

module Aspera
  module Cli
    RSpec.describe(Plugins::Transferd) do
      let(:source_root) { File.expand_path('..', __dir__) }
      # Fake client: records the calls
      let(:fake) do
        Class.new do
          attr_reader :calls

          def initialize
            @calls = []
          end

          def info(params)
            @calls.push([:info, params])
            {'apiVersion' => 'v1', 'info' => {'managementPort' => 55_001}}
          end

          def transfer_status(transfer_id, params)
            @calls.push([:transfer_status, transfer_id, params])
            {'status' => 'running', 'bytes_transferred' => 10}
          end

          def transfer_cancel(transfer_id, params)
            @calls.push([:transfer_cancel, transfer_id, params])
            true
          end
        end.new
      end

      before { described_class.daemon_client = fake }

      after { described_class.daemon_client = nil }

      # @return [String] standard output of the command line run in this process, with the fake client
      def run_cli(*argv)
        output = nil
        Dir.mktmpdir do |home|
          stub_const('ENV', ENV.to_h.merge('ASCLI_HOME' => home))
          output = capture_stdout { Runner.new([*argv, '--format=json', '--version-check-days=0']).run }
        end
        output
      end

      def capture_stdout
        saved = $stdout
        $stdout = StringIO.new
        yield
        return $stdout.string
      ensure
        $stdout = saved
      end

      it 'gives information on the daemon, with the options url, api_key and ca_file' do
        output = run_cli('transferd', 'info', '--url=127.0.0.1:55002', '--api-key=KEY', '--ca-file=/path/ca.pem')
        expect(JSON.parse(output)).to(include('apiVersion' => 'v1'))
        expect(fake.calls).to(eq([[:info, {'url' => '127.0.0.1:55002', 'api_key' => 'KEY', 'ca_file' => '/path/ca.pem'}]]))
      end

      it 'does not need api_key and ca_file' do
        run_cli('transferd', 'info', '--url=h:1')
        expect(fake.calls).to(eq([[:info, {'url' => 'h:1'}]]))
      end

      it 'shows a transfer' do
        output = run_cli('transferd', 'transfers', 'show', 'tid', '--url=h:1')
        expect(JSON.parse(output)).to(include('status' => 'running'))
        expect(fake.calls).to(eq([[:transfer_status, 'tid', {'url' => 'h:1'}]]))
      end

      it 'cancels a transfer' do
        run_cli('transferd', 'transfers', 'cancel', 'tid', '--url=h:1')
        expect(fake.calls).to(eq([[:transfer_cancel, 'tid', {'url' => 'h:1'}]]))
      end

      it 'requires the option url' do
        expect { run_cli('transferd', 'info') }.to(raise_error(SystemExit))
        expect(fake.calls).to(be_empty)
      end

      it 'does not appear under the deprecated config transferd' do
        reg = Plugins::Config.command_registry
        expect(reg.children_of(%i[transferd]).keys).to(contain_exactly(:install, :list, :service))
      end
    end

    RSpec.describe('transferd client without the gem grpc') do
      it 'gives a clear error, only when a client command runs' do
        plugin = Plugins::Transferd.allocate
        allow(plugin).to(receive(:require).with('aspera/agent/transferd').and_raise(LoadError, 'cannot load such file -- grpc'))
        expect { plugin.send(:daemon_client) }.to(raise_error(Cli::Error, /gem install grpc/))
      end

      it 'does not load grpc for the local commands' do
        source_root = File.expand_path('..', __dir__)
        script = <<~RUBY
          require 'aspera/cli/runner'
          ARGV.replace(%w[transferd service spec --format=json --version-check-days=0])
          at_exit { $stderr.puts("GRPC=\#{defined?(::GRPC).inspect} AGENT=\#{$LOADED_FEATURES.any? { |f| f.end_with?('aspera/agent/transferd.rb') }}") }
          Aspera::Cli::Runner.new(ARGV).run
        RUBY
        Dir.mktmpdir do |home|
          _stdout, stderr, status = Open3.capture3({'ASCLI_HOME' => home}, RbConfig.ruby, "-I#{source_root}/lib", '-e', script)
          expect(status.exitstatus).to(eq(0), stderr)
          expect(stderr).to(include('GRPC=nil AGENT=false'))
        end
      end
    end
  end
end
