# frozen_string_literal: true

# Unit tests for secret references in HashiCorp Vault: KV v2, token file, AppRole — with a fake Vault server (WEBrick).

require 'tmpdir'
require 'securerandom'
require 'webrick'
require 'json'
require 'aspera/secret/resolver'
require 'aspera/secret/store/hashicorp_vault'

RSpec.describe(Aspera::Secret::Store::HashicorpVault) do
  before(:all) do
    # Shared with server: valid tokens, secrets (URL path after `/v1/` → versions), AppRole, counters
    @state = {}
    state = @state
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    @server.mount_proc('/v1/') do |req, res|
      state[:requests] += 1
      path = req.path.delete_prefix('/v1/')
      token = req['X-Vault-Token']
      status, body =
        case [req.request_method, path]
        in ['POST', %r{\Aauth/([^/]+)/login\z}]
          credentials = JSON.parse(req.body)
          if Regexp.last_match(1).eql?('approle') && credentials.eql?(state[:approle])
            state[:logins] += 1
            token = SecureRandom.hex(16)
            state[:tokens].push(token)
            [200, {auth: {client_token: token, lease_duration: state[:lease], renewable: true, policies: []}}]
          else
            [400, {errors: ['invalid role or secret ID']}]
          end
        in _ unless state[:tokens].include?(token)
          [403, {errors: ['permission denied']}]
        in ['PUT', 'auth/token/renew-self']
          state[:renewals] += 1
          [200, {auth: {client_token: token, lease_duration: state[:lease], renewable: true, policies: []}}]
        in [('POST' | 'PUT'), %r{\A([^/]+)/data/(.+)\z}]
          # KV v2 write (gem vault uses PUT)
          mount = Regexp.last_match(1)
          kv_path = Regexp.last_match(2)
          body_json = JSON.parse(req.body, symbolize_names: true)
          cas = body_json.dig(:options, :cas)
          full = "#{mount}/data/#{kv_path}"
          if cas == 0 && state[:secrets].key?(full)
            [400, {errors: ['check-and-set parameter did not match the current version']}]
          else
            version = (state[:secrets][full]&.size || 0) + 1
            state[:secrets][full] ||= []
            state[:secrets][full].push(body_json[:data])
            [200, {data: {metadata: {version: version, created_time: '2026-10-31T10:00:00.000000000Z'}}}]
          end
        in ['GET', _]
          versions = state[:secrets][path]
          version = (req.query['version'] || versions&.size).to_i
          if versions.nil? || !version.between?(1, versions.size)
            [404, {errors: []}]
          else
            [200, {data: {data: versions[version - 1], metadata: {version: version, created_time: "2026-10-0#{version}T10:00:00.123456789Z"}}}]
          end
        else
          [405, {errors: ['unsupported']}]
        end
      res.status = status
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate(body)
    end
    @thread = Thread.new { @server.start }
    @url = "http://127.0.0.1:#{@server.config[:Port]}"
  end

  after(:all) do
    @server.shutdown
    @thread.join
  end

  # Values of secrets are generated, none in source
  let(:secret) { SecureRandom.alphanumeric(16) }
  let(:other) { SecureRandom.alphanumeric(16) }
  let(:token) { SecureRandom.hex(16) }
  let(:approle) { {'role_id' => SecureRandom.uuid, 'secret_id' => SecureRandom.uuid} }
  let(:dir) { Dir.mktmpdir }

  before do
    @state.merge!(requests: 0, logins: 0, renewals: 0, lease: 30, tokens: [token], approle: approle, secrets: {})
  end

  after { FileUtils.rm_rf(dir) }

  # @return [String] Path of new file with content
  def secret_file(name, content)
    File.join(dir, name).tap { |path| File.write(path, "#{content}\n") }
  end

  def resolver(store) = Aspera::Secret::Resolver.new({'cache_ttl' => 0, 'stores' => {'vault_prod' => {'type' => 'vault', 'url' => @url}.merge(store)}})

  describe 'with token file' do
    let(:token_file) { secret_file('token', token) }

    it 'reads a field of the current or given version, and metadata' do
      @state[:secrets]['secret/data/orchestrator/faspex5'] = [{private_key: other}, {private_key: secret, username: SecureRandom.alphanumeric(16)}]
      r = resolver('token' => "@file:#{token_file}")
      expect(r.resolve('secret://vault_prod/secret/orchestrator/faspex5#private_key')).to(eq(secret))
      expect(r.resolve('secret://vault_prod/secret/orchestrator/faspex5?version=1#private_key')).to(eq(other))
      expect(r.metadata('secret://vault_prod/secret/orchestrator/faspex5#username')).to(eq({store: 'vault_prod', version: 2, updated_time: Time.utc(2026, 10, 2, 10, 0, Rational(123_456_789, 1_000_000_000))}))
      expect { r.resolve('secret://vault_prod/secret/orchestrator/faspex5?version=3#private_key') }.to(raise_error(Aspera::Secret::Error, /: not found\z/))
      expect { r.resolve('secret://vault_prod/secret/orchestrator/faspex5') }.to(raise_error(Aspera::Secret::Error, /: field required/))
    end

    it 'reads a secret of a mount with slash' do
      @state[:secrets]['kv/team/data/app'] = [{password: secret}]
      expect(resolver('token' => "@file:#{token_file}").resolve('secret://vault_prod/kv/team/app?mount=kv/team#password')).to(eq(secret))
    end

    it 'reads the token file again when it changes' do
      @state[:secrets]['secret/data/app'] = [{password: secret}]
      r = resolver('token' => "@file:#{token_file}")
      expect(r.resolve('secret://vault_prod/secret/app#password')).to(eq(secret))
      # Rotation by Vault Agent: new token, same modification time, old token revoked
      new_token = SecureRandom.hex(16)
      mtime = File.mtime(token_file)
      File.write(token_file, "#{new_token}\n")
      File.utime(mtime, mtime, token_file)
      @state[:tokens] = [new_token]
      expect(r.resolve('secret://vault_prod/secret/app#password')).to(eq(secret))
      # Revoked, file unchanged: no retry
      @state[:tokens] = []
      requests = @state[:requests]
      expect { r.resolve('secret://vault_prod/secret/app#password') }.to(raise_error(Aspera::Secret::Error, /: Vault: 403 permission denied\z/))
      expect(@state[:requests]).to(eq(requests + 1))
    end

    it 'fails on missing token file, with reference' do
      expect { resolver('token' => "@file:#{File.join(dir, 'missing')}").resolve('secret://vault_prod/secret/app#password') }
        .to(raise_error(Aspera::Secret::Error, %r{\Asecret reference secret://vault_prod/secret/app#password: .*No such file}))
    end

    it 'checks paths before access' do
      r = resolver('token' => "@file:#{token_file}", 'allowed_prefixes' => ['secret/orchestrator/', 'secret/app'])
      @state[:secrets]['secret/data/app/one'] = [{password: secret}]
      expect(r.resolve('secret://vault_prod/secret/app/one#password')).to(eq(secret))
      {
        'secret://vault_prod/secret/other#password'                    => 'path not allowed: secret/other',
        'secret://vault_prod/secret/application#password'              => 'path not allowed: secret/application',
        'secret://vault_prod/secret/orchestrator/../other#password'    => 'invalid path: secret/orchestrator/../other',
        'secret://vault_prod/secret/orchestrator//x#password'          => 'invalid path: secret/orchestrator//x',
        'secret://vault_prod/secret#password'                          => 'path shall be <mount>/<path>: secret',
        'secret://vault_prod/kv/app?mount=other#password'              => 'path shall start with mount other/',
        'secret://vault_prod/secret/orchestrator/a?version=0#password' => 'version shall be a positive integer: 0',
        'secret://vault_prod/secret/orchestrator/a?flavor=1#password'  => 'unsupported options: flavor'
      }.each do |text, reason|
        expect { r.resolve(text) }.to(raise_error(Aspera::Secret::Error, "secret reference #{text}: #{reason}"))
      end
      expect(@state[:requests]).to(eq(1))
    end
  end

  describe 'with token value' do
    it 'reads a field' do
      @state[:secrets]['secret/data/app'] = [{password: secret}]
      expect(resolver('token' => token).resolve('secret://vault_prod/secret/app#password')).to(eq(secret))
    end
  end

  describe 'with AppRole' do
    let(:secret_id_file) { secret_file('secret_id', approle['secret_id']) }
    let(:vault) { Aspera::Secret::Store::HashicorpVault.new(url: @url, approle: {'role_id' => approle['role_id'], 'secret_id' => "@file:#{secret_id_file}"}) }

    before { @state[:secrets]['secret/data/app'] = [{password: secret}] }

    def read_at(seconds)
      allow(vault).to(receive(:monotonic_time).and_return(seconds))
      vault.read(path: 'app')[:data][:password]
    end

    it 'logs in, and renews the token after 2/3 of lease' do
      expect(read_at(1000)).to(eq(secret))
      expect(read_at(1019)).to(eq(secret))
      expect(@state.slice(:logins, :renewals)).to(eq({logins: 1, renewals: 0}))
      expect(read_at(1021)).to(eq(secret))
      expect(@state.slice(:logins, :renewals)).to(eq({logins: 1, renewals: 1}))
      # Renewal refused: new login
      @state[:tokens] = []
      expect(read_at(1042)).to(eq(secret))
      expect(@state.slice(:logins, :renewals)).to(eq({logins: 2, renewals: 1}))
    end

    it 'logs in again when the token is refused' do
      expect(read_at(1000)).to(eq(secret))
      @state[:tokens] = []
      expect(read_at(1001)).to(eq(secret))
      expect(@state[:logins]).to(eq(2))
      # Login refused: error
      @state[:tokens] = []
      @state[:approle] = {}
      expect { read_at(1002) }.to(raise_error(Vault::HTTPClientError, /invalid role or secret ID/))
    end

    it 'resolves through the store, with secret_id in a file or as value' do
      [{'role_id' => approle['role_id'], 'secret_id' => "@file:#{secret_id_file}"}, approle].each do |parameters|
        expect(resolver('approle' => parameters).resolve('secret://vault_prod/secret/app#password')).to(eq(secret))
      end
      expect(@state[:logins]).to(eq(2))
    end
  end

  describe '#write_reference' do
    let(:token_file) { secret_file('token', token) }
    # Resolver with writable store and allowed_prefixes restriction
    let(:rw) do
      Aspera::Secret::Resolver.new({
        'cache_ttl' => 0,
        'stores'    => {
          'vault_prod' => {
            'type'             => 'vault',
            'url'              => @url,
            'token'            => "@file:#{token_file}",
            'allowed_prefixes' => ['secret/orchestrator/'],
            'writable'         => true
          }
        }
      })
    end

    it 'creates a new secret and returns version and time' do
      result = rw.write('secret://vault_prod/secret/orchestrator/new_app', {'username' => SecureRandom.alphanumeric(8), 'password' => secret})
      expect(result[:version]).to(eq(1))
      expect(result[:updated_time]).to(be_a(Time))
      # Readable at once (cache was cleared)
      expect(rw.resolve('secret://vault_prod/secret/orchestrator/new_app#password')).to(eq(secret))
    end

    it 'sends cas:0 in the request body (refuses an existing path)' do
      rw.write('secret://vault_prod/secret/orchestrator/cas_test', {'password' => secret})
      expect { rw.write('secret://vault_prod/secret/orchestrator/cas_test', {'password' => other}) }
        .to(raise_error(Aspera::Secret::Error, %r{secret exists: secret/orchestrator/cas_test}))
    end

    it 'reports 403 as a Vault error' do
      @state[:tokens] = []
      expect { rw.write('secret://vault_prod/secret/orchestrator/forbidden', {'password' => secret}) }
        .to(raise_error(Aspera::Secret::Error, /Vault: 403/))
    end

    it 'refuses a path outside allowed_prefixes' do
      expect { rw.write('secret://vault_prod/secret/other/app', {'password' => secret}) }
        .to(raise_error(Aspera::Secret::Error, /path not allowed/))
    end

    it 'refuses a store not marked writable' do
      read_only = resolver('token' => "@file:#{token_file}")
      expect { read_only.write('secret://vault_prod/secret/orchestrator/x', {'password' => secret}) }
        .to(raise_error(Aspera::Secret::Error, /store vault_prod is not writable/))
    end
  end
end
