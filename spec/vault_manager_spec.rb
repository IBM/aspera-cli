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
      let(:other) { SecureRandom.alphanumeric(16) }
      let(:vault_password) { SecureRandom.alphanumeric(16) }
      let(:other_password) { SecureRandom.alphanumeric(16) }
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
        Secret::Store::EncryptedHash.new(file: File.join(main_folder, 'other.bin'), password: other_password)
          .set({label: 'app', password: other}) # HashiCorpIgnore
        allow(Log.log).to(receive(:warn))
      end

      after { FileUtils.rm_rf(main_folder) }

      describe '#store' do
        it 'is nil when not configured, and opened when configured later' do
          expect(manager.store).to(be_nil)
          values.merge!(vault: {'default' => 'ops', 'stores' => {'ops' => {'type' => 'file', 'file' => 'ops.bin'}}}, vault_password: vault_password)
          expect(manager.store).to(be_a(Secret::Store::EncryptedHash))
        end

        it 'is not opened with an empty Hash (@none:)' do
          values[:vault] = {}
          expect(manager.store).to(be_nil)
        end

        it 'raises BadArgument when mandatory and not configured' do
          expect { manager.store(mandatory: true) }.to(raise_error(BadArgument, 'Missing mandatory option: vault'))
        end

        it 'is the store given by default' do
          values[:vault] = {'default' => 'ops', 'stores' => {'ops' => {'type' => 'file', 'file' => 'ops.bin', 'password' => vault_password}}} # HashiCorpIgnore
          expect(manager.store.get(label: 'my.preset')[:password]).to(eq(secret))
        end

        it 'is nil without default, also with a store named default, and raises BadArgument when mandatory' do
          values[:vault] = {'stores' => {'default' => {'type' => 'file', 'file' => 'ops.bin', 'password' => vault_password}}} # HashiCorpIgnore
          expect(manager.store).to(be_nil)
          expect { manager.store(mandatory: true) }.to(raise_error(BadArgument, /no default store/))
        end

        it 'refuses a default that is not a store' do
          values[:vault] = {'default' => 'none', 'stores' => {}}
          expect { manager.store }.to(raise_error(BadArgument, 'option vault: default: no store none'))
        end

        it 'requires vault_password for a default store of type file without password' do
          values[:vault] = {'default' => 'ops', 'stores' => {'ops' => {'type' => 'file'}}}
          expect { manager.store }.to(raise_error(BadArgument, 'Missing mandatory option: vault_password'))
        end
      end

      describe '.convert_option' do
        it 'converts the parameters of one store (deprecated) to the default store, named after its type, file by default, with a warning' do
          expect(Log.log).to(receive(:warn).twice) { |&block| expect(block.call).to(match(/\Aoption vault: parameters of one store are deprecated after 4\.28\.0: set a store in stores/)) }
          expect(described_class.convert_option({name: 'ops.bin'})).to(eq({'default' => 'file', 'stores' => {'file' => {'name' => 'ops.bin', 'type' => 'file'}}}))
          # Parameters added to a value with stores, e.g. --vault.type=system
          expect(described_class.convert_option({'default' => 'ops', 'cache_ttl' => 0, 'stores' => {'ops' => {}}, 'type' => 'system'}))
            .to(eq({'default' => 'system', 'cache_ttl' => 0, 'stores' => {'ops' => {}, 'system' => {'type' => 'system'}}}))
        end

        it 'keeps a value with stores, without warning' do
          expect(Log.log).not_to(receive(:warn))
          value = {'default' => 'ops', 'stores' => {'ops' => {'type' => 'file'}}}
          expect(described_class.convert_option(value)).to(eq(value))
          expect(described_class.convert_option({})).to(eq({}))
        end

        it 'gives a default store with name or file' do
          [{'name' => 'ops.bin'}, {'type' => 'file', 'file' => File.join(main_folder, 'ops.bin')}].each do |vault|
            values.merge!(vault: described_class.convert_option(vault), vault_password: vault_password)
            manager = described_class.new(options, main_folder)
            expect(manager.value('my.preset.password')).to(eq(secret))
            expect(manager.value('//file/my.preset#username')).to(eq(username))
          end
        end
      end

      describe '#value' do
        before do
          values.merge!(
            vault: {'default' => 'ops', 'cache_ttl' => 0, 'stores' => {'ops' => {'type' => 'file', 'file' => 'ops.bin'}, 'other' => {'type' => 'file', 'file' => 'other.bin', 'password' => other_password}}}, # HashiCorpIgnore
            vault_password: vault_password
          )
        end

        it 'reads a field of a label containing dots in the default store' do
          expect(manager.value('my.preset.password')).to(eq(secret))
          expect(manager.value('my.preset.username')).to(eq(username))
        end

        it 'raises BadArgument without field' do
          expect { manager.value('my_preset') }.to(raise_error(BadArgument, /<name>.<param>/))
        end

        it 'reads a reference to any store, file relative to the configuration folder, password by default' do
          expect(manager.value('//ops/my.preset')).to(eq(secret))
          expect(manager.value('//other/app')).to(eq(other))
        end

        it 'gives the reference in errors' do
          expect { manager.value('//ops/missing') }.to(raise_error(Secret::Error, 'secret reference secret://ops/missing: no label: missing'))
          expect { manager.value('//none/my.preset') }.to(raise_error(Secret::Error, /unknown store none/))
        end

        it 'uses vault_password only for the default store, after its password' do
          values[:vault]['stores']['other'].delete('password')
          expect { manager.value('//other/app') }.to(raise_error(Secret::Error, /store other: password: expecting /)) # HashiCorpIgnore
          # vault_password is the password of ops.bin
          values[:vault].merge!('default' => 'other', 'stores' => {'other' => {'type' => 'file', 'file' => 'other.bin', 'password' => other_password}}) # HashiCorpIgnore
          expect(described_class.new(options, main_folder).value('app.password')).to(eq(other))
        end

        it 'raises BadArgument for a reference without option vault' do
          values.delete(:vault)
          expect { manager.value('//ops/my.preset') }.to(raise_error(BadArgument, 'Missing mandatory option: vault'))
        end
      end

      # `@file:` in parameters of stores is read by the library: checked as extended value `@file:`
      describe 'option security' do
        let(:password_file) { File.join(main_folder, 'ops.pass') }
        let(:allowed_file) { File.join(main_folder, 'allowed') }

        before do
          File.write(password_file, vault_password)
          File.write(allowed_file, 'x')
          values[:vault] = {'cache_ttl' => 0, 'stores' => {'ops' => {'type' => 'file', 'file' => 'ops.bin', 'password' => "@file:#{password_file}"}}}
        end

        after { Security.instance.reset }

        it 'reads @file: with level low' do
          expect(manager.value('//ops/my.preset')).to(eq(secret))
        end

        it 'refuses @file: with level high' do
          Security.instance.options = {'level' => 'high'}
          expect { manager.value('//ops/my.preset') }.to(raise_error(BadArgument, /\Aoption vault: @file: extended value is disabled by security level high/))
        end

        it 'reads @file: with level medium only in allowed paths' do
          Security.instance.options = {'level' => 'medium', 'allowed_paths' => [allowed_file]}
          expect { manager.value('//ops/my.preset') }.to(raise_error(BadArgument, /\Aoption vault: no such file in security.allowed_paths/))
          Security.instance.options = {'level' => 'medium', 'allowed_paths' => [password_file]}
          expect(described_class.new(options, main_folder).value('//ops/my.preset')).to(eq(secret))
        end

        it 'refuses @file: as token, also from vault_password, with level high' do
          Security.instance.options = {'level' => 'high'}
          values[:vault] = {'default' => 'v', 'stores' => {'v' => {'type' => 'vault', 'url' => 'https://127.0.0.1:8200', 'token' => "@file:#{password_file}"}}}
          expect { manager.store }.to(raise_error(BadArgument, /\Aoption vault: @file: extended value is disabled/))
          values.merge!(vault: {'default' => 'v', 'stores' => {'v' => {'type' => 'vault', 'url' => 'https://127.0.0.1:8200'}}}, vault_password: "@file:#{password_file}")
          expect { manager.store }.to(raise_error(BadArgument, /\Aoption vault_password: @file: extended value is disabled/)) # HashiCorpIgnore
        end
      end

      describe '#metadata' do
        before do
          values[:vault] = {'stores' => {'ops' => {'type' => 'file', 'file' => File.join(main_folder, 'ops.bin'), 'password' => vault_password}}} # HashiCorpIgnore
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
