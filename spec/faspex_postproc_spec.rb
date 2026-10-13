# frozen_string_literal: true

require 'aspera/faspex_postproc'
require 'fileutils'
require 'json'
require 'securerandom'
require 'tmpdir'

RSpec.describe(Aspera::Faspex4PostProcServlet) do
  subject(:servlet) { described_class.new(webrick, described_class.normalize_parameters(parameters)) }

  let(:webrick) { WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [], DoNotListen: true) }
  let(:script_folder) { Dir.mktmpdir('postproc') }
  # File written by the script when it is executed
  let(:marker) { File.join(script_folder, 'marker') }
  let(:parameters) { {root: '/processing', script_folder: script_folder} }
  # Minimal stand-in for WEBrick::HTTPRequest
  let(:request_class) do
    Struct.new(:path, :query_string, :body, :client_ip, :headers) do
      def peeraddr = ['AF_INET', 40_000, client_ip, client_ip]
      def [](key) = headers[key]
    end
  end
  # Minimal stand-in for WEBrick::HTTPResponse
  let(:response_class) do
    Class.new do
      attr_accessor :status, :body, :content_type

      def initialize = @headers = {}
      def [](key) = @headers[key]

      def []=(key, value)
        @headers[key] = value
      end
    end
  end

  before do
    script = File.join(script_folder, 'marker.sh')
    File.write(script, "#!/bin/sh\nprintf '%s' \"$faspex_pkg_name\" > '#{marker}'\n")
    File.chmod(0o700, script)
    allow(Aspera::Log.log).to(receive(:warn))
  end

  after { FileUtils.rm_rf(script_folder) }

  # Send a webhook request to the servlet, as Faspex does: JSON body, parameters in URL
  # @param headers [Hash] Headers added to, or replacing, the ones of Faspex
  # @return [Object] response of the servlet
  def post(query_string = nil, script: 'marker.sh', client_ip: '127.0.0.1', body: {faspex_pkg_name: 'executed'}.to_json, headers: {})
    res = response_class.new
    headers = {'Host' => 'localhost:8080', 'Content-Type' => 'application/json', **headers}
    servlet.do_POST(request_class.new("/processing/#{script}", query_string, body, client_ip, headers), res)
    res
  end

  it 'executes the script with webhook values in environment when no protection is configured' do
    res = post
    expect(res.status).to(eq(200))
    expect(JSON.parse(res.body)).to(include('status' => 'success', 'exit_code' => 0))
    expect(File.read(marker)).to(eq('executed'))
  end

  describe 'environment of the script' do
    before do
      script = File.join(script_folder, 'env.sh')
      File.write(script, "#!/bin/sh\nprintf '%s\\n' \"$faspex_metadata_fields\" \"$PATH\" \"${LD_PRELOAD-unset}\" > '#{marker}'\n")
      File.chmod(0o700, script)
    end

    it 'gives faspex_ values, structured values as JSON, and ignores other keys' do
      body = {faspex_metadata_fields: {'_pkg_name' => 'Test'}, PATH: '/attacker', LD_PRELOAD: '/attacker.so'}.to_json
      expect(post(script: 'env.sh', body: body).status).to(eq(200))
      expect(File.read(marker).lines(chomp: true)).to(eq(['{"_pkg_name":"Test"}', ENV.fetch('PATH'), 'unset']))
      expect(Aspera::Log.log).to(have_received(:warn).twice)
    end
  end

  describe 'requests of web pages' do
    it 'refuses a body that is not application/json, sent by a web page without preflight' do
      res = post(headers: {'Content-Type' => 'text/plain'})
      expect(res.status).to(eq(415))
      expect(JSON.parse(res.body)['message']).to(include('Content-Type shall be application/json'))
      expect(File.exist?(marker)).to(be(false))
    end

    it 'refuses a body without Content-Type' do
      expect(post(headers: {'Content-Type' => nil}).status).to(eq(415))
    end

    it 'accepts a Content-Type with parameters' do
      expect(post(headers: {'Content-Type' => 'application/json; charset=utf-8'}).status).to(eq(200))
    end

    it 'refuses a request from a web page of another site' do
      expect(post(headers: {'Origin' => 'https://attacker.example.com'}).status).to(eq(403))
      expect(File.exist?(marker)).to(be(false))
    end

    it 'refuses a host name that is not loopback, as after DNS rebinding' do
      expect(post(headers: {'Host' => 'attacker.example.com:8080', 'Origin' => 'http://attacker.example.com:8080'}).status).to(eq(403))
      expect(File.exist?(marker)).to(be(false))
    end
  end

  describe 'request checks' do
    it 'refuses a body that is not JSON' do
      expect(post(body: 'not json').status).to(eq(400))
    end

    it 'refuses a JSON body that is not an object' do
      expect(post(body: '[1,2]').status).to(eq(400))
    end

    it 'returns 404 for a missing script without disclosing its path' do
      res = post(script: 'missing.sh')
      expect(res.status).to(eq(404))
      expect(res.body).not_to(include(script_folder))
    end

    it 'returns 404 for a folder' do
      Dir.mkdir(File.join(script_folder, 'sub'))
      expect(post(script: 'sub').status).to(eq(404))
    end

    it 'refuses a link to a script outside script_folder' do
      outside = Dir.mktmpdir('outside')
      File.write(File.join(outside, 'x.sh'), "#!/bin/sh\n")
      File.symlink(File.join(outside, 'x.sh'), File.join(script_folder, 'link.sh'))
      expect(post(script: 'link.sh').status).to(eq(403))
    ensure
      FileUtils.rm_rf(outside)
    end
  end

  describe 'lambda in URL query' do
    before { allow(Aspera::Log.log).to(receive(:error)) }

    # @param code [String] Ruby code of the lambda script
    def lambda_script(code, name: 'marker.rb')
      File.write(File.join(script_folder, name), code)
    end

    it 'calls the lambda returned by the Ruby script with all webhook values' do
      lambda_script("->(params) { File.write('#{marker}', params.keys.join(',')) }\n")
      res = post('lambda', script: 'marker.rb', body: {faspex_pkg_name: 'x', other: 'y'}.to_json)
      expect(res.status).to(eq(200))
      expect(JSON.parse(res.body)).to(include('status' => 'success', 'exit_code' => nil))
      expect(File.read(marker)).to(eq('faspex_pkg_name,other'))
    end

    it 'refuses a script that is not Ruby' do
      expect(post('lambda').status).to(eq(400))
      expect(File.exist?(marker)).to(be(false))
    end

    it 'fails if the script does not return a lambda' do
      lambda_script("1\n")
      expect(JSON.parse(post('lambda', script: 'marker.rb').body)['message']).to(include('shall return a lambda'))
    end

    it 'fails on a syntax error' do
      lambda_script("->(params) {\n")
      expect(post('lambda', script: 'marker.rb').status).to(eq(500))
    end

    it 'stops the lambda after timeout_seconds' do
      parameters[:timeout_seconds] = 1
      lambda_script("->(_params) { sleep(10) }\n")
      expect(post('lambda', script: 'marker.rb').status).to(eq(500))
    end
  end

  describe '.normalize_parameters' do
    it 'refuses an unknown parameter' do
      expect { described_class.normalize_parameters(foo: 1) }.to(raise_error(/unsupported parameters: foo/))
    end

    it 'refuses a missing script_folder' do
      expect { described_class.normalize_parameters(script_folder: '/does/not/exist') }.to(raise_error(/script_folder not found/))
    end

    it 'refuses an empty secret_token, which would accept requests without token' do
      expect { described_class.normalize_parameters(secret_token: '') }.to(raise_error(/secret_token must not be empty/))
    end

    it 'refuses a weak secret_token' do
      expect { described_class.normalize_parameters(secret_token: 'MySecretToken2024!') }.to(raise_error(/secret_token is too weak: about \d+ bits, minimum 80/))
    end

    it 'accepts a weak secret_token if secret_token_min_bits allows it' do
      expect(described_class.normalize_parameters(secret_token: 'mysecret', secret_token_min_bits: 0)).to(include(secret_token: 'mysecret'))
    end

    it 'refuses an invalid IP address' do
      expect { described_class.normalize_parameters(allowed_ips: 'not_an_ip') }.to(raise_error(ArgumentError, /invalid IP address or network: not_an_ip/))
    end
  end

  context 'with secret_token' do
    let(:token) { SecureRandom.hex(32) }

    before { parameters[:secret_token] = token }

    it 'refuses a request without token' do
      expect(post.status).to(eq(401))
      expect(File.exist?(marker)).to(be(false))
    end

    it 'refuses a wrong token' do
      expect(post('token=bad').status).to(eq(401))
      expect(File.exist?(marker)).to(be(false))
    end

    it 'executes the script with the token in the URL query' do
      expect(post("token=#{token}").status).to(eq(200))
      expect(File.read(marker)).to(eq('executed'))
    end
  end

  context 'with allowed_ips' do
    before { parameters[:allowed_ips] = ['10.1.2.3', '10.89.0.0/24'] }

    it 'refuses a request from another IP' do
      expect(post.status).to(eq(403))
      expect(File.exist?(marker)).to(be(false))
    end

    it 'executes the script for an allowed IP' do
      expect(post(client_ip: '10.1.2.3').status).to(eq(200))
      expect(File.read(marker)).to(eq('executed'))
    end

    it 'executes the script for an IP in an allowed network' do
      expect(post(client_ip: '10.89.0.42').status).to(eq(200))
    end

    it 'executes the script for an allowed IPv4 seen on a dual-stack listener' do
      expect(post(client_ip: '::ffff:10.1.2.3').status).to(eq(200))
    end

    it 'accepts a single IP as String' do
      parameters[:allowed_ips] = '10.1.2.3'
      expect(post(client_ip: '10.1.2.3').status).to(eq(200))
    end
  end
end
