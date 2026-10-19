# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/secret_hider'
require 'aspera/environment'
require 'securerandom'

RSpec.describe(Aspera::SecretHider) do
  let(:hider) { described_class.instance }
  let(:formatter) { hider.log_formatter(proc { |_s, _d, _p, m| m }) }
  # Values of secrets are generated, none in source
  let(:secret) { SecureRandom.alphanumeric(12) }
  let(:other) { SecureRandom.alphanumeric(12) }

  # The placeholder depends on Unicode support: tests use the Unicode one, unless stated otherwise
  around do |example|
    Aspera::Environment.unicode = true
    example.run
  ensure
    Aspera::Environment.unicode = nil
  end

  def log(msg)
    formatter.call('DEBUG', nil, nil, msg)
  end

  it 'uses an ASCII placeholder when Unicode is not supported' do
    Aspera::Environment.unicode = false
    expect(log(%Q({"password":"#{secret}"}))).to(eq('{"password":"***"}'))
    expect(hider.deep_remove_secret({'password' => secret})).to(eq({'password' => '***'}))
    expect(hider.deep_hide_values("a #{secret} b", [secret])).to(eq('a *** b'))
  end

  describe '#log_formatter' do
    after { hider.log_secrets = false }

    it 'hides JSON values' do
      expect(log(%Q({"password":"#{secret}"}))).to(eq('{"password":"🔑"}'))
    end

    it 'hides whole JSON value with escaped quote' do
      expect(log(%Q({"password":"#{secret}\\"#{other}"}))).to(eq('{"password":"🔑"}'))
    end

    it 'hides Ruby 3.4+ inspect with string keys' do
      expect(log({'password' => secret}.inspect)).not_to(include(secret))
    end

    it 'hides Ruby 3.4+ inspect with symbol keys' do
      # literal: `inspect` of Ruby < 3.4 gives legacy format
      expect(log(%Q({user: "john", password: "#{secret}"}))).to(eq('{user: "john", password: "🔑"}'))
    end

    it 'hides legacy Ruby inspect' do
      expect(log(%Q({"password"=>"#{secret}", :token=>"#{other}"}))).to(eq('{"password"=>"🔑", :token=>"🔑"}'))
    end

    it 'hides ascp env var in middle and at end of line' do
      expect(log("exec: ASPERA_SCP_PASS=#{secret} ascp")).to(eq('exec: ASPERA_SCP_PASS=🔑 ascp'))
      expect(log("exec: ASPERA_SCP_PASS=#{secret}\nnext")).to(eq("exec: ASPERA_SCP_PASS=🔑\nnext"))
    end

    it 'hides logged data case-insensitively' do
      expect(log("password: #{secret}")).to(eq('password: 🔑'))
      expect(log("Password: #{secret}")).to(eq('Password: 🔑'))
    end

    it 'hides secrets in URL query parameters' do
      expect(log(%Q("POST /processing/x.sh?token=#{secret} HTTP/1.1" 200))).to(eq('"POST /processing/x.sh?token=🔑 HTTP/1.1" 200'))
      expect(log(%Q("GET /cb?code=#{other}&client_secret=#{secret}&state=1 HTTP/1.1" 200))).to(eq(%Q("GET /cb?code=#{other}&client_secret=🔑&state=1 HTTP/1.1" 200)))
    end

    it 'hides get/set options' do
      expect(log("get password=#{secret}")).to(eq('get password=🔑'))
    end

    it 'hides private keys' do
      pem = "-----BEGIN RSA PRIVATE KEY-----\n#{secret}\n-----END RSA PRIVATE KEY-----\n"
      expect(log(pem)).not_to(include(secret))
    end

    it 'hides secrets in exception messages' do
      out = hider.log_formatter(nil).call('ERROR', Time.now, 'test', RuntimeError.new(%Q({"password":"#{secret}"})))
      expect(out).not_to(include(secret))
    end

    it 'shows secrets when log_secrets is set' do
      hider.log_secrets = true
      expect(log(%Q({"password":"#{secret}"}))).to(include(secret))
    end
  end

  describe '#hide_secrets_in_string' do
    it 'hides only private keys by default' do
      expect(hider.hide_secrets_in_string(%Q({"password":"#{secret}"}))).to(include(secret))
      expect(hider.hide_secrets_in_string("-----BEGIN PRIVATE KEY-----\n#{other}\n-----END PRIVATE KEY-----")).not_to(include(other))
    end

    it 'hides all secrets with all: true' do
      expect(hider.hide_secrets_in_string(%Q({"password":"#{secret}"}), all: true)).not_to(include(secret))
    end

    it 'keeps end of line and following lines after a logged secret' do
      expect(hider.hide_secrets_in_string("a --secret=#{secret}\nnext\n", all: true)).to(eq("a --secret=🔑\nnext\n"))
    end
  end

  describe '#secret?' do
    it 'matches keys case-insensitively' do
      expect(hider.secret?('Password', secret)).to(be(true))
      expect(hider.secret?('API_KEY', secret)).to(be(true))
      expect(hider.secret?(:token, secret)).to(be(true))
    end

    it 'ignores false positives and non-string values' do
      expect(hider.secret?('access_key', secret)).to(be(false))
      expect(hider.secret?('Access_Key', secret)).to(be(false))
      expect(hider.secret?('password', true)).to(be(false))
      expect(hider.secret?('username', secret)).to(be(false))
      expect(hider.secret?('public_key', secret)).to(be(false))
      expect(hider.secret?('token_type', 'Bearer')).to(be(false))
    end

    it 'matches additional exact keys' do
      expect(hider.secret?('dsa', secret)).to(be(false))
      hider.add_secret_keys(%i[dsa])
      hider.add_secret_keys(%i[dsa])
      expect(hider.secret?('dsa', secret)).to(be(true))
      expect(hider.instance_variable_get(:@additional_keys).size).to(eq(1))
    end
  end

  describe '#deep_remove_secret' do
    it 'hides secrets in arrays nested in hashes' do
      data = {'items' => [{'name' => 'a', 'password' => secret}], 'sub' => {'Token' => other}}
      expect(hider.deep_remove_secret(data)).to(eq({'items' => [{'name' => 'a', 'password' => '🔑'}], 'sub' => {'Token' => '🔑'}}))
    end
  end
end
