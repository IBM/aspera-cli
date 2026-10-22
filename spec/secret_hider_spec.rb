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
    expect(hider.hidden_copy({'password' => secret})).to(eq({'password' => '***'}))
    hider.add_secret_values(secret)
    expect(hider.hidden_copy("a #{secret} b")).to(eq('a *** b'))
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

    it 'hides rendered Ruby Struct and object' do
      expect(log(%Q(#<struct O user="john", password="#{secret}">))).to(eq('#<struct O user="john", password="🔑">'))
      expect(log(%Q(#<C:0x0001 @user="john", @password="#{secret}">))).to(eq('#<C:0x0001 @user="john", @password="🔑">'))
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

  describe '#add_secret_values' do
    it 'hides a declared value in logs, strings and structures' do
      hider.add_secret_values(secret)
      expect(log("got: #{secret} end")).to(eq('got: 🔑 end'))
      expect(hider.hide_secrets_in_string("Bearer #{secret}")).to(eq('Bearer 🔑'))
      expect(hider.hidden_copy({'a' => ["x #{secret} y", 1], 'b' => {'c' => secret}})).to(eq({'a' => ['x 🔑 y', 1], 'b' => {'c' => '🔑'}}))
    end

    it 'hides escaped forms of a declared value' do
      value = "#{secret}\"/ &#{other}"
      hider.add_secret_values(value)
      expect(log(JSON.generate({'v' => value}))).to(eq('{"v":"🔑"}'))
      expect(log("?q=#{URI.encode_www_form_component(value)}&r=1")).to(eq('?q=🔑&r=1'))
      expect(log(value.inspect)).to(eq('"🔑"'))
    end

    it 'hides a short value only as a whole string' do
      short = SecureRandom.alphanumeric(6)
      hider.add_secret_values(short)
      expect(hider.hidden_copy(short)).to(eq('🔑'))
      expect(hider.hidden_copy("x#{short}y")).to(eq("x#{short}y"))
    end

    it 'hides the longest declared value first' do
      hider.add_secret_values(secret, "#{secret}#{other}")
      expect(hider.hidden_copy("a #{secret}#{other} b")).to(eq('a 🔑 b'))
    end

    it 'ignores empty and non-string values' do
      expect { hider.add_secret_values('', nil, 12_345_678, true) }.not_to(change { hider.hidden_copy('') })
    end
  end

  describe '#add_secrets_in' do
    it 'declares values found by key name' do
      hider.add_secrets_in({'list' => [{'remote_password' => secret, 'remote_user' => other}]})
      expect(hider.hidden_copy("#{secret} #{other}")).to(eq("🔑 #{other}"))
    end
  end

  describe '#hidden_copy' do
    it 'hides secrets in arrays nested in hashes, without modifying them' do
      data = {'items' => [{'name' => 'a', 'password' => secret}], 'sub' => {'Token' => other}}
      original = Marshal.load(Marshal.dump(data))
      expect(hider.hidden_copy(data)).to(eq({'items' => [{'name' => 'a', 'password' => '🔑'}], 'sub' => {'Token' => '🔑'}}))
      expect(data).to(eq(original))
    end

    it 'hides secrets in a Struct, without modifying it' do
      data = Struct.new(:user, :password).new('a', secret)
      expect(hider.hidden_copy(data).to_a).to(eq(['a', '🔑']))
      expect(data.password).to(eq(secret))
    end
  end

  describe '#contains_secret?' do
    it 'detects a secret by key name, or declared value, also nested' do
      expect(hider.contains_secret?({'a' => [{'password' => secret}]})).to(be(true)) # HashiCorpIgnore
      expect(hider.contains_secret?({'a' => ["x #{other} y", 1]})).to(be(false))
      hider.add_secret_values(other)
      expect(hider.contains_secret?({'a' => ["x #{other} y", 1]})).to(be(true))
      expect(hider.contains_secret?(other)).to(be(true))
      expect(hider.contains_secret?(12)).to(be(false))
    end
  end
end
