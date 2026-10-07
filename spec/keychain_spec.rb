# frozen_string_literal: true

# Unit tests for Aspera::Keychain backends — no server, keychain or `op` needed.

require 'tmpdir'
require 'yaml'
require 'json'
require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/keychain/encrypted_hash'
require 'aspera/keychain/macos_security'
require 'aspera/keychain/one_password_cli'
require 'aspera/keychain/hashicorp_vault'

RSpec.describe(Aspera::Keychain) do
  let(:success) { instance_double(Process::Status, success?: true, exitstatus: 0) }

  def failure(code) = instance_double(Process::Status, success?: false, exitstatus: code)

  # Simulates a failed command, raising like `secure_execute` unless `exception: false`
  def stub_failed_execute(stderr, code)
    allow(Aspera::Environment).to(receive(:secure_execute)) do |*_args, exception: true, **|
      raise "Process failed: #{code} (#{stderr})" if exception
      ['', stderr, failure(code)]
    end
  end

  describe Aspera::Keychain::EncryptedHash do
    it 'migrates a legacy vault (no kdf) to PBKDF2 on password change' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'vault.bin')
        # v4.26.0 format: key is the password zero-padded, no kdf field
        legacy_key = "old#{"\x00" * 32}"[0, 32]
        data = described_class::OsslCipher.new('aes-256-cbc', legacy_key).encrypt(YAML.dump({'my_label' => {password: 'my_secret'}}))
        File.write(path, YAML.dump({'version' => '1.0.0', 'type' => 'encrypted_hash_vault', 'cipher' => 'aes-256-cbc', 'data' => data}))
        described_class.new(file: path, password: 'old').change_password('new')
        expect(YAML.load_file(path)['kdf']).to(include('algo' => 'PBKDF2'))
        expect(described_class.new(file: path, password: 'new').get(label: 'my_label')[:password]).to(eq('my_secret'))
      end
    end

    it 'refuses to overwrite a secret and to delete a missing one' do
      Dir.mktmpdir do |dir|
        vault = described_class.new(file: File.join(dir, 'vault.bin'), password: 'pass')
        vault.set({label: 'my_label', password: 'my_secret'})
        expect { vault.set({label: 'my_label', password: 'other'}) }.to(raise_error(/already exist/))
        expect { vault.delete(label: 'missing') }.to(raise_error(/not found/))
      end
    end
  end

  describe Aspera::Keychain::MacosSystem do
    let(:keychain) { Aspera::Keychain::MacosSecurity::Keychain.new('/tmp/test.keychain-db') }
    let(:system_vault) { described_class.allocate.tap { |v| v.instance_variable_set(:@keychain, keychain) } }

    it 'reads the password printed on stderr' do
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([
        "keychain: \"/tmp/test.keychain-db\"\nattributes:\n    0x00000007 <blob>=\"my_label\"\n    \"acct\"<blob>=\"bob\"\n    \"icmt\"<blob>=\"my comment\"\n",
        "password: \"my secret\"\n",
        success
      ]))
      expect(system_vault.get(label: 'my_label')).to(eq({label: 'my_label', username: 'bob', password: 'my secret', description: 'my comment'}))
    end

    it 'returns nil for a missing secret when exception is false' do
      stub_failed_execute("security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.\n", 44)
      expect(system_vault.get(label: 'missing', exception: false)).to(be_nil)
      expect { system_vault.get(label: 'missing') }.to(raise_error(RuntimeError, /not found/))
    end

    it 'passes values unescaped (no shell)' do
      expect(Aspera::Environment).to(receive(:secure_execute)
        .with('security', 'add-generic-password', '-s', 'my_label', '-a', 'none', '-w', 'a b$c', '/tmp/test.keychain-db', mode: :capture, exception: false)
        .and_return(['', '', success]))
      system_vault.set({label: 'my_label', password: 'a b$c'})
    end
  end

  describe Aspera::Keychain::OnePasswordCli do
    it 'returns nil for a missing secret when exception is false' do
      stub_failed_execute('[ERROR] item not found', 1)
      vault = described_class.new
      expect(vault.get(label: 'missing', exception: false)).to(be_nil)
      expect { vault.get(label: 'missing') }.to(raise_error(RuntimeError, /not found/))
    end

    it 'reads url from the website or from a custom field found by label' do
      item = {
        'id' => 'abc', 'title' => 'my_label',
        'fields' => [
          {'id' => 'password', 'label' => 'password', 'value' => 'my_secret'},
          {'id' => 'x7generated', 'label' => 'url', 'value' => 'https://custom.example.com'}
        ]
      }
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([JSON.generate(item), '', success]))
      expect(described_class.new.get(label: 'my_label')).to(eq({label: 'my_label', password: 'my_secret', url: 'https://custom.example.com', id: 'abc'}))
      item['urls'] = [{'href' => 'https://other.example.com'}, {'href' => 'https://site.example.com', 'primary' => true}]
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([JSON.generate(item), '', success]))
      expect(described_class.new.get(label: 'my_label')[:url]).to(eq('https://site.example.com'))
    end

    it 'creates a new item with the website' do
      stub_failed_execute('[ERROR] item not found', 1)
      expect(Aspera::Environment).to(receive(:secure_execute)
        .with('op', 'item', 'create', '--category', 'Login', '--title=my_label', '--url=https://site.example.com', 'password[password]=my_secret', mode: :capture, exception: true)
        .and_return(['', '', success]))
      described_class.new.set({label: 'my_label', password: 'my_secret', url: 'https://site.example.com'})
    end

    it 'refuses to create a second item with the same label' do
      allow(Aspera::Environment).to(receive(:secure_execute).and_return([JSON.generate({'id' => 'abc', 'title' => 'my_label'}), '', success]))
      expect { described_class.new.set({label: 'my_label', password: 'my_secret'}) }.to(raise_error(/already exist/))
    end
  end

  describe Aspera::Keychain::HashicorpVault do
    it 'skips secrets deleted but still listed in metadata (KV v2)' do
      logical = double('logical')
      allow(Vault).to(receive(:logical).and_return(logical))
      allow(logical).to(receive(:list).with('secret/metadata/').and_return(%w[kept deleted]))
      allow(logical).to(receive(:read).with('secret/data/kept').and_return(Vault::Secret.new(data: {data: {password: 'my_secret'}})))
      allow(logical).to(receive(:read).with('secret/data/deleted').and_return(nil))
      vault = described_class.new(url: 'http://127.0.0.1:8200', token: 'token')
      expect(vault.all).to(eq([{password: 'my_secret', label: 'kept'}]))
      expect(vault.get(label: 'deleted', exception: false)).to(be_nil)
      expect { vault.set({label: 'kept', password: 'other'}) }.to(raise_error(/already exist/))
      expect(logical).to(receive(:write).with('secret/data/deleted', data: {password: 'new'}))
      vault.set({label: 'deleted', password: 'new'})
    end
  end
end
