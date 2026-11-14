# frozen_string_literal: true

# #203: with `once_only`, a package is marked as downloaded only when its transfer succeeded.

require_relative '../lib/aspera/cli/runner'
require_relative '../lib/aspera/cli/plugins/aoc'
require_relative '../lib/aspera/persistency_action_once'
require_relative '../lib/aspera/transfer/result'
require 'bundler/setup'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Aoc) do
        # Persistency manager in memory
        let(:store) do
          Class.new do
            def initialize = @h = {}
            def get(id) = @h[id]
            def put(id, value) = @h[id] = value
            def delete(id) = @h.delete(id)
          end.new
        end
        let(:skip_ids) { PersistencyActionOnce.new(manager: store, data: [], id: 'aoc_recv_test') }
        let(:transfer) { double(ts_source_paths: ['.'], destination_folder: '/dest', user_transfer_spec: {}) }
        let(:node_api) { double(transfer_spec_gen4: {}) }
        let(:aoc_api) { double(public_link: nil, read: {'id' => 'p1', 'name' => 'pack', 'node_id' => 'n1', 'contents_file_id' => 'f1'}, node_api_from: node_api) }
        let(:plugin) do
          plugin = described_class.allocate
          allow(plugin).to(receive_messages(
            aoc_api: aoc_api,
            transfer: transfer,
            package_persistency: skip_ids,
            workspace_id_hash: {},
            formatter: double(display_status: nil),
            options: double(get_option: {})
          ))
          plugin
        end

        def receive_package = plugin.send(:action_packages_receive, package_id: 'p1')

        it 'marks the package as downloaded when the transfer succeeded' do
          allow(transfer).to(receive(:start).and_return(Transfer::Result.success))
          receive_package
          expect(skip_ids.data).to(eq(['p1']))
          expect(store.get('aoc_recv_test')).to(eq('["p1"]'))
        end

        it 'does not mark the package when the transfer failed' do
          allow(transfer).to(receive(:start).and_return(Transfer::Result.error(StandardError.new('failed'))))
          expect { receive_package }.to(raise_error(StandardError, 'failed'))
          expect(skip_ids.data).to(be_empty)
          expect(store.get('aoc_recv_test')).to(be_nil)
        end

        it 'does not mark the package when the transfer is interrupted (Ctrl-C)' do
          allow(transfer).to(receive(:start).and_raise(Interrupt))
          expect { receive_package }.to(raise_error(Interrupt))
          expect(skip_ids.data).to(be_empty)
          expect(store.get('aoc_recv_test')).to(be_nil)
        end
      end
    end
  end
end
