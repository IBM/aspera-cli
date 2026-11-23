# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Tests for TransferAgent#start: the restriction on written files (option `security`, `writable_paths`)
# applies to the destination folder only when the transfer agent writes on the local system.
# The agent_instance is doubled; no real transfer is started.

require_relative '../../../hash_ext'
require_relative '../../../persistency_folder'
require_relative '../../../cli/error'
require_relative '../../../cli/security'
require_relative '../transfer_agent'
require_relative '../../../agent/base'
require_relative '../../node/agent'
require 'bundler/setup'
require 'tmpdir'

module Aspera
  module Cli
    RSpec.describe(Aspera::Plugins::TransferAgents::TransferAgent) do
      let(:tmpdir) { Dir.mktmpdir('transfer_agent_destination_spec') }
      let(:security) { Security.instance }
      # Transfer spec given to the agent
      let(:started) { [] }

      after do
        security.reset
        FileUtils.rm_rf(tmpdir)
      end

      # @param local     [Boolean] Value of `local_destination?` of the agent
      # @param to_folder [String]  Destination folder (option `to_folder`)
      # @return [TransferAgent] with a doubled agent, in asynchronous mode (no wait for completion)
      def transfer_agent(local:, to_folder:)
        ta = described_class.allocate
        ta.instance_variable_set(:@user_transfer_spec, {})
        ta.instance_variable_set(:@transfer_paths, [{'source' => '/src/file.txt'}])
        ta.instance_variable_set(:@notification_cb, nil)
        ta.instance_variable_set(:@httpgw_url_lambda, nil)
        options = double('Options')
        allow(options).to(receive(:get_option).and_return(nil))
        allow(options).to(receive(:get_option).with(:to_folder).and_return(to_folder))
        allow(options).to(receive(:get_option).with(:transfer_info).and_return({}))
        allow(options).to(receive(:get_option).with(:transfer).and_return({'agent' => 'httpgw', 'asynchronous' => true}))
        ta.instance_variable_set(:@context, double('Context', persistency: Aspera::PersistencyFolder.new(tmpdir), main_folder: tmpdir, options: options))
        agent = double('Agent', local_destination?: local, last_job_id: 'job', in_process?: true, transfer_id: 'job', async_params: {})
        allow(agent).to(receive(:start_transfer)) { |spec, **| started.push(spec) }
        # The agent is a double: its name is the one of the option
        allow(Aspera::Agent::Factory.instance).to(receive(:agent_name).with(agent).and_return(:httpgw))
        ta.agent_instance = agent
        ta
      end

      # @return [Hash] Transfer spec that receives files
      def receive_spec
        {'direction' => 'receive', 'remote_host' => 'host.example.com', 'remote_user' => 'xfer', 'paths' => [{'source' => '/file.txt'}]}
      end

      it 'tells that agents write on the local system, except agent node' do
        expect(Agent::Base.allocate.local_destination?).to(be(true))
        expect(Aspera::Plugins::Node::Agent.allocate.local_destination?).to(be(false))
      end

      it 'gives the destination as is at level low' do
        transfer_agent(local: true, to_folder: 'relative/folder').start(receive_spec)
        expect(started.first['destination_root']).to(eq('relative/folder'))
      end

      context 'with security level high' do
        before { security.lock('in test', default: :high) }

        it 'refuses a local destination that is not in writable paths' do
          expect { transfer_agent(local: true, to_folder: tmpdir).start(receive_spec) }.to(raise_error(BadArgument, /writing is refused by security level high/))
          expect(started).to(be_empty)
        end

        it 'accepts a local destination in writable paths, and gives its real path' do
          security.reset
          security.options = {'level' => 'high', 'writable_paths' => [tmpdir]}
          transfer_agent(local: true, to_folder: File.join(tmpdir, 'new')).start(receive_spec)
          expect(started.first['destination_root']).to(eq(File.join(File.realpath(tmpdir), 'new')))
        end

        it 'does not check a destination on a remote system' do
          transfer_agent(local: false, to_folder: '/Upload').start(receive_spec)
          expect(started.first['destination_root']).to(eq('/Upload'))
        end
      end
    end
  end
end
