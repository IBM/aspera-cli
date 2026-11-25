# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Security levels `medium` and `high` (MCP server): a secret of the configuration is sent only to a URL of the configuration, and the configuration is read-only.
# Full command line with a configuration file in a temporary home: no server, the REST call is stubbed.

require_relative '../lib/aspera/cli/runner'
require_relative '../lib/aspera/plugins/node/commands'
require_relative '../lib/aspera/plugins/server/commands'
require 'securerandom'
require 'fileutils'
require 'tmpdir'
require 'yaml'

module Aspera
  module Cli
    RSpec.describe(Security) do
      # Message of a credential refused
      refused = /option password: a secret of the configuration cannot be sent to a URL that is not in the configuration at security level high/
      let(:secret) { SecureRandom.hex(16) }
      let(:server_url) { 'https://server.example.com' }
      let(:client_url) { 'https://elsewhere.example.com' }
      # Configuration file of the server: the presets of the operator
      let(:presets) do
        {
          'config'   => {'version' => VERSION},
          'myserver' => {'url' => server_url, 'username' => 'user1', 'password' => secret},
          'srv'      => {'url' => 'ssh://server.example.com:33001', 'username' => 'user1', 'password' => secret},
          'mynode'   => {'agent' => 'node', 'url' => 'https://node.example.com', 'username' => 'ak1', 'password' => SecureRandom.hex(16)}
        }
      end

      # Main folder, with the configuration file of the server
      let(:home) { Dir.mktmpdir }
      let(:config_file) { File.join(home, 'config.yaml') }

      before do
        File.write(config_file, presets.to_yaml)
        stub_const('ENV', ENV.to_h.merge('ASCLI_HOME' => home))
        # URL of the REST calls, instead of a call
        allow_any_instance_of(Rest::Client).to(receive(:call) { |client, **| raise Error, "called: #{client.base_url}" })
      end

      after do
        described_class.instance.reset
        FileUtils.rm_rf(home)
      end

      # @return [Result] result of the command line at level high
      def run(*argv)
        Runner.new([*argv, '--security.level=high', '--version-check-days=0']).run_with_result
      end

      it 'sends the secret of a preset to its URL' do
        expect { run('node', 'browse', '/', '--preset=myserver') }.to(raise_error(Error, "called: #{server_url}"))
      end

      it 'sends the secret of a preset to the same URL given on the command line' do
        expect { run('node', 'browse', '/', '--preset=myserver', "--url=#{server_url}") }.to(raise_error(Error, "called: #{server_url}"))
      end

      it 'sends the own secret of the client anywhere' do
        expect { run('node', 'browse', '/', "--url=#{client_url}", '--username=user1', "--password=#{SecureRandom.hex(16)}") }.to(raise_error(Error, "called: #{client_url}"))
      end

      it 'refuses the secret of a preset with another URL' do
        expect { run('node', 'browse', '/', '--preset=myserver', "--url=#{client_url}") }.to(raise_error(BadArgument, refused))
      end

      it 'refuses the secret of a preset referenced by @preset:, with another URL' do
        expect { run('node', 'browse', '/', "--url=#{client_url}", '--username=user1', '--password=@preset:myserver.password') }.to(raise_error(BadArgument, refused))
      end

      it 'refuses the secret of a preset referenced in a preset given by the client' do
        client_preset = JSON.generate({'url' => client_url, 'username' => 'user1', 'password' => '@preset:myserver.password'})
        expect { run('node', 'browse', '/', "--preset=@json:#{client_preset}") }.to(raise_error(BadArgument, refused))
      end

      # Upload with agent `node` (a remote agent, as required at level high), without transfer
      def upload(*argv)
        file = File.join(home, 'file.txt')
        File.write(file, 'content')
        run('server', 'upload', file, '--to-folder=/', '--preset=srv', *argv)
      end

      it 'refuses option ts that sends the credentials of the command to another host' do
        expect { upload('--ts=@json:{"remote_host":"elsewhere.example.com"}', '--transfer=@preset:mynode', '--dry-run=yes') }
          .to(raise_error(BadArgument, /option ts: remote_host: the credentials of the transfer \(remote_password\) cannot be sent to a host that is not in the configuration/))
      end

      it 'accepts option ts with the host of the command' do
        expect { upload('--ts=@json:{"remote_host":"server.example.com"}', '--transfer=@preset:mynode', '--dry-run=yes') }.not_to(raise_error)
      end

      it 'refuses the secret of agent node of a preset with another URL' do
        expect { upload('--transfer=@preset:mynode', "--transfer.url=#{client_url}") }.to(raise_error(BadArgument, /option transfer: password: a secret of the configuration cannot be sent/))
      end

      it 'sends the secret of agent node of a preset to its URL' do
        expect { upload('--transfer=@preset:mynode') }.to(raise_error(Error, 'called: https://node.example.com'))
      end

      it 'does not change the configuration' do
        expect { run('config', 'preset', 'set', 'myserver', 'url', client_url) }.to(raise_error(BadArgument, /command preset set: disabled by security level high/))
        expect { run('config', 'preset', 'delete', 'myserver') }.to(raise_error(BadArgument, /command preset delete: disabled by security level high/))
        expect { run('config', 'vault', 'create', '@json:{"label":"x","password":"y"}') }.to(raise_error(BadArgument, /command vault create: disabled by security level high/))
        expect(YAML.load_file(config_file)).to(eq(presets))
      end

      it 'still reads the configuration' do
        expect(run('config', 'preset', 'show', 'myserver').data).to(include('url' => server_url))
      end

      # The configuration is read-only: its presets are the ones of the operator, also for an option available at level low only
      context 'with an option of level low in the configuration' do
        let(:presets) do
          super().merge(
            'default'     => {'config' => 'cli_default'},
            'cli_default' => {'ignore_certificate' => [server_url]},
            'lab'         => {'url' => server_url, 'username' => 'user1', 'password' => secret, 'insecure' => true}
          )
        end

        it 'accepts it in the default preset' do
          expect { run('node', 'browse', '/', '--preset=myserver') }.to(raise_error(Error, "called: #{server_url}"))
        end

        it 'accepts it in a preset given by name' do
          expect { run('node', 'browse', '/', '--preset=lab') }.to(raise_error(Error, "called: #{server_url}"))
        end

        it 'refuses it in a preset given as a Hash' do
          client_preset = JSON.generate({'url' => server_url, 'insecure' => true})
          expect { run('node', 'browse', '/', "--preset=@json:#{client_preset}") }.to(raise_error(BadArgument, /option insecure: disabled by security level high/))
        end

        it 'refuses it on the command line' do
          expect { run('node', 'browse', '/', '--preset=myserver', '--insecure=yes') }.to(raise_error(BadArgument, /option insecure: disabled by security level high/))
        end
      end

      it 'refuses to save a configuration changed by a command' do
        manager = PresetManager.new(config_file: config_file)
        manager.set_key('myserver', 'url', client_url)
        described_class.instance.options = {'level' => 'high'}
        expect { manager.save_if_needed }.to(raise_error(BadArgument, /saving the configuration file: disabled by security level high/))
        described_class.instance.options = {'level' => 'low'}
        expect(manager.save_if_needed).to(be(true))
      end
    end
  end
end
