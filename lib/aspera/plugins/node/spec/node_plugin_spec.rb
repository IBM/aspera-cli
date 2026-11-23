# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Node::Commands — Node API is doubled, no node server needed.

require 'spec_helper'
require_relative '../../../cli/context'
require_relative '../../../cli/parser'
require_relative '../../../cli/formatter'
require_relative '../commands'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Aspera::Plugins::Node::Commands) do
        let(:api) { instance_double(Aspera::Plugins::Node::Api, base_url: 'https://node.example.com') }
        let(:formatter) { instance_double(Formatter, display_item_count: nil) }

        # @param argv [Array<String>] command line
        # @return [Result] result of command
        def execute(*argv)
          context = Context.new
          context.man_header = false
          context.options = Parser.new('test', argv)
          context.formatter = formatter
          described_class.new(context: context, api: api).execute_action
        end

        describe 'browse (gen3)' do
          let(:folder) { {'path' => '/', 'type' => 'directory'} }

          # @param total [Integer] total number of entries in folder
          def pages(total)
            calls = []
            allow(api).to(receive(:create).with('files/browse', anything)) do |_path, query|
              calls.push(query.dup)
              skip = query['skip'] || 0
              {'self' => folder, 'total_count' => total, 'item_count' => 2, 'items' => [{'path' => "/f#{skip}"}, {'path' => "/f#{skip + 1}"}]}
            end
            calls
          end

          it 'reads all pages' do
            calls = pages(4)
            expect(execute('browse', '/').data.map { |item| item['path'] }).to(eq(%w[/f0 /f1 /f2 /f3]))
            expect(calls.map { |query| query['skip'] }).to(eq([nil, 2]))
          end

          it 'stops at the maximum number of items' do
            pages(10)
            expect(execute('browse', '/', '--query=@json:{"max":3}').data.length).to(eq(3))
          end

          it 'makes a single call with skip, and displays the count' do
            calls = pages(10)
            expect(execute('browse', '/', '--query=@json:{"skip":4}').data.length).to(eq(2))
            expect(calls.length).to(eq(1))
            expect(formatter).to(have_received(:display_item_count).with(2, 10))
          end
        end

        describe 'stream' do
          it 'creates, shows, modifies and cancels' do
            allow(api).to(receive_messages(create: {'id' => 's1'}, read: {'id' => 's1', 'status' => 'running'}, update: {'id' => 's1'}, cancel: {'id' => 's1'}))
            expect(execute('stream', 'create', '@json:{"direction":"send"}').data).to(eq({'id' => 's1'}))
            expect(execute('stream', 'show', 's1').data['status']).to(eq('running'))
            execute('stream', 'modify', 's1', '@json:{"target_rate_kbps":1000}')
            execute('stream', 'cancel', 's1')
            expect(api).to(have_received(:create).with('streams', {'direction' => 'send'}))
            expect(api).to(have_received(:read).with('ops/transfers/s1'))
            expect(api).to(have_received(:update).with('streams/s1', {'target_rate_kbps' => 1000}))
            expect(api).to(have_received(:cancel).with('streams/s1'))
          end
        end

        describe 'watch_folder' do
          it 'shows, modifies, deletes and shows state' do
            allow(api).to(receive_messages(read: {'id' => 'w1'}, update: nil, delete: nil, headers: {}))
            expect(execute('watch_folder', 'show', 'w1').data).to(eq({'id' => 'w1'}))
            expect(execute('watch_folder', 'modify', 'w1', '@json:{"source":{"path":"/s"}}').data).to(eq('w1 updated'))
            expect(execute('watch_folder', 'delete', 'w1').data).to(eq('w1 deleted'))
            execute('watch_folder', 'state', 'w1')
            expect(api).to(have_received(:read).with('v3/watchfolders/w1/state'))
            expect(api).to(have_received(:update).with('v3/watchfolders/w1', {'source' => {'path' => '/s'}}))
            expect(api).to(have_received(:delete).with('v3/watchfolders/w1'))
          end
        end

        describe 'ssync lookup by name' do
          it 'fails if no sync has this name' do
            allow(api).to(receive(:read).with('asyncs').and_return({'ids' => [1]}))
            allow(api).to(receive(:read).with('asyncs/1').and_return({'configuration' => {'name' => 'other'}}))
            expect { execute('ssync', 'show', '%name:mine') }.to(raise_error(BadIdentifier, /mine/))
          end
        end

        describe 'access_keys do delete' do
          it 'deletes by file id' do
            allow(api).to(receive(:delete))
            execute('access_keys', 'do', 'self', 'delete', '%id:f1', '--root-id=1')
            expect(api).to(have_received(:delete).with('files/f1'))
          end
        end

        describe 'telemetry' do
          let(:otel) { instance_double(Rest::Client, create: nil) }

          before { allow(Rest::Client).to(receive(:new).and_return(otel)) }

          it 'sends the number of active transfers once' do
            allow(api).to(receive(:read_with_paging).with('ops/transfers', {active_only: true}).and_return([{}, {}]))
            allow(Log.log).to(receive(:info))
            execute('telemetry', '@json:{"url":"https://otel.example.com","key":"<API_KEY>","interval":0.0}')
            expect(Rest::Client).to(have_received(:new).with(hash_including(base_url: 'https://otel.example.com/v1')))
            expect(otel).to(have_received(:create).with('metrics', an_object_satisfying { |metrics|
              metrics.dig(:resourceMetrics, 0, :scopeMetrics, 0, :metrics, 0, :gauge, :dataPoints, 0, :asInt).eql?(2)
            }))
          end

          it 'accepts an integer interval, as documented' do
            allow(api).to(receive(:read_with_paging).and_return([]))
            allow(Log.log).to(receive(:info))
            expect { execute('telemetry', '@json:{"url":"https://otel.example.com","key":"<API_KEY>","interval":0}') }.not_to(raise_error)
          end

          it 'requires key (schema), and a positive interval' do
            expect { execute('telemetry', '@json:{"url":"https://otel.example.com"}') }.to(raise_error(BadArgument, /key/))
            expect { execute('telemetry', '@json:{"url":"https://otel.example.com","key":"<API_KEY>","interval":-1.0}') }.to(raise_error(BadArgument, /positive/))
          end
        end
      end
    end
  end
end
