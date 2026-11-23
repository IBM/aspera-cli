# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Tests for Aspera::Plugins::Desktop::Agent.transfer_status class method (async re-query interface).
# JSON-RPC is doubled: no Desktop application required.

require_relative '../agent'
require_relative '../../../json_rpc/client'

RSpec.describe('Aspera::Plugins::Desktop::Agent.transfer_status') do
  before do
    allow(Aspera::Plugins::Desktop::Agent).to(receive(:desktop_api_url).and_return('http://127.0.0.1:33024'))
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

  let(:params) { {'application_id' => 'app-uuid-001'} }

  it 'returns running status' do
    result = Aspera::Plugins::Desktop::Agent.transfer_status('tid-running', params)
    expect(result['status']).to(eq('running'))
    expect(result['bytes_transferred']).to(eq(512))
  end

  it 'returns completed status with ended_at' do
    result = Aspera::Plugins::Desktop::Agent.transfer_status('tid-completed', params)
    expect(result['status']).to(eq('completed'))
    expect(result['ended_at']).not_to(be_nil)
  end

  it 'returns cancelled status with ended_at' do
    result = Aspera::Plugins::Desktop::Agent.transfer_status('tid-cancelled', params)
    expect(result['status']).to(eq('cancelled'))
    expect(result['ended_at']).not_to(be_nil)
  end
end
