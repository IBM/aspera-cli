# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Xfer::TransferActions (`config agents jobs status`) — no server needed.

require_relative '../../../persistency_folder'
require_relative '../async_transfer_store'
require_relative '../../../cli/result'
require_relative '../../../cli/error'
require_relative '../transfer_agent'
require_relative '../transfer_actions'
require 'tmpdir'
require 'securerandom'

module Aspera
  module Cli
    RSpec.describe(Aspera::Plugins::Xfer::TransferActions) do
      let(:tmpdir) { Dir.mktmpdir('transfer_actions_spec') }
      let(:store) { Aspera::Plugins::Xfer::AsyncTransferStore.new(PersistencyFolder.new(tmpdir)) }
      let(:transfer_options) { {} }
      # Host of the mixin, as Plugins::Config: provides `context`
      let(:host) do
        transfer = instance_double(Aspera::Plugins::Xfer::TransferAgent, async_store: store, transfer_options: transfer_options)
        context = Struct.new(:transfer).new(transfer)
        Class.new do
          include Aspera::Plugins::Xfer::TransferActions

          define_method(:context) { context }
          attr_reader :queried

          # Records the entry used to query the agent, instead of querying it
          define_method(:query_live_status) do |entry|
            @queried = entry
            {'status' => 'completed'}
          end
        end.new
      end

      after { FileUtils.rm_rf(tmpdir) }

      # Value of the secret is generated, none in source
      let(:secret) { SecureRandom.alphanumeric(12) }

      before do
        store.write('job1', {'job_id' => 'job1', 'agent_type' => 'node', 'transfer_id' => 't1', 'agent_params' => {'url' => 'https://node', 'username' => 'ak', 'password' => secret}, 'status' => 'running'}) # HashiCorpIgnore
      end

      context 'with transfer options for the same agent' do
        let(:transfer_options) { {'agent' => 'node', 'url' => 'https://other', 'password' => secret} } # HashiCorpIgnore

        it 'queries with the secret from current options, and keeps stored parameters' do
          result = host.action_agents_jobs_status(job_id: 'job1')
          expect(host.queried['agent_params']).to(eq({'url' => 'https://node', 'username' => 'ak', 'password' => secret}))
          expect(result.data['status']).to(eq('completed'))
          expect(result.data['agent_params']).not_to(have_key('password'))
          expect(store.read('job1')['status']).to(eq('completed'))
        end
      end

      context 'with transfer options for another agent' do
        let(:transfer_options) { {'agent' => 'transferd', 'password' => SecureRandom.alphanumeric(12)} }

        it 'queries with the stored parameters only' do
          host.action_agents_jobs_status(job_id: 'job1')
          expect(host.queried['agent_params']).to(eq({'url' => 'https://node', 'username' => 'ak'}))
        end
      end

      describe 'query of the agent' do
        # Host that queries the agent
        let(:querying) { Class.new { include Aspera::Plugins::Xfer::TransferActions }.new }
        let(:entry) { {'job_id' => 'job1', 'agent_type' => 'node', 'transfer_id' => 't1', 'agent_params' => {'url' => 'https://node'}} }
        let(:agent_class) { double('agent class') }

        before { allow(Agent::Factory.instance).to(receive(:agent_class).with('node').and_return(agent_class)) }

        it 'asks the status to the class of the agent given by the factory of agents (agent of a bundle)' do
          allow(agent_class).to(receive(:transfer_status).with('t1', {'url' => 'https://node'}).and_return({'status' => 'completed'}))
          expect(querying.send(:query_live_status, entry)).to(eq({'status' => 'completed'}))
        end

        it 'gives no status, with a warning, when the agent cannot be queried' do
          allow(agent_class).to(receive(:transfer_status).and_raise(BundleRegistry::Unavailable, 'plugin spec is unavailable'))
          allow(Log.log).to(receive(:warn))
          expect(querying.send(:query_live_status, entry)).to(be_nil)
          expect(Log.log).to(have_received(:warn)) { |&block| expect(block.call).to(eq('Could not re-query node agent for job job1: plugin spec is unavailable')) }
        end
      end
    end
  end
end
