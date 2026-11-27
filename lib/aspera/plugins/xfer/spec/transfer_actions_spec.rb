# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Xfer::TransferActions (`config agents jobs status` and `list`) — no server needed.

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
      # Status given by the agent for the entry of a job
      let(:live) { ->(_entry) { {'status' => 'completed'} } }
      # Host of the mixin, as Plugins::Config: provides `context`
      let(:host) do
        transfer = instance_double(Aspera::Plugins::Xfer::TransferAgent, async_store: store, transfer_options: transfer_options)
        context = Struct.new(:transfer).new(transfer)
        answer = live
        Class.new do
          include Aspera::Plugins::Xfer::TransferActions

          define_method(:context) { context }
          # Last entry used to query the agent, and the jobs queried
          attr_reader :queried, :queried_jobs

          # No agent class loaded
          define_method(:agent_class_of) { |_agent_type| nil }

          # Records the entry used to query the agent, instead of querying it (`list`: from several threads)
          define_method(:query_live_status) do |entry, _agent_class = nil|
            @queried = entry
            (@queried_jobs ||= []).push(entry['job_id'])
            answer.call(entry)
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
          expect(host.queried['agent_params']).to(eq({'url' => 'https://node', 'username' => 'ak', 'password' => secret})) # HashiCorpIgnore
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

      describe 'status' do
        it 'removes the error of a previous query when the agent gives the status' do
          store.write('job1', store.read('job1').merge('status' => 'unknown', 'error' => 'Unauthenticated: missing api_key', 'error_code' => '1', 'note' => 'other'))
          result = host.action_agents_jobs_status(job_id: 'job1')
          expect(result.data).to(include('status' => 'completed'))
          expect(result.data).not_to(include('error', 'error_code', 'note'))
          expect(store.read('job1')).not_to(include('error', 'error_code', 'note'))
        end

        it 'keeps the error given by the agent with its status' do
          allow(live).to(receive(:call).and_return({'status' => 'failed', 'error' => 'Failed to open TCP connection for SSH'}))
          expect(host.action_agents_jobs_status(job_id: 'job1').data).to(include('status' => 'failed', 'error' => 'Failed to open TCP connection for SSH'))
          expect(store.read('job1')).to(include('status' => 'failed', 'error' => 'Failed to open TCP connection for SSH'))
        end

        context 'when the agent gives no status' do
          let(:live) { ->(_entry) { {'status' => 'unknown', 'bytes_transferred' => 0, 'error' => 'Unauthenticated: missing api_key'} } }

          it 'shows the saved status with the error, and does not save unknown' do
            store.write('job1', store.read('job1').merge('bytes_transferred' => 1024))
            saved = store.read('job1')
            result = host.action_agents_jobs_status(job_id: 'job1')
            expect(result.data).to(include('status' => 'running', 'bytes_transferred' => 1024, 'error' => 'Unauthenticated: missing api_key'))
            expect(store.read('job1')).to(eq(saved))
          end
        end

        it 'shows the saved status, without error, when the agent cannot be queried' do
          allow(live).to(receive(:call).and_return(nil))
          result = host.action_agents_jobs_status(job_id: 'job1')
          expect(result.data).to(include('status' => 'running'))
          expect(result.data).not_to(have_key('error'))
          expect(store.read('job1')['status']).to(eq('running'))
        end

        it 'does not query the agent of a job ended' do
          store.write('job1', store.read('job1').merge('status' => 'completed', 'bytes_transferred' => 4096))
          expect(host.action_agents_jobs_status(job_id: 'job1').data).to(include('status' => 'completed', 'bytes_transferred' => 4096))
          expect(host.queried_jobs).to(be_nil)
        end
      end

      describe 'list' do
        let(:live) do
          lambda do |entry|
            case entry['job_id']
            when 'job1' then {'status' => 'running', 'bytes_transferred' => 2048}
            when 'job2' then {'status' => 'completed', 'bytes_transferred' => 4096, 'ended_at' => '2026-11-23T10:00:00Z'}
            else {'status' => 'unknown', 'bytes_transferred' => 0, 'error' => 'Unavailable: failed to connect to all addresses'}
            end
          end
        end

        before do
          %w[job2 job3 job4].each do |job_id|
            store.write(job_id, {'job_id' => job_id, 'agent_type' => 'transferd', 'transfer_id' => "t-#{job_id}", 'agent_params' => {'url' => '127.0.0.1:55002'}, 'status' => 'running', 'bytes_transferred' => 0})
          end
          store.write('job5', {'job_id' => 'job5', 'agent_type' => 'transferd', 'transfer_id' => 't5', 'status' => 'failed', 'error' => 'ended before'})
          allow(Log.log).to(receive(:warn))
        end

        # @return [Hash] Rows of the result of list, by job_id
        def list_rows
          result = host.action_agents_jobs_list
          expect(result).to(be_a(Cli::Result::ObjectList))
          expect(result.fields).to(eq(%w[job_id agent_type status started_at ended_at bytes_transferred transfer_id]))
          result.data.to_h { |row| [row['job_id'], row] }
        end

        it 'refreshes and saves the status of the jobs not ended' do
          rows = list_rows
          expect(rows['job1']).to(include('status' => 'running', 'bytes_transferred' => 2048))
          expect(rows['job2']).to(include('status' => 'completed', 'bytes_transferred' => 4096, 'ended_at' => '2026-11-23T10:00:00Z'))
          expect(store.read('job2')).to(include('status' => 'completed', 'bytes_transferred' => 4096))
        end

        it 'keeps the saved status of the jobs not refreshed, with one warning for each reason' do
          rows = list_rows
          expect(rows['job3']).to(include('status' => 'running', 'bytes_transferred' => 0))
          expect(rows['job3']).not_to(have_key('error'))
          expect(store.read('job4')['status']).to(eq('running'))
          expect(store.read('job4')).not_to(have_key('error'))
          expect(Log.log).to(have_received(:warn).once) { |&block| expect(block.call).to(eq('Status not refreshed for job job3, job4: Unavailable: failed to connect to all addresses')) }
        end

        it 'does not query the agent of the jobs ended' do
          rows = list_rows
          expect(host.queried_jobs).to(contain_exactly('job1', 'job2', 'job3', 'job4'))
          expect(rows['job5']).to(include('status' => 'failed', 'error' => 'ended before'))
        end

        context 'with agents that do not answer' do
          # Each query waits, as an agent that does not answer until the call timeout
          let(:live) { ->(_entry) { sleep(0.3) && nil } }

          it 'queries the agents in parallel, by batches: a timeout once per batch, not once per job' do
            (6..12).each do |index|
              store.write("job#{index}", {'job_id' => "job#{index}", 'agent_type' => 'transferd', 'transfer_id' => "t#{index}", 'agent_params' => {'url' => '10.0.0.1:55002'}, 'status' => 'running'})
            end
            started_at = Time.now
            rows = list_rows
            # 11 jobs not ended: 2 batches of at most 10
            expect(Time.now - started_at).to(be_between(0.6, 1.5))
            expect(host.queried_jobs.size).to(eq(11))
            expect(rows.values.map { |row| row['status'] }.tally).to(eq('running' => 11, 'failed' => 1))
          end
        end

        it 'queries with the secret from current options' do
          transfer_options.merge!('agent' => 'transferd', 'api_key' => '<API_KEY>')
          list_rows
          expect(host.queried['agent_params']).to(include('api_key' => '<API_KEY>', 'url' => '127.0.0.1:55002'))
          expect(store.read('job4')['agent_params']).not_to(have_key('api_key'))
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
