# frozen_string_literal: true

require 'bundler/setup'
require 'tmpdir'
require 'aspera/persistency_folder'
require 'aspera/cli/async_transfer_store'

module Aspera
  module Cli
    RSpec.describe(AsyncTransferStore) do
      # Use a real PersistencyFolder backed by a temp directory
      let(:tmpdir){Dir.mktmpdir('async_store_spec')}
      let(:persistency){Aspera::PersistencyFolder.new(tmpdir)}
      let(:store){described_class.new(persistency)}

      after{FileUtils.rm_rf(tmpdir)}

      let(:job_id){'aaaaaaaa-0000-0000-0000-000000000001'}
      let(:entry) do
        {
          'job_id'            => job_id,
          'agent_type'        => 'node',
          'transfer_id'       => 'tid-123',
          'agent_params'      => {'url' => 'https://node.example.com', 'username' => 'u', 'password' => 'p'},
          'status'            => 'running',
          'bytes_transferred' => 0,
          'started_at'        => '2024-01-01T00:00:00Z',
          'ended_at'          => nil,
          'error'             => nil
        }
      end

      describe '#write and #read round-trip' do
        it 'persists and retrieves an entry by job_id' do
          store.write(job_id, entry)
          result = store.read(job_id)
          expect(result).to(be_a(Hash))
          expect(result['job_id']).to(eq(job_id))
          expect(result['agent_type']).to(eq('node'))
          expect(result['transfer_id']).to(eq('tid-123'))
          expect(result['status']).to(eq('running'))
        end

        it 'returns nil for an unknown job_id' do
          expect(store.read('does-not-exist')).to(be_nil)
        end

        it 'overwrites an existing entry on second write' do
          store.write(job_id, entry)
          store.write(job_id, entry.merge('status' => 'completed'))
          expect(store.read(job_id)['status']).to(eq('completed'))
        end
      end

      describe '#list' do
        it 'returns an empty array when nothing is stored' do
          expect(store.list).to(eq([]))
        end

        it 'returns all stored entries' do
          id2 = 'aaaaaaaa-0000-0000-0000-000000000002'
          store.write(job_id, entry)
          store.write(id2, entry.merge('job_id' => id2, 'agent_type' => 'desktop'))
          listed = store.list
          expect(listed.size).to(eq(2))
          types = listed.map{ |e| e['agent_type']}.sort
          expect(types).to(eq(%w[desktop node]))
        end
      end

      describe '#delete' do
        it 'removes a stored entry' do
          store.write(job_id, entry)
          store.delete(job_id)
          expect(store.read(job_id)).to(be_nil)
          expect(store.list).to(be_empty)
        end

        it 'does not raise when deleting a non-existent entry' do
          expect{store.delete('no-such-id')}.not_to(raise_error)
        end
      end
    end
  end
end
