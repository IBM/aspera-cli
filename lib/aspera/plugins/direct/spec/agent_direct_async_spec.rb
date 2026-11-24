# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Direct::Agent: end of an `async` process monitored on its exclusive management port.
# In continuous mode, `async` sends DONE and closes the management port at the end of its first activity period, but keeps running.
# A fake `async` (Ruby script) sends management events, then ends by itself, or records that it was interrupted.

require_relative '../agent'
require 'bundler/setup'
require 'rbconfig'
require 'tmpdir'

RSpec.describe(Aspera::Plugins::Direct::Agent) do
  let(:agent) { described_class.new(spawn_timeout_sec: 10) }

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  # @param events [Array<String>] Types of the management events sent before closing the management port
  # @return [String] Path of the file where the fake `async` writes how it ended: `ended` or `interrupted`
  def run_fake_async(events)
    marker = File.join(@dir, 'marker')
    fake = File.join(@dir, 'async')
    frames = events.map { |type| "FASPMGR 2\nType: #{type}\nSessionId: s1\n\n" }.join
    File.write(fake, <<~RUBY)
      #!#{RbConfig.ruby}
      require 'socket'
      Signal.trap('INT') { File.write(#{marker.inspect}, 'interrupted'); exit!(3) }
      port = ARGV.find { |a| a.start_with?('--exclusive-mgmt-port=') }.split('=', 2).last.to_i
      socket = TCPSocket.new('127.0.0.1', port)
      socket.write(#{frames.inspect})
      socket.close
      # continuous mode: still running after the management port is closed
      sleep(1)
      File.write(#{marker.inspect}, 'ended')
    RUBY
    File.chmod(0o755, fake)
    allow(Aspera::Ascp::Installation.instance).to(receive(:path).with(:async).and_return(fake))
    agent.start_and_monitor_process(session: {}, exec_spec: Aspera::ExecSpec.new(exec: :async))
    marker
  end

  it 'waits for the end of async after DONE, without stopping it (continuous mode)' do
    marker = run_fake_async(%w[INIT DONE])
    expect(File.read(marker)).to(eq('ended'))
  end

  it 'stops async when the management port closes without final status' do
    marker = nil
    expect { marker = run_fake_async(%w[INIT]) }.to(raise_error(Aspera::Transfer::Error, /ended without final status/))
    expect(File.read(File.join(@dir, 'marker'))).to(eq('interrupted'))
    expect(marker).to(be_nil)
  end
end
