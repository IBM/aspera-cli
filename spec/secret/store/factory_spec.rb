# frozen_string_literal: true

# Unit tests for Aspera::Secret::Store::Factory — no server needed.

require 'tmpdir'
require 'securerandom'
require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/secret/store/factory'

RSpec.describe(Aspera::Secret::Store::Factory) do
  # Values of secrets are generated, none in source
  let(:secret) { SecureRandom.alphanumeric(12) }
  let(:vault_password) { SecureRandom.alphanumeric(12) }

  describe '.create file vault' do
    it 'uses vault.bin in the given folder by default, created with restricted access' do
      Dir.mktmpdir do |dir|
        vault = described_class.create({type: 'file'}, 'ascli', dir, vault_password)
        vault.set({label: 'my_label', password: secret})
        path = File.join(dir, 'vault.bin')
        expect(File.exist?(path)).to(be(true))
        expect(File.stat(path).mode & 0o777).to(eq(0o600)) unless Gem.win_platform?
        expect(vault.get(label: 'my_label')[:password]).to(eq(secret))
      end
    end

    it 'resolves a relative name in the given folder' do
      Dir.mktmpdir do |dir|
        described_class.create({type: 'file', name: 'other.bin'}, 'ascli', dir, vault_password).set({label: 'my_label', password: secret})
        expect(File.exist?(File.join(dir, 'other.bin'))).to(be(true))
      end
    end
  end

  describe '.create vault' do
    def create(info) = described_class.create({type: 'vault', url: 'http://127.0.0.1:8200'}.merge(info), 'ascli', '.', vault_password)

    it 'uses the vault password as token, unless token or approle is set' do
      expect(create({}).info[:auth]).to(eq('token'))
      expect(create({token: '@file:/run/vault/token'}).info[:auth]).to(eq('token file'))
      expect(create({approle: {'role_id' => 'my_role'}}).info[:auth]).to(eq('approle'))
      expect { create({namespace: {}}) }.to(raise_error(/only string values/))
    end
  end
end
