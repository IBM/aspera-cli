# frozen_string_literal: true

# Unit tests for secret references in an encrypted file of ascli (vault of type `file`).

require 'English'
require 'tmpdir'
require 'securerandom'
require 'aspera/secret/resolver'
require 'aspera/secret/store/encrypted_hash'

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
  let(:password) { "@file:#{password_file}" }
  let(:resolver) { Aspera::Secret::Resolver.new({'cache_ttl' => 0, 'stores' => {'ops' => {'type' => 'file', 'file' => file, 'password' => password}}}) }
  let(:writable_resolver) { Aspera::Secret::Resolver.new({'cache_ttl' => 0, 'stores' => {'ops' => {'type' => 'file', 'file' => file, 'password' => password, 'writable' => true}}}) }

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

  context 'with the password as value' do
    let(:password) { vault_password }

    it 'reads the file when used, and again when it is modified' do
      expect(resolver.resolve('secret://ops/faspex5')).to(eq(secret))
      rewrite(file) { Aspera::Secret::Store::EncryptedHash.new(file: file, password: vault_password).set({label: 'aoc', password: rotated}) }
      expect(resolver.resolve('secret://ops/aoc')).to(eq(rotated))
    end
  end

  describe '#write_reference' do
    it 'writes a new secret and makes it readable at once' do
      result = writable_resolver.write('secret://ops/new_label', {'password' => secret, 'username' => SecureRandom.alphanumeric(8)})
      expect(result).to(eq({version: nil, updated_time: nil}))
      expect(writable_resolver.resolve('secret://ops/new_label')).to(eq(secret))
    end

    it 'refuses an existing label' do
      expect { writable_resolver.write('secret://ops/faspex5', {'password' => secret}) }
        .to(raise_error(Aspera::Secret::Error, %r{secret reference secret://ops/faspex5: .*faspex5 already exist}))
    end

    it 'refuses unsupported fields' do
      expect { writable_resolver.write('secret://ops/new_label', {'api_key' => secret}) }
        .to(raise_error(Aspera::Secret::Error, /unsupported fields: api_key/))
    end

    it 'two processes writing concurrently keep both labels and the file is never empty during writes',
      skip: RUBY_PLATFORM.include?('mingw') || RUBY_PLATFORM.include?('mswin') do
      parent_read_errors = []
      # Child writes a second label while parent reads in a loop
      child = fork do
        1_000.times do
          vault = Aspera::Secret::Store::EncryptedHash.new(file: file, password: vault_password)
          vault.write_reference(Aspera::Secret.parse_reference("secret://ops/child_#{SecureRandom.alphanumeric(4)}"), {'password' => SecureRandom.alphanumeric(16)})
        rescue Aspera::Secret::Error, Aspera::AssertError
          # label collision: fine (two processes may pick the same random suffix)
        end
        exit!(0)
      end
      200.times do
        resolver.resolve('secret://ops/faspex5')
      rescue Aspera::Secret::Error => e
        parent_read_errors << e.message
      end
      Process.wait(child)
      expect($CHILD_STATUS.exitstatus).to(eq(0))
      expect(parent_read_errors).to(be_empty)
    end
  end

  it 'refuses a missing or empty password, when used' do
    [nil, '', '@file:'].each do |value|
      config = {'stores' => {'ops' => {'type' => 'file', 'file' => file, 'password' => value}.compact}}
      expect { Aspera::Secret::Resolver.new(config).resolve('secret://ops/faspex5') }.to(raise_error(Aspera::Secret::Error, /: store ops: password: expecting /))
    end
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
