# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `console`: commands.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'

module Aspera
  module Plugins
    module Console
      RSpec.describe('Bundle console') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin console, from the bundle' do
            expect(registry.unavailable_reason(:console)).to(be_nil)
            expect(registry[:console].depends).to(eq([]))
            expect(registry[:console].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:console)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:console)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('console'))
          end
        end

        describe 'transfer current list' do
          let(:api) { double }
          let(:plugin) { Commands.allocate }

          # @param query [Hash] value of option `query`, or its default `{}`
          # @return [Hash] query sent to the API
          def query_sent(query)
            sent = nil
            allow(plugin).to(receive_messages(query_read_delete: query, api_console: api))
            allow(api).to(receive(:read).with('transfers', anything)) { |_path, q| sent = q.dup; [] } # rubocop:disable Style/Semicolon
            plugin.send(:action_transfer_current_list)
            sent
          end

          it 'lists the last 24 hours by default, in UTC' do
            sent = query_sent({})
            expect(sent.keys).to(eq(%w[from to]))
            from, to = sent.values_at('from', 'to').map { |v| Time.strptime("#{v} UTC", '%Y-%m-%d %H:%M:%S %Z') }
            expect(to).to(be_within(5).of(Time.now))
            expect(to - from).to(eq(86_400))
          end

          it 'converts the dates given to UTC, a date without time zone is in UTC' do
            sent = query_sent({'from' => '2013-02-28 12:00:00', 'to' => '2013-02-28T14:00:00+01:00'})
            expect(sent).to(eq({'from' => '2013-02-28 12:00:00', 'to' => '2013-02-28 13:00:00'}))
            sent = query_sent({'from' => 'now-2h'})
            expect(Time.strptime("#{sent['from']} UTC", '%Y-%m-%d %H:%M:%S %Z')).to(be_within(5).of(Time.now - 7200))
            expect(sent).not_to(have_key('to'))
          end

          it 'refuses an invalid date' do
            expect { query_sent({'from' => '2h'}) }.to(raise_error(ParameterError, /use now-2h or now\+2h/))
          end
        end

        describe 'API schema' do
          it 'is the vendor schema of the bundle (downloaded), not in LOCATIONS' do
            schema = registry.schema(:console)
            expect(schema).not_to(be_nil)
            expect(schema.key).to(eq(:console))
            expect(schema.owned).to(be(false))
            expect(schema.source['url']).to(end_with('-enhanced.yaml'))
            expect(schema.file).to(eq(File.join(bundle_folder, 'schemas', 'IBM Aspera Console-enhanced.yaml')))
            expect(Schema::Registry.known?(:console)).to(be(true))
            expect(Schema::Registry.owned?('console')).to(be(false))
            expect(Schema::Registry::LOCATIONS).not_to(include(:console))
          end
        end
      end
    end
  end
end
