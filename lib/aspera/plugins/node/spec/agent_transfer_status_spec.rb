# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Tests for Aspera::Plugins::Node::Agent.transfer_status class method (async re-query interface),
# and for the status loop of Aspera::Plugins::Node::Agent.
# All external I/O (REST) is doubled — no real daemons required.

require 'spec_helper'
require_relative '../../../rest'
require_relative '../../../transfer/error'
require_relative '../agent'
require 'bundler/setup'
require 'securerandom'

# ── Node ──────────────────────────────────────────────────────────────────────

RSpec.describe('Aspera::Plugins::Node::Agent.transfer_status') do
  before do
    rest_double = instance_double('Aspera::Rest::Client')
    allow(Aspera::Rest::Client).to(receive(:new).and_return(rest_double))
    allow(rest_double).to(receive(:read)) do |path|
      case path
      when %r{ops/transfers/tid-running}
        {'status' => 'running', 'bytes_transferred' => 1024, 'error_desc' => ''}
      when %r{ops/transfers/tid-completed}
        {'status' => 'completed', 'bytes_transferred' => 4096, 'error_desc' => ''}
      when %r{ops/transfers/tid-failed}
        {'status' => 'failed', 'bytes_transferred' => 0, 'error_desc' => 'disk full'}
      when %r{ops/transfers/tid-canceled}
        {'status' => 'canceled', 'bytes_transferred' => 512, 'error_code' => 28, 'error_desc' => 'User aborted session'}
      when %r{ops/transfers/tid-paused}
        {'status' => 'paused', 'bytes_transferred' => 256, 'error_desc' => ''}
      end
    end
  end

  let(:params) { {'url' => 'https://node.example.com', 'username' => 'u', 'password' => SecureRandom.alphanumeric(12)} }

  it 'returns running status' do
    result = Aspera::Plugins::Node::Agent.transfer_status('tid-running', params)
    expect(result['status']).to(eq('running'))
    expect(result['bytes_transferred']).to(eq(1024))
  end

  it 'returns completed status with ended_at' do
    result = Aspera::Plugins::Node::Agent.transfer_status('tid-completed', params)
    expect(result['status']).to(eq('completed'))
    expect(result['ended_at']).not_to(be_nil)
    expect(result['bytes_transferred']).to(eq(4096))
  end

  it 'returns failed status with error message' do
    result = Aspera::Plugins::Node::Agent.transfer_status('tid-failed', params)
    expect(result['status']).to(eq('failed'))
    expect(result['error']).to(eq('disk full'))
    expect(result['ended_at']).not_to(be_nil)
  end

  it 'returns cancelled status with ended_at' do
    result = Aspera::Plugins::Node::Agent.transfer_status('tid-canceled', params)
    expect(result['status']).to(eq('cancelled'))
    expect(result['ended_at']).not_to(be_nil)
    expect(result['bytes_transferred']).to(eq(512))
  end

  it 'returns running status when paused' do
    result = Aspera::Plugins::Node::Agent.transfer_status('tid-paused', params)
    expect(result['status']).to(eq('running'))
    expect(result['ended_at']).to(be_nil)
  end
end

RSpec.describe('Aspera::Plugins::Node::Agent#wait_for_transfers_completion') do
  let(:events) { [] }
  # Records event types, and `info` of `:end`
  let(:progress) { double('progress').tap { |recorder| allow(recorder).to(receive(:event)) { |type, info: nil, **| events.push(type.eql?(:end) ? [type, info] : type) } } }

  # @param statuses [Array<Hash>] transfer read at each poll
  def agent_reading(*statuses)
    rest_double = instance_double('Aspera::Rest::Client')
    allow(Aspera::Rest::Client).to(receive(:new).and_return(rest_double))
    allow(rest_double).to(receive(:read).and_return(*statuses))
    Aspera::Plugins::Node::Agent.new(url: 'https://node.example.com', username: 'u', password: SecureRandom.alphanumeric(12), progress: progress).tap { |agent| allow(agent).to(receive(:sleep)) }
  end

  it 'raises when the transfer is canceled' do
    agent = agent_reading(
      {'status' => 'running', 'bytes_transferred' => 1024, 'error_desc' => ''},
      {'status' => 'canceled', 'bytes_transferred' => 1024, 'error_code' => 28, 'error_desc' => 'User aborted session'}
    )
    expect { agent.wait_for_completion }.to(raise_error(Aspera::Transfer::Error, /status: canceled.*User aborted session/))
    expect(events.last(2)).to(eq([:session_end, [:end, false]]))
  end

  it 'waits while the transfer is paused' do
    agent = agent_reading({'status' => 'paused', 'bytes_transferred' => 0, 'error_desc' => ''}, {'status' => 'completed', 'bytes_transferred' => 1024})
    expect(agent.wait_for_completion).to(be_a(Aspera::Transfer::Result::Success))
    expect(events).to(eq([:sessions_init, :session_end, [:end, true]]))
  end
end
