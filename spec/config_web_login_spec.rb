# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/cli/plugins/config'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/persistency_folder'
require_relative '../lib/aspera/web_auth/blob'

module Aspera
  module Cli
    module Plugins
      # Command `config web_login`: login on the workstation for `ascli` that runs on another host
      RSpec.describe(Config) do
        let(:persisted) { {} }
        let(:persistency) do
          instance_double(PersistencyFolder).tap do |p|
            allow(p).to(receive(:get)) { |id| persisted[id] }
            allow(p).to(receive(:put)) { |id, value| persisted[id] = value }
          end
        end
        let(:config) do
          # without the initialization of the plugin: the action needs only `context`
          described_class.allocate.tap { |c| allow(c).to(receive(:context).and_return(instance_double(Context, persistency: persistency))) }
        end
        let(:login_data) { {'login_url' => 'https://idp.example.com/authorize?a=1', 'redirect_uri' => 'http://localhost:12345/', 'reply_keys' => %w[code state]} }
        let(:login_code) { WebAuth::Blob.encode(:login, login_data) }
        let(:hosts_id) { described_class.const_get(:WEB_LOGIN_HOSTS_ID) }

        before do
          allow(WebAuth::Relay).to(receive(:run))
          allow(Log.log).to(receive(:warn))
        end

        it 'is a command reserved to security level low' do
          expect(described_class.command_registry[[:web_login]].security).to(eq(:low))
        end

        it 'asks to trust the host the first time, then does not ask again' do
          allow($stdin).to(receive(:tty?).and_return(true))
          allow(Prompt).to(receive(:prompt_user_input).and_return('yes'))
          config.action_web_login(code: login_code)
          expect(Log.log).to(have_received(:warn))
          expect(WebAuth::Relay).to(have_received(:run).once)
          expect(persisted[hosts_id]).to(eq('idp.example.com'))
          config.action_web_login(code: login_code)
          expect(Prompt).to(have_received(:prompt_user_input).once)
          expect(WebAuth::Relay).to(have_received(:run).twice)
        end

        it 'does not open the page if the user refuses the host' do
          allow($stdin).to(receive(:tty?).and_return(true))
          allow(Prompt).to(receive(:prompt_user_input).and_return('no'))
          expect { config.action_web_login(code: login_code) }.to(raise_error(BadArgument, /refused/))
          expect(WebAuth::Relay).not_to(have_received(:run))
          expect(persisted).to(be_empty)
        end

        it 'refuses an unknown host without terminal' do
          allow($stdin).to(receive(:tty?).and_return(false))
          expect { config.action_web_login(code: login_code) }.to(raise_error(BadArgument, /not known/))
          expect(WebAuth::Relay).not_to(have_received(:run))
        end

        it 'does not ask for a host already trusted' do
          persisted[hosts_id] = "other.example.com\nidp.example.com"
          allow($stdin).to(receive(:tty?).and_return(false))
          expect(config.action_web_login(code: login_code)).to(be_a(Result::Status))
          expect(WebAuth::Relay).to(have_received(:run))
        end

        it 'refuses a reply code, for the remote ascli' do
          expect { config.action_web_login(code: WebAuth::Blob.encode(:reply, {'state' => 'x'})) }.to(raise_error(BadArgument, /waits for the login/))
        end

        it 'refuses a damaged code' do
          expect { config.action_web_login(code: login_code[0..-6]) }.to(raise_error(BadArgument))
        end

        it 'refuses a login page that is not https, without asking' do
          allow(Prompt).to(receive(:prompt_user_input))
          code = WebAuth::Blob.encode(:login, login_data.merge('login_url' => 'http://idp.example.com/'))
          expect { config.action_web_login(code: code) }.to(raise_error(BadArgument, /https/))
          expect(Prompt).not_to(have_received(:prompt_user_input))
        end

        it 'reports that the port is used' do
          persisted[hosts_id] = 'idp.example.com'
          allow(WebAuth::Relay).to(receive(:run).and_raise(Errno::EADDRINUSE))
          expect { config.action_web_login(code: login_code) }.to(raise_error(Error, /port is used/))
        end
      end
    end
  end
end
