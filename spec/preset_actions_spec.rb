# frozen_string_literal: true

require 'aspera/cli/preset_actions'
require 'aspera/cli/vault_manager'
require 'aspera/cli/result'
require 'aspera/cli/parser'
require 'aspera/log'

# Minimal host class that includes both mixins, backed by simple test doubles.
module Aspera
  module Cli
    RSpec.describe(PresetActions) do
      # -----------------------------------------------------------------------
      # Test host: includes the mixins and exposes injectable doubles
      # -----------------------------------------------------------------------
      let(:config_presets) { {} }

      let(:presets_double) do
        double('presets', config_presets: config_presets, global_default_preset: 'GLOBAL').tap do |d|
          allow(d).to(receive(:set_key)) do |preset, key, value|
            config_presets[preset] ||= {}
            config_presets[preset][key] = value
          end
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
        _presets = presets_double
        _vault   = vault_double

        Class.new do
          include PresetActions
          include VaultManager

          define_method(:presets) { _presets }

          # options stub: vault option returns the double directly via a proc so
          # we can toggle it per example
          attr_writer :vault_option

          def options
            _opts = self
            Object.new.tap do |o|
              o.define_singleton_method(:get_option) do |sym, mandatory: false|
                _opts.vault_option if sym == :vault
              end
              o.define_singleton_method(:unprocessed_options_with_value) { {} }
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
            config_presets['mypreset'] = {'password' => 'cleartext'}
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['password']).to(eq('cleartext'))
          end
        end

        context 'when vault is configured' do
          before { host.vault_double_override = vault_double }

          it 'moves a clear-text password into the vault and replaces it with a @vault: reference' do
            config_presets['mypreset'] = {'password' => 'secret123'}
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['password']).to(eq('@vault:mypreset.password'))
            expect(vault_store['mypreset']).to(include(password: 'secret123'))
          end

          it 'moves a clear-text secret field into the vault' do
            config_presets['mypreset'] = {'api_secret' => 'topsecret'}
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
            vault_store['mypreset'] = {label: 'mypreset', password: 'old'}
            config_presets['mypreset'] = {'password' => 'newpass'}
            host.action_preset_secure(config_name: 'mypreset')
            expect(config_presets['mypreset']['password']).to(eq('@vault:mypreset0.password'))
            expect(vault_store['mypreset0']).to(include(password: 'newpass'))
          end

          it 'processes all presets when no config_name is given' do
            config_presets['preset_a'] = {'password' => 'passA'}
            config_presets['preset_b'] = {'password' => 'passB'}
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
          _presets = presets_double
          _vault   = vault_override

          Class.new do
            include PresetActions
            include VaultManager

            define_method(:presets) { _presets }

            define_method(:options) do
              opts_hash = unprocessed_hash
              Object.new.tap do |o|
                o.define_singleton_method(:unprocessed_options_with_value) { opts_hash }
                o.define_singleton_method(:get_option) { |*| nil }
              end
            end

            define_method(:vault) do
              return @vault_instance if @vault_instance_initialized
              @vault_instance_initialized = true
              @vault_instance = _vault
            end
          end.new
        end

        context 'without vault' do
          it 'saves the password in clear' do
            h = host_with_options({'password' => 'mypass', 'username' => 'bob'})
            h.action_preset_update(name: 'p1')
            expect(config_presets['p1']['password']).to(eq('mypass'))
          end
        end

        context 'with vault' do
          it 'automatically moves the password to the vault' do
            h = host_with_options({'password' => 'mypass', 'username' => 'bob'}, vault_override: vault_double)
            h.action_preset_update(name: 'p1')
            expect(config_presets['p1']['password']).to(eq('@vault:p1.password'))
            expect(vault_store['p1']).to(include(password: 'mypass'))
          end

          it 'leaves non-secret fields in clear' do
            h = host_with_options({'password' => 'mypass', 'username' => 'bob'}, vault_override: vault_double)
            h.action_preset_update(name: 'p1')
            expect(config_presets['p1']['username']).to(eq('bob'))
          end
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
            host.action_preset_set(name: 'p1', param_name: 'password', param_value: 'abc')
            expect(config_presets['p1']['password']).to(eq('@vault:p1.password'))
          end

          it 'does not alter a non-secret option' do
            host.action_preset_set(name: 'p1', param_name: 'url', param_value: 'https://example.com')
            expect(config_presets['p1']['url']).to(eq('https://example.com'))
            expect(vault_store).to(be_empty)
          end
        end
      end

      # -----------------------------------------------------------------------
      # VaultManager#vault — lazy init and nil handling
      # -----------------------------------------------------------------------
      describe VaultManager do
        describe '#vault' do
          it 'returns nil when not configured and caches the result' do
            # host.vault already overridden by the test double mechanism above;
            # test the real behaviour via a raw includer
            includer = Class.new do
              include VaultManager
              def options
                Object.new.tap do |o|
                  o.define_singleton_method(:get_option) { |*| nil }
                end
              end
            end.new
            expect(includer.vault).to(be_nil)
            # second call must not re-invoke get_option (cached)
            expect(includer.vault).to(be_nil)
          end
        end

        describe '#vault_required' do
          it 'raises BadArgument when vault is nil' do
            includer = Class.new do
              include VaultManager
              def vault; nil; end
            end.new
            expect { includer.vault_required }.to(raise_error(Aspera::Cli::BadArgument, /vault/))
          end
        end
      end
    end
  end
end
