# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::TransferAgents::TransferAgent option handling: `ts`, `transfer` and `transfer_info`.

require_relative '../../../cli/parser'
require_relative '../../../cli/context'
require_relative '../transfer_agent'

module Aspera
  module Cli
    RSpec.describe(Aspera::Plugins::TransferAgents::TransferAgent) do
      # @return [TransferAgent] transfer agent with options from the given command line and preset
      def build_transfer_agent(argv, preset: nil)
        context = Context.new
        context.options = Parser.new('test', argv)
        # Declared by the config plugin
        context.options.declare(:notify_to, description: 'Notify')
        # Declared by the runner
        context.options.declare(:dry_run, description: 'Dry run', allowed: Type::BOOLEAN, default: false)
        context.options.add_option_preset(preset, 'test') unless preset.nil?
        described_class.new(context)
      end

      describe 'option ts' do
        it 'has defaults' do
          expect(build_transfer_agent([]).user_transfer_spec).to(eq({'create_dir' => true, 'resume_policy' => 'sparse_csum'}))
        end

        it 'overrides defaults and adds parameters' do
          ta = build_transfer_agent(['--ts.resume_policy=none', '--ts.target_rate_kbps=1000'])
          expect(ta.user_transfer_spec).to(eq({'create_dir' => true, 'resume_policy' => 'none', 'target_rate_kbps' => 1000}))
        end

        it 'merges preset and command line' do
          ta = build_transfer_agent(['--ts.target_rate_kbps=1000'], preset: {ts: {'cookie' => 'x', 'target_rate_kbps' => 10}})
          expect(ta.user_transfer_spec).to(include('create_dir' => true, 'cookie' => 'x', 'target_rate_kbps' => 1000))
        end
      end

      describe 'option transfer' do
        it 'is empty by default' do
          expect(build_transfer_agent([]).transfer_options).to(eq({}))
        end

        it 'accepts agent type as String, with parameters' do
          expect(build_transfer_agent(['--transfer=node', '--transfer.url=https://u']).transfer_options).to(eq({'agent' => 'node', 'url' => 'https://u'}))
        end

        it 'accepts agent type as String after parameters' do
          expect(build_transfer_agent(['--transfer.url=https://u', '--transfer=node']).transfer_options).to(eq({'url' => 'https://u', 'agent' => 'node'}))
        end

        it 'merges dotted parameters into a Hash value' do
          ta = build_transfer_agent(['--transfer=@json:{"agent":"node","url":"https://x"}', '--transfer.url=https://y'])
          expect(ta.transfer_options).to(eq({'agent' => 'node', 'url' => 'https://y'}))
        end

        it 'overrides deprecated transfer_info' do
          ta = build_transfer_agent(['--transfer-info.url=https://i', '--transfer-info.username=a', '--transfer.url=https://u'])
          expect(ta.transfer_options).to(eq({'url' => 'https://u', 'username' => 'a'}))
        end
      end

      describe 'option dry_run' do
        let(:transfer_spec) { {'remote_host' => 'localhost', 'direction' => 'send', 'remote_password' => '<PASSWORD>', 'paths' => [{'source' => 'file'}]} }

        it 'does not start the transfer: the final transfer spec is the result' do
          ta = build_transfer_agent(['--dry-run=yes', '--ts.target_rate_kbps=1000', '--to-folder=/folder'])
          expect(ta).not_to(receive(:agent_instance))
          result = ta.start(transfer_spec)
          expect(result).to(be_a(Transfer::Result::DryRun))
          expect(result.transfer_spec).to(include('remote_host' => 'localhost', 'target_rate_kbps' => 1000, 'destination_root' => '/folder', 'paths' => [{'source' => 'file'}]))
          expect(Secret::Hider.instance.hidden_copy(result.transfer_spec)['remote_password']).not_to(eq('<PASSWORD>'))
        end

        it 'refuses a command that changes something before the transfer' do
          expect { build_transfer_agent(['--dry-run=yes']).assert_no_dry_run }.to(raise_error(Cli::BadArgument, /dry_run is not supported/))
          expect { build_transfer_agent([]).assert_no_dry_run }.not_to(raise_error)
        end
      end
    end
  end
end
