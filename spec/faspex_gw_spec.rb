# frozen_string_literal: true

require 'aspera/faspex_gw'

RSpec.describe(Aspera::Faspex4GWServlet) do
  subject(:servlet) { described_class.new(webrick, described_class.normalize_parameters(parameters), app_api, nil) }

  let(:parameters) { {} }

  let(:webrick) { WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [], DoNotListen: true) }
  # Faspex 5 API: records created packages
  let(:app_api) do
    stub_const('Aspera::Api::Faspex', Class.new do
      const_set(:TRANSFER_CONNECT, 'connect')
      attr_reader :packages

      def initialize = @packages = []

      def create(_subpath, package)
        raise 'Faspex error' if package['title'].eql?('fail')
        @packages.push(package)
        {'id' => 'pkg1'}
      end

      def call(**) = {'remote_host' => 'faspex.example.com', 'authentication' => 'token'}
    end)
    Aspera::Api::Faspex.new
  end
  let(:request_class) do
    Struct.new(:path, :body, :headers) do
      def [](key) = headers[key]
    end
  end
  # Minimal stand-in for WEBrick::HTTPResponse
  let(:response_class) do
    Class.new do
      attr_accessor :status, :body

      def initialize = @headers = {}
      def [](key) = @headers[key]

      def []=(key, value)
        @headers[key] = value
      end
    end
  end

  before do
    allow(Aspera::Log.log).to(receive(:warn))
    allow(Aspera::Log.log).to(receive(:error))
  end

  # Send a Faspex 4 package creation request
  # @return [Array] HTTP status and parsed body of the response
  def send_package(title: 'test', path: '/aspera/faspex/send', headers: {}, body: {delivery: {title: title, note: '', recipients: ['user@example.com']}}.to_json)
    res = response_class.new
    servlet.do_POST(request_class.new(path, body, {'Host' => 'localhost:9443', 'Content-Type' => 'application/json', **headers}), res)
    [res.status, JSON.parse(res.body)]
  end

  it 'creates the package and returns the upload transfer spec' do
    status, body = send_package
    expect(status).to(eq(200))
    expect(body['xfer_sessions']).to(eq([{'remote_host' => 'faspex.example.com'}]))
    expect(app_api.packages).to(eq([{'title' => 'test', 'note' => '', 'recipients' => [{'name' => 'user@example.com'}]}]))
  end

  it 'refuses a package sent by a web page without preflight' do
    expect(send_package(headers: {'Content-Type' => 'text/plain'})).to(match([415, include('error' => /Content-Type/)]))
    expect(app_api.packages).to(be_empty)
  end

  it 'refuses a package sent by a web page of another site' do
    expect(send_package(headers: {'Origin' => 'https://attacker.example.com'}).first).to(eq(403))
    expect(app_api.packages).to(be_empty)
  end

  it 'refuses an unknown endpoint' do
    expect(send_package(path: '/other').first).to(eq(400))
  end

  it 'returns the error without stack trace' do
    expect(send_package(title: 'fail')).to(eq([500, {'error' => 'Faspex error'}]))
  end

  it 'refuses an invalid package creation request' do
    expect(send_package(body: nil)).to(eq([400, {'error' => 'Empty request'}]))
    expect(send_package(body: 'not json').first).to(eq(400))
    expect(send_package(body: '[]').first).to(eq(400))
    expect(send_package(body: {}.to_json)).to(eq([400, {'error' => 'Missing object: delivery'}]))
    expect(send_package(body: {delivery: {title: 'test'}}.to_json).first).to(eq(400))
    expect(send_package(body: {delivery: {recipients: []}}.to_json).first).to(eq(400))
    expect(send_package(body: {delivery: {recipients: [{}]}}.to_json).first).to(eq(400))
    expect(app_api.packages).to(be_empty)
  end

  describe 'with username and password' do
    let(:password) { SecureRandom.hex(32) }
    let(:parameters) { {'username' => 'fx4', 'password' => password} }

    # @return [Hash] Header of Basic authentication
    def basic(username, password) = {'Authorization' => "Basic #{["#{username}:#{password}"].pack('m0')}"}

    it 'accepts the expected credentials' do
      expect(send_package(headers: basic('fx4', password)).first).to(eq(200))
      expect(app_api.packages.length).to(eq(1))
    end

    it 'refuses missing or wrong credentials' do
      [{}, basic('fx4', 'wrong'), basic('other', password), {'Authorization' => "Bearer #{password}"}].each do |headers|
        expect(send_package(headers: headers)).to(eq([401, {'error' => 'Invalid or missing credentials'}]))
      end
      expect(app_api.packages).to(be_empty)
    end

    it 'asks for Basic credentials' do
      res = response_class.new
      servlet.do_POST(request_class.new('/aspera/faspex/send', '{}', {'Host' => 'localhost:9443', 'Content-Type' => 'application/json'}), res)
      expect(res['WWW-Authenticate']).to(eq('Basic realm="Faspex 4 Gateway"'))
    end
  end

  describe '.normalize_parameters' do
    it 'sets the default minimum strength of the password' do
      expect(described_class.normalize_parameters({})).to(eq({password_min_bits: Aspera::SecretStrength::DEFAULT_MIN_BITS}))
    end

    it 'refuses username without password' do
      expect { described_class.normalize_parameters({username: 'fx4'}) }.to(raise_error(Aspera::ParameterError, /together/))
    end

    it 'refuses a weak password' do
      expect { described_class.normalize_parameters({username: 'fx4', password: 'password'}) }.to(raise_error(Aspera::ParameterError, /password_min_bits/))
      expect(described_class.normalize_parameters({username: 'fx4', password: 'password', password_min_bits: 0})).to(include(password: 'password'))
    end

    it 'refuses an unknown parameter' do
      expect { described_class.normalize_parameters({secret_token: 'x'}) }.to(raise_error(Aspera::ParameterError, /secret_token/))
    end
  end
end
