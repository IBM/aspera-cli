# frozen_string_literal: true

# Unit tests for Aspera::Cli::TransferActions (`config transfer status`) — no server needed.

require 'tmpdir'
require 'aspera/persistency_folder'
require 'aspera/cli/async_transfer_store'
require 'aspera/cli/result'
require 'aspera/cli/error'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/transfer_actions'

module Aspera
  module Cli
    RSpec.describe(TransferActions) do
      let(:tmpdir) { Dir.mktmpdir('transfer_actions_spec') }
      let(:store) { AsyncTransferStore.new(PersistencyFolder.new(tmpdir)) }
      let(:transfer_options) { {} }
      # Host of the mixin, as Plugins::Config: provides `context`
      let(:host) do
        transfer = instance_double(TransferAgent, async_store: store, transfer_options: transfer_options)
        context = Struct.new(:transfer).new(transfer)
        Class.new do
          include TransferActions

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

      before do
        store.write('job1', {'job_id' => 'job1', 'agent_type' => 'node', 'transfer_id' => 't1', 'agent_params' => {'url' => 'https://node', 'username' => 'ak', 'password' => 'secret'}, 'status' => 'running'})
      end

      context 'with transfer options for the same agent' do
        let(:transfer_options) { {'agent' => 'node', 'url' => 'https://other', 'password' => 'secret'} }

        it 'queries with the secret from current options, and keeps stored parameters' do
          result = host.action_transfer_status(job_id: 'job1')
          expect(host.queried['agent_params']).to(eq({'url' => 'https://node', 'username' => 'ak', 'password' => 'secret'}))
          expect(result.data['status']).to(eq('completed'))
          expect(result.data['agent_params']).not_to(have_key('password'))
          expect(store.read('job1')['status']).to(eq('completed'))
        end
      end

      context 'with transfer options for another agent' do
        let(:transfer_options) { {'agent' => 'transferd', 'password' => 'other'} }

        it 'queries with the stored parameters only' do
          host.action_transfer_status(job_id: 'job1')
          expect(host.queried['agent_params']).to(eq({'url' => 'https://node', 'username' => 'ak'}))
        end
      end
    end
  end
end
