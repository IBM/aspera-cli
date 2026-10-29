# frozen_string_literal: true

# Unit tests for Aspera::Secret: parsing of references, resolver with a fake store — no server needed.

require 'tmpdir'
require 'securerandom'
require 'aspera/secret/resolver'

RSpec.describe(Aspera::Secret) do
  # Values of secrets are generated, none in source
  let(:secret) { SecureRandom.alphanumeric(16) }
  let(:other) { SecureRandom.alphanumeric(16) }

  describe '.parse_reference' do
    it 'parses store, path, options and field' do
      ref = described_class.parse_reference('secret://vault_prod/secret/orchestrator/faspex5?version=2&mount=secret#private_key')
      expect(ref.to_h).to(eq({
        text:    'secret://vault_prod/secret/orchestrator/faspex5?version=2&mount=secret#private_key',
        store:   'vault_prod',
        path:    'secret/orchestrator/faspex5',
        options: {'version' => '2', 'mount' => 'secret'},
        field:   'private_key'
      }))
    end

    it 'decodes spaces and percent-encoding of path and field' do
      expect(described_class.parse_reference('secret://nodes/Baton QC#password').path).to(eq('Baton QC'))
      ref = described_class.parse_reference('secret://nodes/Baton%20QC#certificate%5Fpassphrase')
      expect([ref.path, ref.field]).to(eq(['Baton QC', 'certificate_passphrase']))
      # `+` is a space only in options
      expect(described_class.parse_reference('secret://ops/a+b?mount=c+d').to_h.slice(:path, :options)).to(eq({path: 'a+b', options: {'mount' => 'c d'}}))
    end

    it 'has no field when absent' do
      ref = described_class.parse_reference('secret://ops/faspex5')
      expect([ref.path, ref.options, ref.field]).to(eq(['faspex5', {}, nil]))
    end

    it 'refuses invalid references' do
      ['secret://ops', 'secret://ops/', 'secret://op s/a', 'secret://ops/a#', 'vault://ops/a', 'secret://ops/a%ZZ', nil].each do |text|
        expect { described_class.parse_reference(text) }.to(raise_error(Aspera::Secret::Error, /\Asecret reference /))
      end
    end

    it 'detects references' do
      expect(described_class.reference?('secret://ops/a')).to(be(true))
      expect(described_class.reference?('my secret://ops/a')).to(be(false))
      expect(described_class.reference?(nil)).to(be(false))
    end
  end

  describe '.read_file' do
    it 'reads a file without trailing newline and hides its value' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'token')
        File.write(path, "#{secret}\n")
        expect(described_class.read_file(path)).to(eq(secret))
        expect(Aspera::Secret::Hider.instance.hide_secrets_in_string("token is #{secret}")).not_to(include(secret))
        File.write(path, "\n")
        expect { described_class.read_file(path) }.to(raise_error(Aspera::Secret::Error, /empty/))
        expect { described_class.read_file(File.join(dir, 'missing')) }.to(raise_error(Aspera::Secret::Error, /No such file/))
      end
    end
  end

  describe Aspera::Secret::Bootstrap do
    it 'gives the value and hides it' do
      bootstrap = described_class.new('password', secret)
      expect([bootstrap.value, bootstrap.mtime]).to(eq([secret, nil]))
      expect(bootstrap.inspect).not_to(include(secret))
      expect(Aspera::Secret::Hider.instance.hide_secrets_in_string("password is #{secret}")).not_to(include(secret))
    end

    it 'reads the file at each call, with its modification time' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'password')
        File.write(path, "#{secret}\n")
        bootstrap = described_class.new('password', "@file:#{path}")
        expect([bootstrap.value, bootstrap.mtime]).to(eq([secret, File.mtime(path)]))
        File.write(path, other)
        expect(bootstrap.value).to(eq(other))
        File.delete(path)
        expect { bootstrap.mtime }.to(raise_error(Aspera::Secret::Error, /secret file: No such file/))
      end
    end

    it 'refuses a missing or empty value' do
      [nil, '', '@file:', 42].each do |text|
        expect { described_class.new('password', text) }.to(raise_error(Aspera::Secret::Error, /\Apassword: expecting /))
      end
    end
  end

  describe Aspera::Secret::Resolver do
    # Store in memory: path → fields; counts reads
    fake_store = Class.new(Aspera::Secret::Store::Base) do
      self::PARAMETERS = %i[allowed].freeze
      self::REFERENCE_OPTIONS = %w[flavor].freeze
      attr_reader :reads
      attr_accessor :secrets

      def initialize(allowed: nil)
        super()
        @allowed = allowed
        @secrets = {}
        @reads = 0
      end

      def check_reference(ref)
        super
        raise Aspera::Secret::Error, "path not allowed: #{ref.path}" unless @allowed.nil? || ref.path.start_with?(@allowed)
      end

      def read_reference(ref)
        @reads += 1
        fields = @secrets[ref.path]
        raise Aspera::Secret::Error, 'not found' if fields.nil?
        {value: field_value(fields, ref, default: 'value'), version: 3, updated_time: Time.at(0)}
      end
    end

    before(:all) do
      Aspera::Secret::Store::Factory.register_type('fake', fake_store)
      # Without parameters, read by label
      Aspera::Secret::Store::Factory.register_type('plain', Class.new(Aspera::Secret::Store::Base) do
        def get(label:, **) = {password: "value of #{label}"}
      end)
    end

    let(:resolver) { described_class.new({'cache_ttl' => 60, 'stores' => {'mem' => {'type' => 'fake', 'allowed' => 'app/'}, 'other' => {'type' => 'fake'}}}) }
    let(:store) { resolver.store('mem') }

    # Monotonic time seen by the resolver
    def at_time(seconds)
      allow(resolver).to(receive(:monotonic_time).and_return(seconds))
    end

    it 'gives a store by name' do
      expect(resolver.store('mem')).to(be(store))
      expect(resolver.store_names).to(eq(%w[mem other]))
      expect { resolver.store('none') }.to(raise_error(Aspera::Secret::Error, 'unknown store none'))
    end

    it 'reads a store without reference methods by label, field password by default' do
      plain = described_class.new({'stores' => {'p' => {'type' => 'plain'}}})
      expect(plain.resolve('secret://p/my_label')).to(eq('value of my_label'))
      expect(plain.metadata('secret://p/my_label')).to(eq({store: 'p', version: nil, updated_time: nil}))
    end

    it 'resolves a reference, with default field' do
      store.secrets['app/one'] = {value: secret, 'user' => other}
      expect(resolver.resolve('secret://mem/app/one')).to(eq(secret))
      expect(resolver.resolve('secret://mem/app/one#user')).to(eq(other))
      expect(resolver.metadata('secret://mem/app/one')).to(eq({store: 'mem', version: 3, updated_time: Time.at(0)}))
      expect(Aspera::Secret::Hider.instance.hide_secrets_in_string("value: #{secret}")).not_to(include(secret))
    end

    it 'caches values until TTL expires' do
      store.secrets['app/one'] = {value: secret}
      at_time(100)
      resolver.resolve('secret://mem/app/one')
      store.secrets['app/one'] = {value: other}
      at_time(159)
      # same secret, other spelling
      expect(resolver.resolve('secret://mem/app%2Fone')).to(eq(secret))
      expect(store.reads).to(eq(1))
      at_time(160)
      expect(resolver.resolve('secret://mem/app/one')).to(eq(other))
      expect(store.reads).to(eq(2))
    end

    it 'invalidates the cache of a store or all' do
      store.secrets['app/one'] = {value: secret}
      resolver.resolve('secret://mem/app/one')
      resolver.invalidate('other')
      resolver.resolve('secret://mem/app/one')
      expect(store.reads).to(eq(1))
      resolver.invalidate('mem')
      resolver.resolve('secret://mem/app/one')
      resolver.invalidate
      resolver.resolve('secret://mem/app/one')
      expect(store.reads).to(eq(3))
    end

    it 'does not cache when TTL is 0' do
      resolver = described_class.new({cache_ttl: 0, stores: {mem: {type: 'fake'}}})
      store = resolver.store('mem')
      store.secrets['one'] = {value: secret}
      2.times { resolver.resolve('secret://mem/one') }
      expect(store.reads).to(eq(2))
    end

    it 'gives the reference and the reason in errors, never a value' do
      store.secrets['app/one'] = {value: secret, list: [secret]}
      {
        'secret://unknown/app/one'       => 'unknown store unknown',
        'secret://mem/other/one'         => 'path not allowed: other/one',
        'secret://mem/app/one?version=1' => 'unsupported options: version',
        'secret://mem/app/missing'       => 'not found',
        'secret://mem/app/one#user'      => 'no field: user',
        'secret://mem/app/one#list'      => 'field list is not a string'
      }.each do |text, reason|
        expect { resolver.resolve(text) }.to(raise_error(Aspera::Secret::Error, "secret reference #{text}: #{reason}"))
      end
      expect(store.reads).to(eq(3))
    end

    it 'refuses an invalid configuration' do
      [
        [[], /expecting a Hash/],
        [{'other' => 1}, /unsupported keys: other/],
        [{'cache_ttl' => -1}, /cache_ttl/],
        [{'stores' => {'mem' => {'type' => 'none'}}}, /store mem: type: unknown none, use one of: .*vault/],
        [{'stores' => {'mem' => {}}}, /store mem: type: missing/],
        [{'stores' => {'mem' => {'type' => 'fake', 'bad' => 1}}}, /store mem: unsupported keys: bad\z/],
        [{'stores' => {'m/n' => {'type' => 'fake'}}}, %r{store m/n: invalid name}],
        [{'stores' => {'p' => {'type' => 'plain', 'x' => 1}}}, /store p: unsupported keys: x\z/],
        [{'stores' => {'o' => {'type' => '1password', 'source' => 'web'}}}, /store o: source: unknown web, use one of: api, cli/],
        [{'stores' => {'f' => {'type' => 'file', 'file' => 'f', 'password_file' => 'p'}}}, /store f: unsupported keys: password_file\z/],
        [{'stores' => {'v' => {'type' => 'vault', 'url' => 'http://127.0.0.1:8200', 'token_file' => 't'}}}, /store v: unsupported keys: token_file\z/]
      ].each do |config, message|
        expect { described_class.new(config) }.to(raise_error(Aspera::Secret::Error, /\Asecret references configuration: #{message}/))
      end
    end

    it 'creates a store when first used, and reports its errors with the reference' do
      [
        [{}, 'vault: one of token or approle is required'],
        [{'token' => '@file:'}, 'token: expecting @file:<path>'],
        [{'approle' => {'role_id' => 'r', 'secret_id_file' => 's'}}, 'vault approle: unsupported keys: secret_id_file'],
        [{'approle' => {'role_id' => 'r', 'secret_id' => ''}}, 'approle secret_id: expecting ']
      ].each do |params, message|
        vault = params.merge('type' => 'vault', 'url' => 'http://127.0.0.1:8200')
        resolver = described_class.new({'stores' => {'v' => vault, 'mem' => {'type' => 'fake'}}})
        resolver.store('mem').secrets['one'] = {value: secret}
        expect(resolver.resolve('secret://mem/one')).to(eq(secret))
        expect { resolver.resolve('secret://v/kv/app#password') }.to(raise_error(Aspera::Secret::Error, %r{\Asecret reference secret://v/kv/app#password: store v: #{Regexp.escape(message)}}))
        expect { resolver.store('v') }.to(raise_error(Aspera::Secret::Error, /\Astore v: #{Regexp.escape(message)}/))
      end
    end

    it 'registers only subclasses of store' do
      expect { Aspera::Secret::Store::Factory.register_type('bad', String) }.to(raise_error(Aspera::AssertError))
      expect(Aspera::Secret::Store::Factory.types).to(include('vault', 'file', 'system', '1password', 'fake'))
    end
  end
end
