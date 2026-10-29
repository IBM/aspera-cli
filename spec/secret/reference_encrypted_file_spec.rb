# frozen_string_literal: true

# Unit tests for secret references in an encrypted file of ascli (vault of type `file`).

require 'tmpdir'
require 'securerandom'
require 'aspera/secret/resolver'

RSpec.describe(Aspera::Secret::Store::EncryptedHash) do
  # Values of secrets are generated, none in source
  let(:secret) { SecureRandom.alphanumeric(16) }
  let(:rotated) { SecureRandom.alphanumeric(16) }
  let(:username) { SecureRandom.alphanumeric(16) }
  let(:vault_password) { SecureRandom.alphanumeric(16) }
  let(:new_vault_password) { SecureRandom.alphanumeric(16) }
  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, 'ops_vault.bin') }
  let(:password_file) { File.join(dir, 'ops_vault.pass') }
  let(:resolver) { Aspera::Secret::Resolver.new({'cache_ttl' => 0, 'stores' => {'ops' => {'type' => 'file', 'file' => file, 'password_file' => password_file}}}) }

  before do
    File.write(password_file, "#{vault_password}\n")
    Aspera::Secret::Store::EncryptedHash.new(file: file, password: vault_password).set({label: 'faspex5', username: username, password: secret})
  end

  after { FileUtils.rm_rf(dir) }

  # Modify file with new modification time
  def rewrite(path)
    mtime = File.mtime(path)
    yield
    File.utime(mtime + 1, mtime + 1, path)
  end

  it 'resolves a field, password by default, with modification time' do
    expect(resolver.resolve('secret://ops/faspex5')).to(eq(secret))
    expect(resolver.resolve('secret://ops/faspex5#username')).to(eq(username))
    expect(resolver.metadata('secret://ops/faspex5')).to(eq({store: 'ops', version: nil, updated_time: File.mtime(file)}))
  end

  it 'reads the file again when it is modified' do
    expect(resolver.resolve('secret://ops/faspex5')).to(eq(secret))
    rewrite(file) do
      vault = Aspera::Secret::Store::EncryptedHash.new(file: file, password: vault_password)
      vault.delete(label: 'faspex5')
      vault.set({label: 'faspex5', password: rotated})
    end
    expect(resolver.resolve('secret://ops/faspex5')).to(eq(rotated))
  end

  it 'reads the password file again when the password changes' do
    expect(resolver.resolve('secret://ops/faspex5')).to(eq(secret))
    rewrite(file) { Aspera::Secret::Store::EncryptedHash.new(file: file, password: vault_password).change_password(new_vault_password) }
    expect { resolver.resolve('secret://ops/faspex5') }.to(raise_error(Aspera::Secret::Error, /: cannot decrypt .*ops_vault.bin/))
    rewrite(password_file) { File.write(password_file, new_vault_password) }
    expect(resolver.resolve('secret://ops/faspex5')).to(eq(secret))
  end

  it 'gives the reference and the reason in errors' do
    {
      'secret://ops/missing'           => 'no label: missing',
      'secret://ops/faspex5#url'       => 'no field: url',
      'secret://ops/faspex5?version=1' => 'unsupported options: version'
    }.each do |text, reason|
      expect { resolver.resolve(text) }.to(raise_error(Aspera::Secret::Error, "secret reference #{text}: #{reason}"))
    end
    File.delete(password_file)
    expect { resolver.resolve('secret://ops/faspex5') }.to(raise_error(Aspera::Secret::Error, /: No such file .*ops_vault.pass/))
  end
end
