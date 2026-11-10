# frozen_string_literal: true

# Tests for Agent::Transferd.transfer_status and Agent::Transferd.transfer_cancel (async re-query interface).
# The gRPC stub is doubled: no daemon required. Requires the optional gem grpc.

require 'bundler/setup'
begin
  require 'aspera/agent/transferd'
rescue LoadError => e
  warn("Skipping Agent::Transferd specs: #{e.message}")
  return
end

RSpec.describe(Aspera::Agent::Transferd) do
  let(:api) { Transferd::Api }
  let(:stub) { instance_double(Transferd::Api::TransferService::Stub) }
  let(:params) { {'url' => '127.0.0.1:55002'} }

  before do
    allow(Transferd::Api::TransferService::Stub).to(receive(:new).with('127.0.0.1:55002', :this_channel_is_insecure).and_return(stub))
  end

  # @param status [Symbol] Status of the daemon
  # @param info   [Hash]   Fields of TransferInfo
  # @param error  [Hash, nil] Fields of Error
  # @return [Transferd::Api::QueryTransferResponse] Response of QueryTransfer
  def query_response(status, info = {}, error: nil)
    api::QueryTransferResponse.new(
      transferId:   'tid',
      status:       status,
      transferInfo: info.empty? ? nil : api::TransferInfo.new(**info),
      error:        error && api::Error.new(**error)
    )
  end

  describe '.transfer_status' do
    it 'queries with QueryTransfer and a deadline' do
      expect(stub).to(receive(:query_transfer)) do |request, deadline:|
        expect(request.transferId).to(eq('tid'))
        expect(deadline).to(be_within(2).of(Time.now + 10))
        query_response(:RUNNING, {bytesTransferred: 1024, bytesWritten: 3072, filesCompleted: 1, averageRateKbps: 900, targetRateKbps: 10_000, elapsedUsec: 2_500_000})
      end
      result = described_class.transfer_status('tid', params)
      expect(result).to(include(
        'status' => 'running', 'state' => 'running', 'bytes_transferred' => 1024, 'bytes_written' => 3072, 'files_completed' => 1,
        'rate_kbps' => 900, 'target_rate_kbps' => 10_000, 'elapsed_sec' => 2.5
      ))
      expect(result).not_to(include('ended_at', 'error'))
    end

    it 'gives queued and paused transfers as running, with the state of the daemon' do
      allow(stub).to(receive(:query_transfer).and_return(query_response(:QUEUED)))
      expect(described_class.transfer_status('tid', params)).to(eq('status' => 'running', 'state' => 'queued', 'bytes_transferred' => 0))
    end

    it 'gives completed with its end time (milliseconds or microseconds since epoch)' do
      ended = Time.utc(2026, 11, 10, 12, 0, 0)
      allow(stub).to(receive(:query_transfer).and_return(query_response(:COMPLETED, {bytesTransferred: 4096, endTimeUsec: (ended.to_f * 1000).to_i})))
      expect(described_class.transfer_status('tid', params)).to(include('status' => 'completed', 'bytes_transferred' => 4096, 'ended_at' => ended.iso8601))
      allow(stub).to(receive(:query_transfer).and_return(query_response(:COMPLETED, {bytesTransferred: 4096, endTimeUsec: (ended.to_f * 1_000_000).to_i})))
      expect(described_class.transfer_status('tid', params)).to(include('ended_at' => ended.iso8601))
    end

    it 'gives failed with the error of the transfer' do
      allow(stub).to(receive(:query_transfer).and_return(query_response(:FAILED, {errorCode: '44', errorDescription: " \n Failed to open TCP connection for SSH"})))
      result = described_class.transfer_status('tid', params)
      expect(result).to(include('status' => 'failed', 'error_code' => '44', 'error' => 'Failed to open TCP connection for SSH'))
      expect(result['ended_at']).not_to(be_nil)
    end

    it 'gives cancelled' do
      allow(stub).to(receive(:query_transfer).and_return(query_response(:CANCELED, {bytesTransferred: 10})))
      expect(described_class.transfer_status('tid', params)).to(include('status' => 'cancelled', 'bytes_transferred' => 10))
    end

    it 'gives unknown for a transfer that the daemon does not know' do
      allow(stub).to(receive(:query_transfer).and_return(query_response(:UNKNOWN_STATUS, error: {code: 404, description: 'transfer id=tid not found'})))
      expect(described_class.transfer_status('tid', params)).to(eq('status' => 'unknown', 'bytes_transferred' => 0, 'error' => 'transfer id=tid not found'))
    end

    it 'gives unknown when the daemon cannot be reached' do
      allow(stub).to(receive(:query_transfer).and_raise(GRPC::Unavailable.new('failed to connect to all addresses')))
      expect(described_class.transfer_status('tid', params)).to(include('status' => 'unknown', 'error' => a_string_starting_with('Unavailable: failed to connect')))
    end

    it 'uses the timeout of the parameters' do
      expect(stub).to(receive(:query_transfer)) do |_request, deadline:|
        expect(deadline).to(be_within(1).of(Time.now + 2))
        query_response(:RUNNING)
      end
      described_class.transfer_status('tid', params.merge('timeout' => 2))
    end
  end

  describe '.transfer_cancel' do
    it 'stops the transfer' do
      expect(stub).to(receive(:stop_transfer)) do |request, deadline:|
        expect(request.transferId.to_a).to(eq(['tid']))
        expect(deadline).to(be_a(Time))
        api::StopTransferResponse.new(stopResult: [api::StopInfo.new(transferId: 'tid', stopped: true)])
      end
      expect(described_class.transfer_cancel('tid', params)).to(be(true))
    end

    it 'raises the error of the daemon when not stopped' do
      allow(stub).to(receive(:stop_transfer).and_return(
        api::StopTransferResponse.new(stopResult: [api::StopInfo.new(transferId: 'tid', stopped: false, error: api::Error.new(code: 417, description: 'transfer id=tid not found'))])
      ))
      expect { described_class.transfer_cancel('tid', params) }.to(raise_error(Aspera::Transfer::Error, 'transfer id=tid not found'))
    end
  end

  it 'is not supported by the base agent' do
    expect(Aspera::Agent::Base.transfer_cancel('tid', params)).to(be_nil)
  end
end
