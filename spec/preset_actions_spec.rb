# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/cli/preset_actions'
require_relative '../lib/aspera/cli/vault_actions'
require_relative '../lib/aspera/cli/result'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/option/value'
require_relative '../lib/aspera/cli/security'
require_relative '../lib/aspera/schema/registry'
require_relative '../lib/aspera/log'
require 'securerandom'

# Minimal host class that includes both mixins, backed by simple test doubles.
module Aspera
  module Cli
    RSpec.describe(PresetActions) do
      # -----------------------------------------------------------------------
      # Test host: includes the mixins and exposes injectable doubles
      # -----------------------------------------------------------------------
      let(:config_presets) { {} }
      # Values of secrets are generated, none in source
      let(:secret) { SecureRandom.alphanumeric(12) }
      let(:other) { SecureRandom.alphanumeric(12) }

      let(:presets_double) do
        double('presets', config_presets: config_presets, global_default_preset: 'GLOBAL').tap do |d|
          allow(d).to(receive(:set_key)) do |preset, key, value|
            config_presets[preset] ||= {}
            # as PresetManager#set_key: nil removes the key
            value.nil? ? config_presets[preset].delete(key) : config_presets[preset][key] = value
          end
          allow(d).to(receive(:global_preset?)) { |name| name.eql?('GLOBAL') }
        end
      end

      # A simple in-memory vault double
      let(:vault_store) { {} }
      let(:vault_double) do
        double('vault').tap do |v|
          allow(v).to(receive(:get)) do |label:, exception: true|
            vault_store[label]
          end
          allow(v).to(receive(:set)) do |entry|
            vault_store[entry[:label]] = entry
          end
        end
      end

      let(:host) do
        presets_captured = presets_double

        Class.new do
          include PresetActions
          include VaultActions

          define_method(:presets) { presets_captured }

          # options stub: vault option returns the double directly via a proc so
          # we can toggle it per example
          attr_writer :vault_option

          def options
            opts_self = self
            Object.new.tap do |o|
              o.define_singleton_method(:get_option) do |sym, mandatory: false|
                opts_self.vault_option if sym == :vault
              end
              o.define_singleton_method(:unprocessed_options_with_value) { |**| {} }
              o.define_singleton_method(:option_declared?) { |_name| false }
            end
          end

          # Override vault to return the injected double directly (bypass Factory)
          attr_writer :vault_double_override

          def vault
            return @vault_instance if @vault_instance_initialized
            @vault_instance_initialized = true
            @vault_instance = @vault_double_override
          end
        end.new
      end

      before do
        host.vault_double_override = nil # default: no vault
      end

      # -----------------------------------------------------------------------
      # secure_preset_option — the private helper
      # -----------------------------------------------------------------------
      describe '#secure_preset_option (via action_preset_secure)' do
        context 'when vault is not configured' do
          it 'leaves the preset value unchanged' do
            config_presets['mypreset'] = {'password' => secret} # HashiCorpIgnore
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['password']).to(eq(secret))
          end
        end

        context 'when vault is configured' do
          before { host.vault_double_override = vault_double }

          it 'moves a clear-text password into the vault and replaces it with a @vault: reference' do
            config_presets['mypreset'] = {'password' => secret} # HashiCorpIgnore
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['password']).to(eq('@vault:mypreset.password'))
            expect(vault_store['mypreset']).to(include(password: secret))
          end

          it 'moves a clear-text secret field into the vault' do
            config_presets['mypreset'] = {'api_secret' => secret}
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['api_secret']).to(eq('@vault:mypreset.password'))
          end

          it 'does not touch options whose name does not end with password or secret' do
            config_presets['mypreset'] = {'username' => 'alice'}
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['username']).to(eq('alice'))
            expect(vault_store).to(be_empty)
          end

          it 'skips values that are already @vault: references' do
            config_presets['mypreset'] = {'password' => '@vault:mypreset.password'}
            host.action_preset_secure(config_name: 'mypreset')
            # vault should not have been written
            expect(vault_store).to(be_empty)
          end

          it 'skips nil values' do
            config_presets['mypreset'] = {'password' => nil}
            host.action_preset_secure(config_name: 'mypreset')
            expect(vault_store).to(be_empty)
          end

          it 'increments the vault label when the base label is already taken' do
            vault_store['mypreset'] = {label: 'mypreset', password: other} # HashiCorpIgnore
            config_presets['mypreset'] = {'password' => secret} # HashiCorpIgnore
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['password']).to(eq('@vault:mypreset0.password'))
            expect(vault_store['mypreset0']).to(include(password: secret))
          end

          it 'leaves secrets of the global preset in clear without opening the vault' do
            config_presets['GLOBAL'] = {'secret' => secret}
            expect(host).not_to(receive(:vault))
            host.action_preset_secure(config_name: 'GLOBAL')
            expect(config_presets['GLOBAL']['secret']).to(eq(secret))
          end

          it 'refuses a preset that does not exist' do
            expect { host.action_preset_secure(config_name: 'missing') }.to(raise_error(Cli::BadArgument, /no such preset: missing/))
            expect(vault_store).to(be_empty)
          end

          it 'processes all presets when no config_name is given' do
            config_presets['preset_a'] = {'password' => secret} # HashiCorpIgnore
            config_presets['preset_b'] = {'password' => other} # HashiCorpIgnore
            host.action_preset_secure
            expect(config_presets['preset_a']['password']).to(eq('@vault:preset_a.password'))
            expect(config_presets['preset_b']['password']).to(eq('@vault:preset_b.password'))
          end
        end
      end

      # -----------------------------------------------------------------------
      # action_preset_update — automatic vault migration
      # -----------------------------------------------------------------------
      describe '#action_preset_update' do
        # Build a host whose options returns a fixed unprocessed hash
        def host_with_options(unprocessed_hash, vault_override: nil)
          presets_captured = presets_double
          vault_captured   = vault_override

          Class.new do
            include PresetActions
            include VaultActions

            define_method(:presets) { presets_captured }

            define_method(:options) do
              opts_hash = unprocessed_hash
              Object.new.tap do |o|
                o.define_singleton_method(:unprocessed_options_with_value) { |**| opts_hash }
                o.define_singleton_method(:option_declared?) { |_name| false }
                o.define_singleton_method(:get_option) { |*| nil }
              end
            end

            define_method(:vault) do
              return @vault_instance if @vault_instance_initialized
              @vault_instance_initialized = true
              @vault_instance = vault_captured
            end
          end.new
        end

        context 'without vault' do
          it 'saves the password in clear' do
            h = host_with_options({'password' => secret, 'username' => 'bob'})
            h.action_preset_update(name: 'p1')
            expect(config_presets['p1']['password']).to(eq(secret))
          end

          it 'does not declare the global preset' do
            expect(presets_double).not_to(receive(:global_default_preset))
            h = host_with_options({'password' => secret})
            h.action_preset_update(name: 'p1')
          end
        end

        context 'with a restricted security level' do
          after { Security.instance.reset }

          it 'refuses an extended value that the level refuses, which would be evaluated later at another level' do
            Security.instance.lock('in MCP server mode', default: :high)
            h = host_with_options({'ts' => '@val:@ruby:1+1'})
            expect { h.action_preset_update(name: 'p1') }.to(raise_error(BadArgument, /cannot store @ruby:/))
            expect(config_presets).to(be_empty)
          end

          it 'refuses command of option ui' do
            Security.instance.lock('in MCP server mode', default: :high)
            option = Option::Value.new(option: :ui, allowed: [Hash, String], schema: Schema::Registry::UI_OPTIONS)
            h = host_with_options({'ui' => {'command' => ['/bin/true']}})
            allow(h).to(receive(:options).and_return(double('options', unprocessed_options_with_value: {'ui' => {'command' => ['/bin/true']}}, option_declared?: true, option_def: option)))
            expect { h.action_preset_update(name: 'p1') }.to(raise_error(BadArgument, /option ui.command: disabled by security level high/))
            expect { h.action_preset_set(name: 'p1', param_name: 'ui.command', param_value: ['/bin/true']) }.to(raise_error(BadArgument, /ui.command/))
          end

          it 'refuses an option that requires a lower level' do
            Security.instance.lock('in MCP server mode', default: :high)
            h = host_with_options({'notify_template' => 'x'})
            option = Option::Value.new(option: :notify_template, security: :low)
            allow(h).to(receive(:options).and_return(double('options', unprocessed_options_with_value: {'notify_template' => 'x'}, option_declared?: true, option_def: option)))
            expect { h.action_preset_update(name: 'p1') }.to(raise_error(BadArgument, /option notify_template: disabled by security level high/))
          end
        end

        context 'with vault' do
          it 'automatically moves the password to the vault' do
            h = host_with_options({'password' => secret, 'username' => 'bob'}, vault_override: vault_double)
            h.action_preset_update(name: 'p1')
            expect(config_presets['p1']['password']).to(eq('@vault:p1.password'))
            expect(vault_store['p1']).to(include(password: secret))
          end

          it 'leaves non-secret fields in clear' do
            h = host_with_options({'password' => secret, 'username' => 'bob'}, vault_override: vault_double)
            h.action_preset_update(name: 'p1')
            expect(config_presets['p1']['username']).to(eq('bob'))
          end
        end

        context 'with options (deprecated)' do
          it 'warns with the set command to use, without secret value' do
            h = host_with_options({'url' => 'https://a.example.com', 'password' => secret, 'out' => {'level' => 'data'}})
            expect(Log.log).to(receive(:warn)) do |&block|
              message = block.call
              expect(message).to(include('deprecated'))
              expect(message).to(include('ascli config preset set p1 @: url=https://a.example.com out.level=data'))
              expect(message).to(include('secret parameters'))
              expect(message).not_to(include(secret))
            end
            h.action_preset_update(name: 'p1')
            expect(config_presets['p1']['url']).to(eq('https://a.example.com'))
          end

          it 'quotes words of the command for a shell' do
            h = host_with_options({})
            expect(h.send(:set_command_hint, 'p 1', {'ts' => {'source' => "it's"}})).to(eq(%q{ascli config preset set 'p 1' @: 'ts.source=it'\''s'}))
          end
        end
      end

      # -----------------------------------------------------------------------
      # action_preset_delete — default declarations
      # -----------------------------------------------------------------------
      describe '#action_preset_delete' do
        it 'removes default declarations referring to the deleted preset' do
          config_presets['p1'] = {'url' => 'https://example.com'}
          config_presets['p2'] = {}
          config_presets['default'] = {'aoc' => 'p1', 'node' => 'p1', 'server' => 'p2'}
          host.action_preset_delete(name: 'p1')
          expect(config_presets.key?('p1')).to(be(false))
          expect(config_presets['default']).to(eq({'server' => 'p2'}))
        end
      end

      # -----------------------------------------------------------------------
      # action_preset_get — scalar secret is declared (no key name in Result::Text)
      # -----------------------------------------------------------------------
      describe '#action_preset_get' do
        # Values of secrets are generated, none in source: short, so hidden only as a whole string
        let(:secret) { SecureRandom.alphanumeric(6) }
        let(:username) { SecureRandom.alphanumeric(6) }

        before { config_presets['p1'] = {'username' => username, 'password' => secret} } # HashiCorpIgnore

        it 'declares a secret value' do
          expect(host.action_preset_get(name: 'p1', param_name: 'password').data).to(eq(secret))
          expect(Secret::Hider.instance.hidden_copy(secret)).not_to(eq(secret))
        end

        it 'does not declare a non-secret value' do
          expect(host.action_preset_get(name: 'p1', param_name: 'username').data).to(eq(username))
          expect(Secret::Hider.instance.hidden_copy(username)).to(eq(username))
        end
      end

      # -----------------------------------------------------------------------
      # GLOBAL keyword: global default preset, created only by actions writing in it
      # -----------------------------------------------------------------------
      describe 'GLOBAL preset name' do
        before { config_presets['GLOBAL'] = {'url' => 'https://example.com'} }

        it 'does not create the global preset when reading it' do
          host.action_preset_show(name: 'GLOBAL')
          host.action_preset_get(name: 'GLOBAL', param_name: 'url')
          expect(presets_double).to(have_received(:global_default_preset).with(create: false).twice)
        end

        it 'creates the global preset when writing in it' do
          host.action_preset_set(name: 'GLOBAL', param_name: 'format', param_value: 'json')
          expect(presets_double).to(have_received(:global_default_preset).with(create: true))
        end

        it 'raises BadArgument for an unknown preset' do
          expect { host.action_preset_show(name: 'nope') }.to(raise_error(BadArgument, /no such preset: nope/))
        end
      end

      # -----------------------------------------------------------------------
      # action_preset_set — automatic vault migration
      # -----------------------------------------------------------------------
      describe '#action_preset_set' do
        before { config_presets['p1'] = {} }

        context 'with vault' do
          before { host.vault_double_override = vault_double }

          it 'automatically secures a password set via action_preset_set' do
            host.action_preset_set(name: 'p1', param_name: 'password', param_value: secret)
            expect(config_presets['p1']['password']).to(eq('@vault:p1.password'))
          end

          it 'does not alter a non-secret option' do
            host.action_preset_set(name: 'p1', param_name: 'url', param_value: 'https://example.com')
            expect(config_presets['p1']['url']).to(eq('https://example.com'))
            expect(vault_store).to(be_empty)
          end
        end

        # Converted, or split with dot-notation, a secret as key name would not be hidden in results
        context 'with a secret as parameter name' do
          before { Secret::Hider.instance.add_secret_values(secret) }

          after { Security.instance.reset }

          %w[medium high].each do |level|
            it "is refused with level #{level}" do
              Security.instance.options = {'level' => level}
              expect { host.action_preset_set(name: 'p1', param_name: secret, param_value: 'v') }
                .to(raise_error(BadArgument, /preset parameter name: cannot process a secret at security level #{level}.*give a name that is not a secret/))
              expect(config_presets['p1']).to(be_empty)
            end
          end

          it 'is allowed with level low' do
            host.action_preset_set(name: 'p1', param_name: secret, param_value: 'v')
            expect(config_presets['p1']).to(eq({secret => 'v'}))
          end
        end

        context 'with a Hash of parameters' do
          it 'merges deeply, with option names converted, and removes keys with nil' do
            config_presets['p1'] = {'url' => 'https://a.example.com', 'username' => 'bob', 'out' => {'format' => 'json', 'level' => 'data'}}
            host.action_preset_set(name: 'p1', param_name: {'username' => nil, 'out' => {'level' => nil, 'pivot' => 'single'}, 'log-level' => 'info'})
            expect(config_presets['p1']).to(eq({'url' => 'https://a.example.com', 'out' => {'format' => 'json', 'pivot' => 'single'}, 'log_level' => 'info'}))
          end

          it 'refuses a third argument' do
            expect { host.action_preset_set(name: 'p1', param_name: {'a' => 1}, param_value: 'x') }.to(raise_error(BadArgument, /no other argument/))
          end
        end

        context 'with a Hash of presets' do
          it 'merges into several presets, and deletes a preset with nil, and its default declarations' do
            config_presets['p2'] = {'url' => 'https://b.example.com'}
            config_presets['default'] = {'server' => 'p2', 'aoc' => 'p1'}
            host.action_preset_set(name: {'p1' => {'url' => 'https://a.example.com'}, 'p2' => nil})
            expect(config_presets['p1']).to(eq({'url' => 'https://a.example.com'}))
            expect(config_presets.key?('p2')).to(be(false))
            expect(config_presets['default']).to(eq({'aoc' => 'p1'}))
          end

          it 'refuses to change the config section' do
            expect { host.action_preset_set(name: {'config' => {'version' => 'x'}}) }.to(raise_error(BadArgument, /section config/))
          end

          it 'refuses a value that is not a Hash' do
            expect { host.action_preset_set(name: {'p1' => 'x'}) }.to(raise_error(BadArgument, /parameters of preset p1/))
          end
        end

        context 'with a parameter name' do
          it 'removes the parameter with nil' do
            config_presets['p1'] = {'url' => 'https://a.example.com', 'username' => 'bob'}
            host.action_preset_set(name: 'p1', param_name: 'username', param_value: nil)
            expect(config_presets['p1']).to(eq({'url' => 'https://a.example.com'}))
          end

          it 'requires a Hash or a parameter' do
            expect { host.action_preset_set(name: 'p1') }.to(raise_error(BadArgument, /expecting <Hash> of parameters/))
          end
        end
      end
    end
  end
end
