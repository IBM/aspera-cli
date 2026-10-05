# frozen_string_literal: true

# Unit tests for Aspera::Keychain::Factory — no server needed.

require 'tmpdir'
require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/keychain/factory'

RSpec.describe(Aspera::Keychain::Factory) do
  describe '.create file vault' do
    it 'uses vault.bin in the given folder by default, created with restricted access' do
      Dir.mktmpdir do |dir|
        vault = described_class.create({type: 'file'}, 'ascli', dir, 'my_vault_password')
        vault.set({label: 'my_label', password: 'my_secret'})
        path = File.join(dir, 'vault.bin')
        expect(File.exist?(path)).to(be(true))
        expect(File.stat(path).mode & 0o777).to(eq(0o600)) unless Gem.win_platform?
        expect(vault.get(label: 'my_label')[:password]).to(eq('my_secret'))
      end
    end

    it 'resolves a relative name in the given folder' do
      Dir.mktmpdir do |dir|
        described_class.create({type: 'file', name: 'other.bin'}, 'ascli', dir, 'my_vault_password').set({label: 'my_label', password: 'my_secret'})
        expect(File.exist?(File.join(dir, 'other.bin'))).to(be(true))
      end
    end
  end
end
