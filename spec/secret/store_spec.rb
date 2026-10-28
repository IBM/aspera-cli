# frozen_string_literal: true

# Unit tests for Aspera::Secret::Store backends — no server, keychain or `op` needed.

require 'tmpdir'
require 'yaml'
require 'json'
require 'securerandom'
require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/secret/store/encrypted_hash'
require 'aspera/secret/store/macos_security'
require 'aspera/secret/store/one_password_cli'
require 'aspera/secret/store/hashicorp_vault'

RSpec.describe(Aspera::Secret::Store) do
  let(:success) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  # Values of secrets are generated, none in source
  let(:secret) { SecureRandom.alphanumeric(12) }
  let(:other) { SecureRandom.alphanumeric(12) }
  let(:vault_password) { SecureRandom.alphanumeric(12) }

  def failure(code) = instance_double(Process::Status, success?: false, exitstatus: code)

  # Simulates a failed command, raising like `secure_execute` unless `exception: false`
  def stub_failed_execute(stderr, code)
    allow(Aspera::Environment).to(receive(:secure_execute)) do |*_args, exception: true, **|
      raise "Process failed: #{code} (#{stderr})" if exception
      ['', stderr, failure(code)]
    end
  end

  describe Aspera::Secret::Store::EncryptedHash do
    it 'migrates a legacy vault (no kdf) to PBKDF2 on password change' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'vault.bin')
        # v4.26.0 format: key is the password zero-padded, no kdf field
        legacy_key = "#{vault_password}#{"\x00" * 32}"[0, 32]
        data = described_class::OsslCipher.new('aes-256-cbc', legacy_key).encrypt(YAML.dump({'my_label' => {password: secret}}))
        File.write(path, YAML.dump({'version' => '1.0.0', 'type' => 'encrypted_hash_vault', 'cipher' => 'aes-256-cbc', 'data' => data}))
        described_class.new(file: path, password: vault_password).change_password(other)
        expect(YAML.load_file(path)['kdf']).to(include('algo' => 'PBKDF2'))
        expect(described_class.new(file: path, password: other).get(label: 'my_label')[:password]).to(eq(secret))
      end
    end

    it 'refuses a vault file with Ruby objects' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'vault.bin')
        File.write(path, "--- !ruby/object:OpenStruct\ntable: {}\n")
        expect { described_class.new(file: path, password: vault_password) }.to(raise_error(Psych::DisallowedClass))
        File.write(path, "--- just a string\n")
        expect { described_class.new(file: path, password: vault_password) }.to(raise_error(/Invalid vault file/))
      end
    end

    it 'refuses to overwrite a secret and to delete a missing one' do
      Dir.mktmpdir do |dir|
        vault = described_class.new(file: File.join(dir, 'vault.bin'), password: vault_password)
        vault.set({label: 'my_label', password: secret})
        expect { vault.set({label: 'my_label', password: other}) }.to(raise_error(/already exist/)) # HashiCorpIgnore
        expect { vault.delete(label: 'missing') }.to(raise_error(/not found/))
      end
    end
  end

  describe Aspera::Secret::Store::MacosSystem do
    let(:keychain) { Aspera::Secret::Store::MacosSecurity::Keychain.new('/tmp/test.keychain-db') }
    let(:system_vault) { described_class.allocate.tap { |v| v.instance_variable_set(:@keychain, keychain) } }

    it 'reads the password printed on stderr' do
      spaced = "#{SecureRandom.alphanumeric(6)} #{SecureRandom.alphanumeric(6)}"
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([
        "keychain: \"/tmp/test.keychain-db\"\nattributes:\n    0x00000007 <blob>=\"my_label\"\n    \"acct\"<blob>=\"bob\"\n    \"icmt\"<blob>=\"my comment\"\n",
        "password: \"#{spaced}\"\n",
        success
      ]))
      expect(system_vault.get(label: 'my_label')).to(eq({label: 'my_label', username: 'bob', password: spaced, description: 'my comment'}))
    end

    it 'returns nil for a missing secret when exception is false' do
      stub_failed_execute("security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.\n", 44)
      expect(system_vault.get(label: 'missing', exception: false)).to(be_nil)
      expect { system_vault.get(label: 'missing') }.to(raise_error(RuntimeError, /not found/))
    end

    it 'passes values unescaped (no shell)' do
      special = "#{SecureRandom.alphanumeric(4)} #{SecureRandom.alphanumeric(4)}$#{SecureRandom.alphanumeric(4)}"
      expect(Aspera::Environment).to(receive(:secure_execute)
        .with('security', 'add-generic-password', '-s', 'my_label', '-a', 'none', '-w', special, '/tmp/test.keychain-db', mode: :capture, exception: false)
        .and_return(['', '', success]))
      system_vault.set({label: 'my_label', password: special})
    end
  end

  describe Aspera::Secret::Store::OnePasswordCli do
    it 'returns nil for a missing secret when exception is false' do
      stub_failed_execute('[ERROR] item not found', 1)
      vault = described_class.new
      expect(vault.get(label: 'missing', exception: false)).to(be_nil)
      expect { vault.get(label: 'missing') }.to(raise_error(RuntimeError, /not found/))
    end

    it 'asks for an id when several items share the same label' do
      stub_failed_execute('[ERROR] More than one item matches "my_label". Try again and specify the item by its ID', 1)
      expect { described_class.new.get(label: 'my_label') }.to(raise_error(/Multiple secrets found.*use id/))
    end

    it 'reads url from the website or from a custom field found by label' do
      item = {
        'id' => 'abc', 'title' => 'my_label',
        'fields' => [
          {'id' => 'password', 'label' => 'password', 'value' => secret},
          {'id' => 'x7generated', 'label' => 'url', 'value' => 'https://custom.example.com'}
        ]
      }
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([JSON.generate(item), '', success]))
      expect(described_class.new.get(label: 'my_label')).to(eq({label: 'my_label', password: secret, url: 'https://custom.example.com', id: 'abc'}))
      item['urls'] = [{'href' => 'https://other.example.com'}, {'href' => 'https://site.example.com', 'primary' => true}]
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([JSON.generate(item), '', success]))
      expect(described_class.new.get(label: 'my_label')[:url]).to(eq('https://site.example.com'))
    end

    it 'creates a new item with the website' do
      stub_failed_execute('[ERROR] item not found', 1)
      expect(Aspera::Environment).to(receive(:secure_execute)
        .with('op', 'item', 'create', '--category', 'Login', '--title=my_label', '--url=https://site.example.com', "password[password]=#{secret}", mode: :capture, exception: true)
        .and_return(['', '', success]))
      described_class.new.set({label: 'my_label', password: secret, url: 'https://site.example.com'})
    end

    it 'refuses to create a second item with the same label' do
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([JSON.generate({'id' => 'abc', 'title' => 'my_label'}), '', success]))
      expect { described_class.new.set({label: 'my_label', password: secret}) }.to(raise_error(/already exist/))
    end
  end

  describe Aspera::Secret::Store::HashicorpVault do
    it 'skips secrets deleted but still listed in metadata (KV v2)' do
      logical = double('logical')
      allow(Vault::Client).to(receive(:new).and_return(instance_double(Vault::Client, logical: logical)))
      allow(logical).to(receive(:list).with('secret/metadata/').and_return(%w[kept deleted]))
      allow(logical).to(receive(:read).with('secret/data/kept').and_return(Vault::Secret.new(data: {data: {password: secret}})))
      allow(logical).to(receive(:read).with('secret/data/deleted').and_return(nil))
      vault = described_class.new(url: 'http://127.0.0.1:8200', token: SecureRandom.hex(16))
      expect(vault.all).to(eq([{password: secret, label: 'kept'}]))
      expect(vault.get(label: 'deleted', exception: false)).to(be_nil)
      expect { vault.set({label: 'kept', password: other}) }.to(raise_error(/already exist/)) # HashiCorpIgnore
      expect(logical).to(receive(:write).with('secret/data/deleted', data: {password: other}))
      vault.set({label: 'deleted', password: other}) # HashiCorpIgnore
    end

    it 'uses its own client, not the global configuration' do
      address = Vault.address
      vault = described_class.new(url: 'http://127.0.0.1:8201', token: SecureRandom.hex(16), namespace: 'media')
      expect(vault.info).to(eq({url: 'http://127.0.0.1:8201', namespace: 'media', auth: 'token'}))
      expect(Vault.address).to(eq(address))
    end

    it 'requires one authentication' do
      expect { described_class.new(url: 'http://127.0.0.1:8200') }.to(raise_error(Aspera::ParameterError, /one of token/))
      expect { described_class.new(url: 'http://127.0.0.1:8200', token: SecureRandom.hex(16), token_file: '/x') }.to(raise_error(Aspera::ParameterError, /one of token/))
      expect { described_class.new(url: 'http://127.0.0.1:8200', approle: {'role_id' => 'r', 'other' => 'x'}) }.to(raise_error(Aspera::ParameterError, /unsupported keys: other/))
    end
  end
end
