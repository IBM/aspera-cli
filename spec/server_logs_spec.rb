# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/aspera/cli/plugins/server'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/ssh'

# Command `server logs`: the SSH connection is replaced by a double that serves the fixture files
RSpec.describe(Aspera::Cli::Plugins::Server) do
  fixtures_dir = File.expand_path('fixtures/ascp_logs', __dir__)
  let(:parser) { Aspera::Cli::Parser.new('server') }
  let(:context) do
    ctx = Aspera::Cli::Context.new
    ctx.man_header = false
    ctx.options = parser
    ctx
  end
  let(:server) { described_class.new(context: context) }
  let(:ssh) { Aspera::Ssh.new('host.example.com', 'xfer', {}) }
  # Commands sent to the server
  let(:commands) { [] }
  # Content of files of the server, by path
  let(:remote_files) { {'/var/log/aspera.log' => File.binread(File.join(fixtures_dir, 'pair_server.log'))} }

  before do
    described_class.declare_options(parser, target: server)
    allow(server).to(receive(:ascmd_executor).and_return(ssh))
    allow(ssh).to(receive(:execute)) do |cmd, **|
      commands.push(cmd)
      path = remote_files.keys.find { |p| cmd.end_with?(Shellwords.escape(p)) }
      raise Aspera::Ssh::Error, "#{cmd}: exit 1, No such file" if path.nil?
      "1790000000\n#{remote_files[path]}"
    end
  end

  it 'declares the same commands as `config ascp logs`' do
    expect(described_class.command_registry.children_of([:logs]).keys).to(include(:summary, :sessions, :diagnostics, :health, :records, :fields))
  end

  it 'analyzes a log file of the server' do
    summary = server.action_ascp_logs_summary(paths: ['/var/log/aspera.log']).data
    expect(summary['files']).to(eq(1))
    expect(summary['sessions']).to(be_positive)
    expect(commands.length).to(eq(1))
  end

  it 'lists the sessions of a log file of the server' do
    rows = server.send(:analyze_ascp_logs, ['/var/log/aspera.log']).sessions
    expect(rows).not_to(be_empty)
  end

  it 'escapes the path and bounds the size' do
    remote_files["/var/log/my logs/a;b'c.log"] = remote_files['/var/log/aspera.log']
    server.action_ascp_logs_summary(paths: ["/var/log/my logs/a;b'c.log"])
    expect(commands.first).to(include(Shellwords.escape("/var/log/my logs/a;b'c.log")))
    expect(commands.first).to(match(/head -c \d+ -- /))
  end

  it 'refuses files over the size limit, and deletes the temporary files' do
    parser.set_option(:ascp_logs, {'remote_max_size' => 100})
    folders = []
    allow(Dir).to(receive(:mktmpdir).and_wrap_original do |m, *args, &block|
      m.call(*args) do |dir|
        folders.push(dir)
        block.call(dir)
      end
    end)
    expect { server.action_ascp_logs_summary(paths: ['/var/log/aspera.log']) }.to(raise_error(Aspera::Cli::BadArgument, /exceed the limit of 100 bytes/))
    expect(folders.length).to(eq(1))
    expect(File.exist?(folders.first)).to(be(false))
  end

  it 'reports a file that cannot be read, without the content of the command' do
    expect { server.action_ascp_logs_summary(paths: ['/nope']) }.to(raise_error(Aspera::Cli::BadArgument, %r{Cannot read /nope}))
  end

  it 'refuses a file that is not an ascp log' do
    remote_files['/etc/hosts'] = "127.0.0.1 localhost\n"
    expect { server.action_ascp_logs_summary(paths: ['/etc/hosts']) }.to(raise_error(Aspera::Cli::BadArgument, /Not an ascp log/))
  end
end
