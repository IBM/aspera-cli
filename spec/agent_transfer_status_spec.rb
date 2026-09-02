# frozen_string_literal: true

# Tests for Agent::Xxx.transfer_status class methods (async re-query interface).
# All external I/O (REST, JSON-RPC, gRPC) is doubled — no real daemons required.

require 'bundler/setup'
require 'aspera/rest'
require 'aspera/oauth'
require 'aspera/agent/node'
require 'aspera/agent/desktop'
require 'aspera/json_rpc/client'

# ── Node ──────────────────────────────────────────────────────────────────────

RSpec.describe('Aspera::Agent::Node.transfer_status') do
  before do
    rest_double = instance_double('Aspera::Rest')
    allow(Aspera::Rest).to(receive(:new).and_return(rest_double))
    allow(rest_double).to(receive(:read)) do |path|
      case path
      when %r{ops/transfers/tid-running}
        {'status' => 'running', 'bytes_transferred' => 1024, 'error_desc' => ''}
      when %r{ops/transfers/tid-completed}
        {'status' => 'completed', 'bytes_transferred' => 4096, 'error_desc' => ''}
      when %r{ops/transfers/tid-failed}
        {'status' => 'failed', 'bytes_transferred' => 0, 'error_desc' => 'disk full'}
      end
    end
  end

  let(:params){{'url' => 'https://node.example.com', 'username' => 'u', 'password' => 'p'}}

  it 'returns running status' do
    result = Aspera::Agent::Node.transfer_status('tid-running', params)
    expect(result['status']).to(eq('running'))
    expect(result['bytes_transferred']).to(eq(1024))
  end

  it 'returns completed status with ended_at' do
    result = Aspera::Agent::Node.transfer_status('tid-completed', params)
    expect(result['status']).to(eq('completed'))
    expect(result['ended_at']).not_to(be_nil)
    expect(result['bytes_transferred']).to(eq(4096))
  end

  it 'returns failed status with error message' do
    result = Aspera::Agent::Node.transfer_status('tid-failed', params)
    expect(result['status']).to(eq('failed'))
    expect(result['error']).to(eq('disk full'))
    expect(result['ended_at']).not_to(be_nil)
  end
end

# ── Desktop ───────────────────────────────────────────────────────────────────

RSpec.describe('Aspera::Agent::Desktop.transfer_status') do
  before do
    allow(Aspera::Agent::Desktop).to(receive(:desktop_api_url).and_return('http://127.0.0.1:33024'))
    # Stub JSON-RPC client
    client_double = double('JsonRpc::Client')
    allow(Aspera::JsonRpc::Client).to(receive(:new).and_return(client_double))
    allow(client_double).to(receive(:get_transfer)) do |args|
      case args[:transfer_id]
      when 'tid-running'    then {'status' => 'running',   'bytes_written' => 512,  'error_desc' => ''}
      when 'tid-completed'  then {'status' => 'completed', 'bytes_written' => 2048, 'error_desc' => ''}
      when 'tid-cancelled'  then {'status' => 'cancelled', 'bytes_written' => 0,    'error_desc' => ''}
      end
    end
  end

  let(:params){{'application_id' => 'app-uuid-001'}}

  it 'returns running status' do
    result = Aspera::Agent::Desktop.transfer_status('tid-running', params)
    expect(result['status']).to(eq('running'))
    expect(result['bytes_transferred']).to(eq(512))
  end

  it 'returns completed status with ended_at' do
    result = Aspera::Agent::Desktop.transfer_status('tid-completed', params)
    expect(result['status']).to(eq('completed'))
    expect(result['ended_at']).not_to(be_nil)
  end

  it 'returns cancelled status with ended_at' do
    result = Aspera::Agent::Desktop.transfer_status('tid-cancelled', params)
    expect(result['status']).to(eq('cancelled'))
    expect(result['ended_at']).not_to(be_nil)
  end
end
