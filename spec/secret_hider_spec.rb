# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/secret_hider'

RSpec.describe(Aspera::SecretHider) do
  let(:hider) { described_class.instance }
  let(:formatter) { hider.log_formatter(proc { |_s, _d, _p, m| m }) }

  def log(msg)
    formatter.call('DEBUG', nil, nil, msg)
  end

  describe '#log_formatter' do
    after { hider.log_secrets = false }

    it 'hides JSON values' do
      expect(log('{"password":"secret123"}')).to(eq('{"password":"🔑"}'))
    end

    it 'hides whole JSON value with escaped quote' do
      expect(log('{"password":"se\"cret123"}')).to(eq('{"password":"🔑"}'))
    end

    it 'hides Ruby 3.4+ inspect with string keys' do
      expect(log({'password' => 'secret123'}.inspect)).not_to(include('secret123'))
    end

    it 'hides Ruby 3.4+ inspect with symbol keys' do
      expect(log({user: 'john', password: 'secret123'}.inspect)).to(eq('{user: "john", password: "🔑"}'))
    end

    it 'hides legacy Ruby inspect' do
      expect(log('{"password"=>"secret123", :token=>"abcdef"}')).to(eq('{"password"=>"🔑", :token=>"🔑"}'))
    end

    it 'hides ascp env var in middle and at end of line' do
      expect(log('exec: ASPERA_SCP_PASS=secret123 ascp')).to(eq('exec: ASPERA_SCP_PASS=🔑 ascp'))
      expect(log("exec: ASPERA_SCP_PASS=secret123\nnext")).to(eq("exec: ASPERA_SCP_PASS=🔑\nnext"))
    end

    it 'hides logged data case-insensitively' do
      expect(log('password: secret123')).to(eq('password: 🔑'))
      expect(log('Password: secret123')).to(eq('Password: 🔑'))
    end

    it 'hides get/set options' do
      expect(log('get password=secret123')).to(eq('get password=🔑'))
    end

    it 'hides private keys' do
      pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIabc\n-----END RSA PRIVATE KEY-----\n"
      expect(log(pem)).not_to(include('MIIabc'))
    end

    it 'hides secrets in exception messages' do
      out = hider.log_formatter(nil).call('ERROR', Time.now, 'test', RuntimeError.new('{"password":"secret123"}'))
      expect(out).not_to(include('secret123'))
    end

    it 'shows secrets when log_secrets is set' do
      hider.log_secrets = true
      expect(log('{"password":"secret123"}')).to(include('secret123'))
    end
  end

  describe '#hide_secrets_in_string' do
    it 'hides only private keys by default' do
      expect(hider.hide_secrets_in_string('{"password":"secret123"}')).to(include('secret123'))
      expect(hider.hide_secrets_in_string("-----BEGIN PRIVATE KEY-----\nMIIabc\n-----END PRIVATE KEY-----")).not_to(include('MIIabc'))
    end

    it 'hides all secrets with all: true' do
      expect(hider.hide_secrets_in_string('{"password":"secret123"}', all: true)).not_to(include('secret123'))
    end

    it 'keeps end of line and following lines after a logged secret' do
      expect(hider.hide_secrets_in_string("a --secret=abcdefg\nnext\n", all: true)).to(eq("a --secret=🔑\nnext\n"))
    end
  end

  describe '#secret?' do
    it 'matches keys case-insensitively' do
      expect(hider.secret?('Password', 'x')).to(be(true))
      expect(hider.secret?('API_KEY', 'x')).to(be(true))
      expect(hider.secret?(:token, 'x')).to(be(true))
    end

    it 'ignores false positives and non-string values' do
      expect(hider.secret?('access_key', 'x')).to(be(false))
      expect(hider.secret?('Access_Key', 'x')).to(be(false))
      expect(hider.secret?('password', true)).to(be(false))
      expect(hider.secret?('username', 'x')).to(be(false))
      expect(hider.secret?('public_key', 'x')).to(be(false))
      expect(hider.secret?('token_type', 'Bearer')).to(be(false))
    end

    it 'matches additional exact keys' do
      expect(hider.secret?('dsa', 'x')).to(be(false))
      hider.add_secret_keys(%i[dsa])
      hider.add_secret_keys(%i[dsa])
      expect(hider.secret?('dsa', 'x')).to(be(true))
      expect(hider.instance_variable_get(:@additional_keys).size).to(eq(1))
    end
  end

  describe '#deep_remove_secret' do
    it 'hides secrets in arrays nested in hashes' do
      data = {'items' => [{'name' => 'a', 'password' => 'x'}], 'sub' => {'Token' => 'y'}}
      expect(hider.deep_remove_secret(data)).to(eq({'items' => [{'name' => 'a', 'password' => '🔑'}], 'sub' => {'Token' => '🔑'}}))
    end
  end
end
