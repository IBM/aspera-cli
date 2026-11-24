# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../gw_servlet'
require 'securerandom'

RSpec.describe(Aspera::Plugins::Faspex4::GWServlet) do
  subject(:servlet) { described_class.new(webrick, described_class.normalize_parameters(parameters), package_sender) }

  let(:parameters) { {} }

  let(:webrick) { WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [], DoNotListen: true) }
  # Package sender of the product: records the received packages, returns the transfer spec
  let(:package_sender) do
    Class.new do
      attr_reader :packages

      def initialize = @packages = []

      def call(faspex_pkg_parameters)
        delivery = faspex_pkg_parameters['delivery']
        raise 'Faspex error' if delivery['title'].eql?('fail')
        @packages.push(delivery)
        {'remote_host' => 'faspex.example.com'}
      end
    end.new
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
    expect(body).to(eq({'links' => {'status' => 'unused'}, 'xfer_sessions' => [{'remote_host' => 'faspex.example.com'}]}))
    expect(package_sender.packages).to(eq([{'title' => 'test', 'note' => '', 'recipients' => ['user@example.com']}]))
  end

  it 'refuses a package sent by a web page without preflight' do
    expect(send_package(headers: {'Content-Type' => 'text/plain'})).to(match([415, include('error' => /Content-Type/)]))
    expect(package_sender.packages).to(be_empty)
  end

  it 'refuses a package sent by a web page of another site' do
    expect(send_package(headers: {'Origin' => 'https://attacker.example.com'}).first).to(eq(403))
    expect(package_sender.packages).to(be_empty)
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
    expect(package_sender.packages).to(be_empty)
  end

  describe 'with username and password' do
    let(:password) { SecureRandom.hex(32) }
    let(:parameters) { {'username' => 'fx4', 'password' => password} } # HashiCorpIgnore

    # @return [Hash] Header of Basic authentication
    def basic(username, password) = {'Authorization' => "Basic #{["#{username}:#{password}"].pack('m0')}"}

    it 'accepts the expected credentials' do
      expect(send_package(headers: basic('fx4', password)).first).to(eq(200))
      expect(package_sender.packages.length).to(eq(1))
    end

    it 'refuses missing or wrong credentials' do
      [{}, basic('fx4', SecureRandom.hex(32)), basic('other', password), {'Authorization' => "Bearer #{password}"}].each do |headers|
        expect(send_package(headers: headers)).to(eq([401, {'error' => 'Invalid or missing credentials'}]))
      end
      expect(package_sender.packages).to(be_empty)
    end

    it 'asks for Basic credentials' do
      res = response_class.new
      servlet.do_POST(request_class.new('/aspera/faspex/send', '{}', {'Host' => 'localhost:9443', 'Content-Type' => 'application/json'}), res)
      expect(res['WWW-Authenticate']).to(eq('Basic realm="Faspex 4 Gateway"'))
    end
  end

  it 'refuses a package sender that cannot be called' do
    expect { described_class.new(webrick, described_class.normalize_parameters(parameters), nil) }.to(raise_error(Aspera::ParameterError, /callable/))
  end

  describe '.normalize_parameters' do
    it 'sets the default minimum strength of the password' do
      expect(described_class.normalize_parameters({})).to(eq({password_min_bits: Aspera::Secret::Strength::DEFAULT_MIN_BITS}))
    end

    it 'refuses username without password' do
      expect { described_class.normalize_parameters({username: 'fx4'}) }.to(raise_error(Aspera::ParameterError, /together/))
    end

    it 'refuses a weak password' do
      # Short: weak
      weak = SecureRandom.alphanumeric(8)
      expect { described_class.normalize_parameters({username: 'fx4', password: weak}) }.to(raise_error(Aspera::ParameterError, /password_min_bits/)) # HashiCorpIgnore
      expect(described_class.normalize_parameters({username: 'fx4', password: weak, password_min_bits: 0})).to(include(password: weak)) # HashiCorpIgnore
    end

    it 'refuses an unknown parameter' do
      expect { described_class.normalize_parameters({secret_token: SecureRandom.hex(32)}) }.to(raise_error(Aspera::ParameterError, /secret_token/))
    end
  end
end
