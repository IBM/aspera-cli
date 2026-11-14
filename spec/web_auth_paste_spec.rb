# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/web_auth/receiver'
require_relative '../lib/aspera/web_auth/blob'

RSpec.describe(Aspera::WebAuth::Paste) do
  describe '.parse' do
    it 'extracts the query of a full redirect URL' do
      expect(described_class.parse('http://localhost:12345/?code=abc&state=xyz')).to(eq('code' => 'abc', 'state' => 'xyz'))
    end

    it 'accepts a query only, with or without "?"' do
      expect(described_class.parse('code=abc&state=xyz')).to(eq('code' => 'abc', 'state' => 'xyz'))
      expect(described_class.parse('?code=abc&state=xyz')).to(eq('code' => 'abc', 'state' => 'xyz'))
    end

    it 'ignores surrounding spaces, newline and fragment' do
      expect(described_class.parse("  http://127.0.0.1:1/cb?code=a%2Bb&state=s#frag\n")).to(eq('code' => 'a+b', 'state' => 's'))
    end

    it 'refuses empty input' do
      expect { described_class.parse('  ') }.to(raise_error(Aspera::ParameterError, /Nothing/))
    end

    it 'refuses a URL without query' do
      expect { described_class.parse('http://localhost:12345/') }.to(raise_error(Aspera::ParameterError, /No query/))
    end

    it 'refuses a query without state' do
      expect { described_class.parse('http://localhost:12345/?code=abc') }.to(raise_error(Aspera::ParameterError, /"state"/))
    end

    it 'refuses a code alone' do
      expect { described_class.parse('abc') }.to(raise_error(Aspera::ParameterError, /"state"/))
    end

    it 'accepts the reply code shown by the browser of the workstation' do
      code = Aspera::WebAuth::Blob.encode(:reply, {'code' => 'abc', 'state' => 'xyz'})
      expect(described_class.parse(code)).to(eq('code' => 'abc', 'state' => 'xyz'))
      expect(described_class.parse("  #{code.downcase}\n")).to(eq('code' => 'abc', 'state' => 'xyz'))
    end

    it 'refuses a reply code without state' do
      expect { described_class.parse(Aspera::WebAuth::Blob.encode(:reply, {'code' => 'abc'})) }.to(raise_error(Aspera::ParameterError, /"state"/))
    end

    it 'refuses a login code, for the workstation' do
      expect { described_class.parse(Aspera::WebAuth::Blob.encode(:login, {'state' => 'x'})) }.to(raise_error(Aspera::ParameterError, /workstation/))
    end

    it 'refuses a damaged code' do
      code = Aspera::WebAuth::Blob.encode(:reply, {'code' => 'abc', 'state' => 'xyz'})
      expect { described_class.parse(code[0..-4]) }.to(raise_error(Aspera::ParameterError))
    end
  end

  describe '#received_request' do
    let(:paste) { described_class.new('http://localhost:12345') }
    let(:login_paste) { described_class.new('http://localhost:12345', login_url: 'https://idp.example.com/authorize?a=1&b=2', reply_keys: %w[code state]) }

    # Messages given to the user (through the logger), evaluated
    let(:shown) { [] }

    before do
      allow(Aspera::Log.log).to(receive(:warn)) { |*args, &block| shown << (block ? block.call : args.first) }
    end

    it 'reads the pasted URL as a sensitive input' do
      allow(Aspera::Cli::Prompt).to(receive(:prompt_user_input).and_return('http://localhost:12345/?code=abc&state=xyz'))
      expect(paste.received_request).to(eq('code' => 'abc', 'state' => 'xyz'))
      expect(shown.join("\n")).to(match(/connection error.*localhost:12345/m))
      expect(Aspera::Cli::Prompt).to(have_received(:prompt_user_input).with('Code or URL', sensitive: true))
    end

    it 'reads the URL from standard input if it is not a terminal' do
      allow($stdin).to(receive_messages(tty?: false, gets: "http://localhost:12345/?code=abc&state=xyz\n"))
      expect { expect(paste.received_request).to(eq('code' => 'abc', 'state' => 'xyz')) }.to(output(/Code or URL> /).to_stderr)
    end

    it 'does not propose the workstation command without login URL' do
      allow(Aspera::Cli::Prompt).to(receive(:prompt_user_input).and_return('code=abc&state=xyz'))
      paste.received_request
      expect(shown.join("\n")).not_to(match(/web_login/))
    end

    it 'gives the login URL in its message only with the login page' do
      expect(paste.shows_login_url?).to(be(false))
      expect(login_paste.shows_login_url?).to(be(true))
      allow(Aspera::Cli::Prompt).to(receive(:prompt_user_input).and_return('code=abc&state=xyz'))
      login_paste.received_request
      expect(shown.join("\n")).to(include('https://idp.example.com/authorize?a=1&b=2'))
    end

    it 'gives the code of the command for the workstation, with the login page, then reads the reply code' do
      reply = Aspera::WebAuth::Blob.encode(:reply, {'code' => 'abc', 'state' => 'xyz'})
      allow(Aspera::Cli::Prompt).to(receive(:prompt_user_input).and_return(reply))
      expect(login_paste.received_request).to(eq('code' => 'abc', 'state' => 'xyz'))
      command = shown.join("\n")[/ascli config web_login (DCODE1L[A-Z2-7]+)/, 1]
      expect(command).not_to(be_nil)
      type, data = Aspera::WebAuth::Blob.decode(command)
      expect(type).to(eq(:login))
      expect(data).to(eq('login_url' => 'https://idp.example.com/authorize?a=1&b=2', 'redirect_uri' => 'http://localhost:12345', 'reply_keys' => %w[code state]))
    end
  end
