# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for the base options of agents (`Agent::Base#initialize`), given the same way to every agent by `Plugins::Transfer::TransferAgent`,
# and for the async contract of agents: `transfer_id`, `async_params`, `in_process?`.
# No transfer is started: REST clients are doubled.

require_relative '../lib/aspera/agent/base'
require_relative '../lib/aspera/plugins/direct/agent'
require_relative '../lib/aspera/plugins/httpgw/agent'
require_relative '../lib/aspera/agent/node'
require_relative '../lib/aspera/plugins/desktop/agent'
require_relative '../lib/aspera/plugins/connect/agent'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/plugins/transfer/transfer_agent'
require 'securerandom'

module Aspera
  RSpec.describe(Agent::Base) do
    # Base options, as given by the CLI
    let(:base_option_keys) { %i[progress progress_default config_dir check_ignore_cb trusted_certs preset_lookup url_provider] }
    # Minimal agent: only the methods required by Base
    let(:agent_class) do
      Class.new(described_class) do
        def start_transfer(_transfer_spec, token_regenerator: nil); end

        def wait_for_transfers_completion = []

        def notify(type) = notify_progress(type, session_id: nil, info: nil)
      end
    end
    let(:events) { [] }
    let(:progress) { double('progress').tap { |recorder| allow(recorder).to(receive(:event)) { |type, **| events.push(type) } } }

    it 'accepts every base option, and only them' do
      agent = agent_class.new(**base_option_keys.to_h { |key| [key, nil] })
      expect(agent.send(:config_dir)).to(be_nil)
      expect { agent_class.new(unknown: 1) }.to(raise_error(ArgumentError, /unknown keyword: :unknown/))
    end

    it 'keeps the base options for the agent' do
      check = ->(_host, _port) { true }
      provider = -> { 'https://gw.example.com' }
      agent = agent_class.new(config_dir: '/config', check_ignore_cb: check, trusted_certs: ['/certs'], url_provider: provider)
      expect(agent.send(:config_dir)).to(eq('/config'))
      expect(agent.send(:check_ignore_cb)).to(be(check))
      expect(agent.send(:trusted_certs)).to(eq(['/certs']))
      expect(agent.send(:url_provider)).to(be(provider))
    end

    it 'gives the values of a default preset with the preset lookup' do
      lookup = ->(plugin) { {'url' => "https://#{plugin}.example.com"} }
      expect(agent_class.new(preset_lookup: lookup).send(:preset_values, :node)).to(eq('url' => 'https://node.example.com'))
      expect(agent_class.new.send(:preset_values, :node)).to(be_nil)
    end

    it 'notifies progress, unless the agent displays its own progress and progress is a default choice' do
      agent_class.new(progress: progress).tap { |agent| agent.send(:own_progress_display) }.notify(:transfer)
      expect(events).to(eq([:transfer]))
      agent_class.new(progress: progress, progress_default: true).tap { |agent| agent.send(:own_progress_display) }.notify(:transfer)
      expect(events).to(eq([:transfer]))
      agent_class.new(progress: progress, progress_default: true).notify(:session_end)
      expect(events).to(eq(%i[transfer session_end]))
    end

    it 'has a default async contract: no transfer id, no runtime parameter, transfers out of the process' do
      agent = agent_class.new
      expect(agent.transfer_id).to(be_nil)
      expect(agent.async_params).to(eq({}))
      expect(agent.in_process?).to(be(false))
    end
  end

  RSpec.describe(Aspera::Plugins::Direct::Agent) do
    let(:events) { [] }
    let(:progress) { double('progress').tap { |recorder| allow(recorder).to(receive(:event)) { |type, **| events.push(type) } } }

    # @return [Array<Symbol>] Progress events received after a notification by the agent
    def events_of(agent)
      agent.send(:notify_progress, :transfer, session_id: nil, info: 0)
      events
    end

    it 'keeps the progress with its default `quiet`' do
      expect(events_of(described_class.new(progress: progress, progress_default: true))).to(eq([:transfer]))
    end

    it 'drops the progress for the native progress of `ascp`, if progress is a default choice' do
      expect(events_of(described_class.new(progress: progress, progress_default: true, quiet: false))).to(be_empty)
    end

    it 'keeps the progress with the native progress of `ascp`, if progress is requested' do
      expect(events_of(described_class.new(progress: progress, progress_default: false, quiet: false))).to(eq([:transfer]))
    end

    it 'gives base options `trusted_certs` and `check_ignore_cb` to the `ascp` parameters' do
      check = ->(_host, _port) { true }
      agent = described_class.new(trusted_certs: ['/certs/ca.pem'], check_ignore_cb: check)
      expect(agent.instance_variable_get(:@tr_opts)).to(include(trusted_certs: ['/certs/ca.pem'], check_ignore_cb: check))
    end

    it 'runs transfers in the process, with the job id as transfer id' do
      agent = described_class.new
      expect(agent.in_process?).to(be(true))
      expect(agent.async_params).to(eq({}))
      expect(agent.transfer_id).to(be_nil)
      agent.instance_variable_get(:@sessions).push({job_id: 'job-1'})
      expect(agent.transfer_id).to(eq('job-1'))
      expect(agent.transfer_id).to(eq(agent.last_job_id))
    end
  end

  RSpec.describe(Aspera::Plugins::Httpgw::Agent) do
    let(:gateway_urls) { [] }

    before do
      allow(Aspera::Plugins::Httpgw::Api).to(receive(:new)) do |url:, **|
        gateway_urls.push(url)
        instance_double(Aspera::Plugins::Httpgw::Api)
      end
    end

    it 'uses the given URL, without the URL provider' do
      provider = -> { raise 'not expected' }
      described_class.new(url: 'https://gw.example.com', url_provider: provider)
      expect(gateway_urls).to(eq(['https://gw.example.com']))
    end

    it 'takes the URL from the URL provider when `url` is not given' do
      described_class.new(url_provider: -> { 'https://app.example.com/gw' })
      expect(gateway_urls).to(eq(['https://app.example.com/gw']))
    end

    it 'requires a URL without URL provider' do
      expect { described_class.new }.to(raise_error(ArgumentError, 'missing keyword: :url'))
    end

    it 'runs transfers in the process, with the job id as transfer id' do
      agent = described_class.new(url: 'https://gw.example.com')
      expect(agent.in_process?).to(be(true))
      expect(agent.async_params).to(eq({}))
      agent.instance_variable_set(:@last_job_id, 'job-2')
      expect(agent.transfer_id).to(eq('job-2'))
    end
  end

  RSpec.describe(Agent::Node) do
    let(:rest_params) { [] }
    let(:rest) { instance_double(Rest::Client, base_url: 'https://node.example.com') }
    let(:password) { SecureRandom.alphanumeric(12) }

    before do
      allow(Rest::Client).to(receive(:new)) do |**params|
        rest_params.push(params)
        rest
      end
    end

    it 'uses the given URL, without the preset lookup' do
      described_class.new(url: 'https://node.example.com', username: 'u', password: password, preset_lookup: ->(_plugin) { raise 'not expected' })
      expect(rest_params.first).to(include(base_url: 'https://node.example.com', auth: {type: :basic, username: 'u', password: password}))
    end

    it 'takes the parameters of the default preset of plugin node when `url` is not given' do
      plugins = []
      lookup = ->(plugin) do
        plugins.push(plugin)
        {'url' => 'https://preset.example.com', 'username' => 'p', 'password' => password}
      end
      described_class.new(username: 'u', preset_lookup: lookup)
      expect(plugins).to(eq([:node]))
      expect(rest_params.first).to(include(base_url: 'https://preset.example.com', auth: {type: :basic, username: 'p', password: password}))
    end

    it 'requires a URL without preset lookup' do
      expect { described_class.new(username: 'u', password: password) }.to(raise_error(ArgumentError, /missing keyword: :url/))
    end

    it 'refuses an unknown parameter in the preset' do
      lookup = ->(_plugin) { {'url' => 'https://preset.example.com', 'username' => 'p', 'password' => password, 'other' => 1} }
      expect { described_class.new(preset_lookup: lookup) }.to(raise_error(ArgumentError, /unknown keyword: :other/))
    end

    it 'gives the transfer id of the node, transfers out of the process' do
      allow(rest).to(receive(:create).and_return({'id' => 'node-tid'}))
      agent = described_class.new(url: 'https://node.example.com', username: 'u', password: password)
      agent.start_transfer({'direction' => 'send', 'remote_host' => 'other.example.com', 'wss_enabled' => true})
      expect(agent.transfer_id).to(eq('node-tid'))
      expect(agent.async_params).to(eq({}))
      expect(agent.in_process?).to(be(false))
    end
  end

  RSpec.describe('async parameters of daemon agents') do
    it 'gives the application id of desktop' do
      agent = Aspera::Plugins::Desktop::Agent.allocate.tap { |a| a.instance_variable_set(:@application_id, 'app-1') }
      expect(agent.async_params).to(eq('application_id' => 'app-1'))
      expect(agent.in_process?).to(be(false))
    end

    it 'gives the app id of connect' do
      agent = Aspera::Plugins::Connect::Agent.allocate.tap { |a| a.instance_variable_set(:@connect_settings, {'app_id' => 'app-2'}) }
      expect(agent.async_params).to(eq('app_id' => 'app-2'))
      expect(agent.in_process?).to(be(false))
    end

    it 'gives the endpoint of transferd' do
      begin
        require_relative '../lib/aspera/plugins/transferd/agent'
      rescue LoadError => e
        skip("optional gem grpc: #{e.message}")
      end
      agent = Plugins::Transferd::Agent.allocate.tap do |a|
        a.instance_variable_set(:@daemon_endpoint, '127.0.0.1:55002')
        a.instance_variable_set(:@transfer_id, 'tid')
      end
      expect(agent.async_params).to(eq('url' => '127.0.0.1:55002'))
      expect(agent.transfer_id).to(eq('tid'))
      expect(agent.in_process?).to(be(false))
    end
  end

  module Cli
    RSpec.describe(Aspera::Plugins::Transfer::TransferAgent) do
      # Base options of `Agent::Base#initialize`
      let(:base_option_keys) { %i[progress progress_default config_dir check_ignore_cb trusted_certs preset_lookup url_provider] }
      let(:created) { [] }
      let(:http_config) { double('Http', trusted_cert_locations: ['/os/certs']) }
      let(:presets) { double('PresetManager') }
      let(:progress) { double('TransferProgress') }

      before do
        allow(Agent::Factory.instance).to(receive(:create)) do |type, options|
          created.push([type, options])
          double('agent')
        end
      end

      # @param argv [Array<String>] Command line
      # @return [TransferAgent] transfer agent with doubled context members
      def build_transfer_agent(argv)
        context = Context.new
        context.options = Parser.new('test', argv)
        # Declared by the config plugin and the bootstrapper
        context.options.declare(:notify_to, description: 'Notify')
        context.options.declare(:progress_bar, description: 'Display progress bar', allowed: Type::BOOLEAN, default: true)
        context.main_folder = '/config'
        context.http_config = http_config
        context.presets = presets
        context.progress_bar = progress
        described_class.new(context)
      end

      # @return [Hash] options given to the agent created for the command line
      def agent_options(argv)
        build_transfer_agent(argv).agent_instance
        created.last.last
      end

      it 'gives the same base options to every agent' do
        Agent::Factory::ALL.each_key do |type|
          options = agent_options(["--transfer=#{type}"])
          expect(created.last.first).to(eq(type))
          expect(options.keys).to(match_array(base_option_keys))
          expect(options).to(include(progress: progress, progress_default: true, config_dir: '/config', trusted_certs: ['/os/certs'], url_provider: nil))
        end
      end

      it 'tells that option progress_bar is set by the user' do
        expect(agent_options(['--progress-bar=no'])).to(include(progress_default: false))
      end

      it 'keeps parameter trusted_certs of option transfer' do
        expect(http_config).not_to(receive(:trusted_cert_locations))
        expect(agent_options(['--transfer=@json:{"agent":"direct","trusted_certs":["/my/certs"]}'])).to(include(trusted_certs: ['/my/certs']))
      end

      it 'keeps the agent parameters of option transfer' do
        options = agent_options(['--transfer=httpgw', '--transfer.url=https://gw.example.com', '--transfer.asynchronous=yes'])
        expect(options).to(include(url: 'https://gw.example.com'))
        expect(options).not_to(include(:agent, :asynchronous))
      end

      it 'checks certificates with the HTTP configuration' do
        allow(http_config).to(receive(:ignore_cert?).with('host.example.com', 443).and_return(true))
        expect(agent_options([])[:check_ignore_cb].call('host.example.com', 443)).to(be(true))
      end

      it 'gives the URL of the web application as URL provider' do
        ta = build_transfer_agent(['--transfer=httpgw'])
        ta.httpgw_url_cb = -> { 'https://app.example.com/gw' }
        ta.agent_instance
        expect(created.last.last[:url_provider].call).to(eq('https://app.example.com/gw'))
      end

      describe 'preset lookup' do
        it 'gives the values of the default preset of the plugin' do
          allow(presets).to(receive(:plugin_default_name).with(:node).and_return('my_node'))
          allow(presets).to(receive(:by_name).with('my_node').and_return({'url' => 'https://node.example.com'}))
          expect(agent_options(['--transfer=node'])[:preset_lookup].call(:node)).to(eq('url' => 'https://node.example.com'))
        end

        it 'raises the error of the CLI without default preset' do
          allow(presets).to(receive(:plugin_default_name).with(:node).and_return(nil))
          lookup = agent_options(['--transfer=node'])[:preset_lookup]
          expect { lookup.call(:node) }.to(raise_error(Cli::BadArgument, 'No default node configured. Please specify --transfer.url or --transfer'))
        end
      end
    end
  end
end
