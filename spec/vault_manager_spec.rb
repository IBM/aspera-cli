# frozen_string_literal: true

require 'tmpdir'
require 'securerandom'
require 'aspera/cli/vault_manager'
require 'aspera/secret/store/encrypted_hash'

module Aspera
  module Cli
    RSpec.describe(VaultManager) do
      # Values of secrets are generated, none in source
      let(:secret) { SecureRandom.alphanumeric(16) }
      let(:username) { SecureRandom.alphanumeric(16) }
      let(:vault_password) { SecureRandom.alphanumeric(16) }
      let(:main_folder) { Dir.mktmpdir }
      # Values of options, changed by examples
      let(:values) { {} }
      let(:options) do
        option_values = values
        Object.new.tap do |o|
          o.define_singleton_method(:get_option) { |name, mandatory: false| option_values[name] } # rubocop:disable Lint/UnusedBlockArgument
        end
      end
      let(:manager) { described_class.new(options, main_folder) }

      before do
        Secret::Store::EncryptedHash.new(file: File.join(main_folder, 'ops.bin'), password: vault_password)
          .set({label: 'my.preset', username: username, password: secret})
      end

      after { FileUtils.rm_rf(main_folder) }

      describe '#store' do
        it 'is nil when not configured, and opened when configured later' do
          expect(manager.store).to(be_nil)
          values.merge!(vault: {'type' => 'file', 'name' => 'ops.bin'}, vault_password: vault_password)
          expect(manager.store).to(be_a(Secret::Store::EncryptedHash))
        end

        it 'is not opened with an empty Hash (@none:)' do
          values[:vault] = {}
          expect(manager.store).to(be_nil)
        end

        it 'raises BadArgument when mandatory and not configured' do
          expect { manager.store(mandatory: true) }.to(raise_error(BadArgument, 'Missing mandatory option: vault'))
        end
      end

      describe '#value' do
        context 'with a label' do
          before { values.merge!(vault: {'type' => 'file', 'name' => 'ops.bin'}, vault_password: vault_password) }

          it 'reads a field of a label containing dots' do
            expect(manager.value('my.preset.password')).to(eq(secret))
            expect(manager.value('my.preset.username')).to(eq(username))
          end

          it 'raises BadArgument without field' do
            expect { manager.value('my_preset') }.to(raise_error(BadArgument, /<name>.<param>/))
          end
        end

        context 'with a reference' do
          before do
            values[:vault_references] = {'cache_ttl' => 0, 'stores' => {'ops' => {'type' => 'file', 'file' => 'ops.bin', 'password' => vault_password}}}
          end

          it 'reads a field from a store, file relative to the configuration folder, password by default' do
            expect(manager.value('//ops/my.preset')).to(eq(secret))
            expect(manager.value('//ops/my.preset#username')).to(eq(username))
          end

          it 'gives the reference in errors' do
            expect { manager.value('//ops/missing') }.to(raise_error(Secret::Error, 'secret reference secret://ops/missing: no label: missing'))
            expect { manager.value('//other/my.preset') }.to(raise_error(Secret::Error, /unknown store other/))
          end

          it 'does not need option vault' do
            expect(manager.value('//ops/my.preset')).to(eq(secret))
            expect(manager.store).to(be_nil)
          end
        end

        it 'raises BadArgument for a reference without option vault_references' do
          expect { manager.value('//ops/my.preset') }.to(raise_error(BadArgument, 'Missing mandatory option: vault_references'))
        end
      end

      # `@file:` in parameters of stores is read by the library: checked as extended value `@file:`
      describe 'option security' do
        let(:password_file) { File.join(main_folder, 'ops.pass') }
        let(:other_file) { File.join(main_folder, 'other') }

        before do
          File.write(password_file, vault_password)
          File.write(other_file, 'x')
          values[:vault_references] = {'cache_ttl' => 0, 'stores' => {'ops' => {'type' => 'file', 'file' => 'ops.bin', 'password' => "@file:#{password_file}"}}}
        end

        after { Security.instance.reset }

        it 'reads @file: with level low' do
          expect(manager.value('//ops/my.preset')).to(eq(secret))
        end

        it 'refuses @file: with level high' do
          Security.instance.options = {'level' => 'high'}
          expect { manager.value('//ops/my.preset') }.to(raise_error(BadArgument, /\Aoption vault_references: @file: extended value is disabled by security level high/))
        end

        it 'reads @file: with level medium only in allowed paths' do
          Security.instance.options = {'level' => 'medium', 'allowed_paths' => [other_file]}
          expect { manager.value('//ops/my.preset') }.to(raise_error(BadArgument, /\Aoption vault_references: no such file in security.allowed_paths/))
          Security.instance.options = {'level' => 'medium', 'allowed_paths' => [password_file]}
          expect(described_class.new(options, main_folder).value('//ops/my.preset')).to(eq(secret))
        end

        it 'refuses @file: in option vault, also as token from vault_password, with level high' do
          Security.instance.options = {'level' => 'high'}
          values[:vault] = {'type' => 'vault', 'url' => 'https://127.0.0.1:8200', 'token' => "@file:#{password_file}"}
          expect { manager.store }.to(raise_error(BadArgument, /\Aoption vault: @file: extended value is disabled/))
          values.merge!(vault: {'type' => 'vault', 'url' => 'https://127.0.0.1:8200'}, vault_password: "@file:#{password_file}")
          expect { manager.store }.to(raise_error(BadArgument, /\Aoption vault_password: @file: extended value is disabled/))
        end
      end

      describe '#metadata' do
        before do
          values[:vault_references] = {'stores' => {'ops' => {'type' => 'file', 'file' => File.join(main_folder, 'ops.bin'), 'password' => vault_password}}}
        end

        it 'gives the store and the time of update, without value' do
          expect(manager.metadata('//ops/my.preset')).to(eq({store: 'ops', version: nil, updated_time: File.mtime(File.join(main_folder, 'ops.bin'))}))
        end

        it 'refuses a label' do
          expect { manager.metadata('my.preset.password') }.to(raise_error(BadArgument, /expecting a reference/))
        end
      end
    end
  end
end