end

RSpec.describe(Aspera::WebAuth, '.receiver') do
  let(:environment) { Aspera::Environment.instance }

  around do |example|
    saved = [environment.web_auth, environment.url_method, environment.browser_command]
    example.run
  ensure
    environment.web_auth, environment.url_method, environment.browser_command = saved
  end

  it 'listens on a port by default' do
    server = instance_double(Aspera::WebAuth::Server)
    allow(Aspera::WebAuth::Server).to(receive(:new).with('http://localhost:12345', 'info').and_return(server))
    environment.web_auth = :port
    expect(described_class.receiver('http://localhost:12345', 'info')).to(be(server))
  end

  it 'does not start a server with paste' do
    allow(Aspera::WebAuth::Server).to(receive(:new))
    environment.web_auth = :paste
    expect(described_class.receiver('http://localhost:12345')).to(be_a(Aspera::WebAuth::Paste))
    expect(Aspera::WebAuth::Server).not_to(have_received(:new))
  end

  it 'gives the login page to paste, for the workstation' do
    environment.web_auth = :paste
    environment.url_method = :text
    environment.browser_command = nil
    paste = described_class.receiver('http://localhost:12345', nil, login_url: 'https://idp.example.com/a', reply_keys: %w[code state])
    expect(paste.instance_variable_get(:@login_url)).to(eq('https://idp.example.com/a'))
    expect(paste.instance_variable_get(:@reply_keys)).to(eq(%w[code state]))
  end

  it 'does not give the login page to paste if the browser is started by ascli' do
    environment.web_auth = :paste
    environment.url_method = :graphical
    environment.browser_command = nil
    paste = described_class.receiver('http://localhost:12345', nil, login_url: 'https://idp.example.com/a', reply_keys: %w[code state])
    expect(paste.instance_variable_get(:@login_url)).to(be_nil)
  end

  it 'does not give the login page to paste if a browser command is set' do
    environment.web_auth = :paste
    environment.url_method = :text
    environment.browser_command = ['firefox']
    paste = described_class.receiver('http://localhost:12345', nil, login_url: 'https://idp.example.com/a', reply_keys: %w[code state])
    expect(paste.instance_variable_get(:@login_url)).to(be_nil)
  end

  it 'suggests paste in a SSH session with terminal mode and port' do
    allow(Aspera::WebAuth::Server).to(receive(:new))
    allow(Aspera::Log.log).to(receive(:warn))
    environment.web_auth = :port
    environment.url_method = :text
    stub_const('ENV', ENV.to_h.merge('SSH_CONNECTION' => '1.2.3.4 1 5.6.7.8 22'))
    described_class.receiver('http://localhost:12345')
    expect(Aspera::Log.log).to(have_received(:warn))
  end

  it 'does not suggest paste without SSH session' do
    allow(Aspera::WebAuth::Server).to(receive(:new))
    allow(Aspera::Log.log).to(receive(:warn))
    environment.web_auth = :port
    environment.url_method = :text
    stub_const('ENV', ENV.to_h.except('SSH_CONNECTION', 'SSH_TTY'))
    described_class.receiver('http://localhost:12345')
    expect(Aspera::Log.log).not_to(have_received(:warn))
  end
end
