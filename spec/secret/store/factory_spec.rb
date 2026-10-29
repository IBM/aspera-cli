# frozen_string_literal: true

# Unit tests for Aspera::Secret::Store::Factory — no server needed.

require 'tmpdir'
require 'securerandom'
require 'aspera/environment'
require 'aspera/secret/store/factory'

RSpec.describe(Aspera::Secret::Store::Factory) do
  # Values of secrets are generated, none in source
  let(:secret) { SecureRandom.alphanumeric(12) }
  let(:vault_password) { SecureRandom.alphanumeric(12) }

  describe '.create file' do
    it 'creates the vault file with restricted access on first secret' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'vault.bin')
        vault = described_class.create({'type' => 'file', 'file' => path, 'password' => vault_password}) # HashiCorpIgnore
        expect(File.exist?(path)).to(be(false))
        vault.set({label: 'my_label', password: secret})
        expect(File.stat(path).mode & 0o777).to(eq(0o600)) unless Gem.win_platform?
        expect(described_class.create({type: 'file', file: path, password: vault_password}).get(label: 'my_label')[:password]).to(eq(secret))
      end
    end

    it 'refuses a missing password, and parameters of other types' do
      expect { described_class.create({type: 'file', file: 'vault.bin'}) }.to(raise_error(Aspera::Secret::Error, /\Apassword: expecting /))
      expect { described_class.create({type: 'file', name: 'vault.bin', password: vault_password}) }.to(raise_error(Aspera::Secret::Error, 'unsupported keys: name')) # HashiCorpIgnore
    end
  end

  describe '.create vault' do
    def create(params) = described_class.create({type: 'vault', url: 'http://127.0.0.1:8200'}.merge(params))

    it 'authenticates with token or approle' do
      expect(create({token: SecureRandom.hex(16)}).info[:auth]).to(eq('token'))
      expect(create({token: '@file:/run/vault/token'}).info[:auth]).to(eq('token file'))
      expect(create({approle: {'role_id' => 'my_role'}}).info[:auth]).to(eq('approle'))
      expect { create({}) }.to(raise_error(Aspera::ParameterError, /one of token or approle/))
    end
  end

  describe '.create 1password' do
    it 'selects the class from source, api by default' do
      expect(described_class.create({type: '1password', source: 'cli', vault: 'ops'})).to(be_a(Aspera::Secret::Store::OnePasswordCli))
      expect(described_class.create({type: '1password', url: 'http://localhost:8080', token: SecureRandom.hex(16), vault_id: 'v'})).to(be_a(Aspera::Secret::Store::OnePasswordApi))
      expect { described_class.create({type: '1password', source: 'cli', token: 't'}) }.to(raise_error(Aspera::Secret::Error, 'unsupported keys: token'))
    end
  end

  describe '.create system' do
    it 'is only on macOS' do
      allow(Aspera::Environment.instance).to(receive(:os).and_return(Aspera::Environment::OS_LINUX))
      expect { described_class.create({type: 'system'}) }.to(raise_error(Aspera::Secret::Error, 'type system: only on macOS'))
    end
  end

  it 'refuses an unknown or missing type' do
    expect { described_class.create({type: 'none'}) }.to(raise_error(Aspera::Secret::Error, /\Atype: unknown none, use one of: file, vault, system, 1password/))
    expect { described_class.create({}) }.to(raise_error(Aspera::Secret::Error, /\Atype: missing/))
    expect { described_class.create('file') }.to(raise_error(Aspera::Secret::Error, 'expecting a Hash'))
  end
end
