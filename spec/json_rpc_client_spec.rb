# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/rest'
require 'aspera/json_rpc/client'
require 'webrick'
require 'json'

RSpec.describe(Aspera::JsonRpc::Client) do
  before(:all) do
    # Shared with server: received requests, response status, and builder of response body from request
    @state = {requests: [], status: nil, body: nil}
    state = @state
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    @server.mount_proc('/') do |req, res|
      request = JSON.parse(req.body)
      state[:requests].push(request)
      res.status = state[:status]
      res['Content-Type'] = 'application/json'
      res.body = JSON.generate(state[:body].call(request))
    end
    @thread = Thread.new { @server.start }
    @api = Aspera::Rest::Client.new(base_url: "http://127.0.0.1:#{@server.config[:Port]}")
  end

  after(:all) do
    @server.shutdown
    @thread.join
  end

  before { @state[:requests].clear }

  # Server replies with `status` and body built by block from request
  def reply(status = 200, &block)
    @state[:status] = status
    @state[:body] = block
  end

  # Server replies with request params as result
  def reply_params
    reply { |request| {'jsonrpc' => '2.0', 'id' => request['id'], 'result' => request['params']} }
  end

  def client(namespace = nil) = Aspera::JsonRpc::Client.new(@api, namespace)

  it 'sends named parameters and returns result' do
    reply_params
    expect(client.get_transfer(app_id: 'a', transfer_id: 't')).to(eq({'app_id' => 'a', 'transfer_id' => 't'}))
    expect(@state[:requests]).to(eq([{'jsonrpc' => '2.0', 'method' => 'get_transfer', 'params' => {'app_id' => 'a', 'transfer_id' => 't'}, 'id' => 1}]))
  end

  it 'sends positional parameters with namespace and new id' do
    reply_params
    rpc = client('ns.')
    expect(rpc.add(1, 2)).to(eq([1, 2]))
    expect(rpc.get_info).to(eq([]))
    expect(@state[:requests].map { |request| request.slice('method', 'id') }).to(eq([{'method' => 'ns.add', 'id' => 1}, {'method' => 'ns.get_info', 'id' => 2}]))
  end

  it 'raises error of 2XX response' do
    reply { |request| {'jsonrpc' => '2.0', 'id' => request['id'], 'error' => {'code' => -32601, 'message' => 'Method not found'}} }
    expect { client.foo }.to(raise_error(Aspera::Rest::CallError, 'Method not found (code: -32601)'))
  end

  it 'raises error with null id' do
    reply { {'jsonrpc' => '2.0', 'id' => nil, 'error' => {'code' => -32600, 'message' => 'Invalid Request'}} }
    expect { client.foo }.to(raise_error(Aspera::Rest::CallError, 'Invalid Request (code: -32600)'))
  end

  it 'raises error of non-2XX response' do
    reply(400) { {'jsonrpc' => '2.0', 'id' => nil, 'error' => {'code' => -32600, 'message' => 'Invalid Request'}} }
    expect { client.foo }.to(raise_error(Aspera::Rest::CallError, /Invalid Request/))
  end

  it 'rejects invalid response' do
    [
      [[1], /expecting type Hash/],
      [{'jsonrpc' => '1.0', 'result' => 1}, /bad version/],
      [{'jsonrpc' => '2.0'}, /either result or error/],
      [{'jsonrpc' => '2.0', 'result' => 1, 'error' => {'code' => 1, 'message' => 'm'}}, /either result or error/],
      [{'jsonrpc' => '2.0', 'id' => 999, 'result' => 1}, /bad id/],
      [{'jsonrpc' => '2.0', 'id' => nil, 'result' => 1}, /bad id/],
      [{'jsonrpc' => '2.0', 'error' => 'oops'}, /bad error/],
      [{'jsonrpc' => '2.0', 'error' => {'message' => 'no code'}}, /bad error/]
    ].each do |response, message|
      reply { |request| response.is_a?(Hash) ? {'id' => request['id']}.merge(response) : response }
      expect { client.foo }.to(raise_error(Aspera::Rest::CallError, message), response.to_s)
    end
  end

  it 'does not send implicit conversions as requests' do
    rpc = client
    expect([rpc].flatten.first.equal?(rpc)).to(be(true))
    expect(Array(rpc).first.equal?(rpc)).to(be(true))
    expect(rpc.to_s).to(match(%r{\A#<Aspera::JsonRpc::Client http://127\.0\.0\.1:\d+>\z}))
    expect(@state[:requests]).to(be_empty)
  end

  it 'does not raise on error message in 2XX response of other API' do
    reply { {'error' => {'message' => 'not a failure'}} }
    expect(@api.create('', {})).to(eq({'error' => {'message' => 'not a failure'}}))
  end
end
