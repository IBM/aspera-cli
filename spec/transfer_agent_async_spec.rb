# frozen_string_literal: true

# Tests for TransferAgent#start in asynchronous mode.
# The agent_instance is fully doubled; no real transfer is started.
# PersistencyFolder uses a temp directory.

require 'bundler/setup'
require 'tmpdir'
require 'aspera/hash_ext'
require 'aspera/persistency_folder'
require 'aspera/cli/async_transfer_store'
require 'aspera/cli/error'
require 'aspera/cli/transfer_agent'
require 'aspera/transfer/result'

module Aspera
  module Cli
    RSpec.describe(TransferAgent) do
      # ── helpers ────────────────────────────────────────────────────────────

      let(:tmpdir){Dir.mktmpdir('transfer_agent_spec')}
      let(:persistency){Aspera::PersistencyFolder.new(tmpdir)}

      after{FileUtils.rm_rf(tmpdir)}

      # Build a TransferAgent with all Context dependencies doubled.
      # We bypass the constructor's option wiring by using instance_variable_set.
      def build_agent(agent_type:, extra_transfer_options: {})
        ta = described_class.allocate

        ta.instance_variable_set(:@user_transfer_spec, {'create_dir' => true, 'resume_policy' => 'sparse_csum'})
        ta.instance_variable_set(:@transfer_options, {'agent' => agent_type}.merge(extra_transfer_options))
        ta.instance_variable_set(:@transfer_paths, [{'source' => '/src/file.txt'}])
        ta.instance_variable_set(:@notification_cb, nil)
        ta.instance_variable_set(:@httpgw_url_lambda, nil)

        options_double = double('Options')
        allow(options_double).to(receive(:get_option).and_return(nil))
        context_double = double('Context', persistency: persistency, main_folder: tmpdir, options: options_double)
        ta.instance_variable_set(:@context, context_double)

        ta
      end

      # Build a minimal transfer spec (direction send, no token — uses default destination)
      def ts
        {
          'direction' => 'send', 'remote_host' => 'host.example.com',
         'remote_user' => 'xfer', 'paths' => [{'source' => '/src/file.txt'}]
        }
      end

      # ── httpgw raises ───────────────────────────────────────────────────────

      describe 'asynchronous: true with httpgw' do
        it 'raises BadArgument' do
          ta = build_agent(agent_type: 'httpgw', extra_transfer_options: {'asynchronous' => true})

          agent_double = double('Agent::Httpgw')
          allow(agent_double).to(receive(:start_transfer))
          ta.agent_instance = agent_double

          expect{ta.start(ts)}.to(raise_error(Cli::BadArgument, /httpgw/))
        end
      end

      # ── node async ──────────────────────────────────────────────────────────

      describe 'asynchronous: true with node' do
        let(:agent_double) do
          d = double('Agent::Node')
          allow(d).to(receive(:start_transfer))
          allow(d).to(receive(:instance_variable_get).with(:@transfer_id).and_return('node-tid-abc'))
          d
        end

        let(:ta) do
          build_agent(
            agent_type: 'node',
            extra_transfer_options: {
              'asynchronous' => true,
              'url'          => 'https://node.example.com',
              'username'     => 'u',
              'password'     => 'p'
            }
          ).tap{ |a| a.agent_instance = agent_double}
        end

        it 'returns a Transfer::Result::Async with running status' do
          result = ta.start(ts)
          expect(result).to(be_a(Aspera::Transfer::Result::Async))
          expect(result.status).to(eq('running'))
          expect(result.job_id).to(be_a(String))
          expect(result.job_id).not_to(be_empty)
        end

        it 'does NOT call wait_for_completion' do
          expect(agent_double).not_to(receive(:wait_for_completion))
          ta.start(ts)
        end

        it 'persists the entry in AsyncTransferStore' do
          result = ta.start(ts)
          job_id = result.job_id
          store = AsyncTransferStore.new(persistency)
          entry = store.read(job_id)
          expect(entry).not_to(be_nil)
          expect(entry['agent_type']).to(eq('node'))
          expect(entry['transfer_id']).to(eq('node-tid-abc'))
          expect(entry['status']).to(eq('running'))
          expect(entry['agent_params']['url']).to(eq('https://node.example.com'))
        end
      end

      # ── direct async ────────────────────────────────────────────────────────

      describe 'asynchronous: true with direct' do
        let(:job_id){'direct-job-uuid'}

        let(:agent_double) do
          d = double('Agent::Direct')
          allow(d).to(receive(:start_transfer))
          allow(d).to(receive(:instance_variable_get).with(:@sessions).and_return([{job_id: job_id}]))
          d
        end

        let(:ta) do
          build_agent(agent_type: 'direct', extra_transfer_options: {'asynchronous' => true})
            .tap{ |a| a.agent_instance = agent_double}
        end

        it 'returns Transfer::Result::Async with the direct job_id without persisting to store' do
          result = ta.start(ts)
          expect(result).to(be_a(Aspera::Transfer::Result::Async))
          expect(result.job_id).to(eq(job_id))
          expect(result.status).to(eq('running'))
          store = AsyncTransferStore.new(persistency)
          expect(store.list).to(be_empty)
        end

        it 'does NOT call wait_for_completion' do
          expect(agent_double).not_to(receive(:wait_for_completion))
          ta.start(ts)
        end
      end

      # ── synchronous (default) ───────────────────────────────────────────────

      describe 'synchronous mode (no asynchronous key)' do
        let(:agent_double) do
          d = double('Agent::Node')
          allow(d).to(receive(:start_transfer))
          allow(d).to(receive(:wait_for_completion).and_return(Aspera::Transfer::Result.success))
          d
        end

        let(:ta) do
          build_agent(agent_type: 'node').tap{ |a| a.agent_instance = agent_double}
        end

        it 'calls wait_for_completion and returns a Transfer::Result::Success' do
          result = ta.start(ts)
          expect(result).to(be_a(Aspera::Transfer::Result::Success))
        end

        it 'does NOT write to AsyncTransferStore' do
          ta.start(ts)
          expect(AsyncTransferStore.new(persistency).list).to(be_empty)
        end
      end

      # ── Runner.result_transfer with typed Transfer::Result ──────────────────

      describe 'Runner.result_transfer' do
        before{require 'aspera/cli/runner'}

        it 'returns a SingleObject for Transfer::Result::Async' do
          async_result = Aspera::Transfer::Result.async(job_id: 'abc-123')
          result = Aspera::Cli::Runner.result_transfer(async_result)
          expect(result).to(be_a(Aspera::Cli::Result::SingleObject))
          expect(result.data['job_id']).to(eq('abc-123'))
        end

        it 'returns Result::Nothing for Transfer::Result::Success' do
          result = Aspera::Cli::Runner.result_transfer(Aspera::Transfer::Result.success)
          expect(result).to(be_a(Aspera::Cli::Result::Nothing))
        end

        it 'raises the exception for Transfer::Result::Error' do
          err = RuntimeError.new('transfer failed')
          expect{Aspera::Cli::Runner.result_transfer(Aspera::Transfer::Result.error(err))}.to(raise_error(RuntimeError, 'transfer failed'))
        end
      end
    end
  end
end
