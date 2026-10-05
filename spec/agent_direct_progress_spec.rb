# frozen_string_literal: true

# Unit tests for Aspera::Agent::Direct: progress events from `ascp` management events.
# Management events are excerpts of actual transfers.

require 'aspera/agent/direct'

RSpec.describe(Aspera::Agent::Direct) do
  let(:events) { [] }
  # Records progress events as: [type, info]
  let(:progress) { double('progress').tap { |recorder| allow(recorder).to(receive(:event)) { |type, info: nil, **| events.push([type, info]) } } }
  let(:agent) { described_class.new(progress: progress) }

  # @param session    [Hash]        Session information
  # @param mgt_events [Array<Hash>] Management events
  def process(session, *mgt_events)
    mgt_events.each { |e| agent.send(:process_progress, session, e) }
  end

  it 'counts the part of a file already at destination (resume)' do
    process(
      {},
      {'Type' => 'INIT'},
      {'Type' => 'NOTIFICATION', 'PreTransferBytes' => '12582912'},
      {'Type' => 'STATS', 'TransferBytes' => '0', 'StartByte' => '2172544', 'FileBytes' => '0', 'Size' => '4194304'},
      {'Type' => 'STATS', 'TransferBytes' => '689920', 'FileBytes' => '2862464', 'Size' => '4194304'},
      {'Type' => 'DONE', 'TransferBytes' => '10410368', 'FileBytes' => '12582912'}
    )
    expect(events).to(eq([
      [:session_start, nil],
      [:session_size, '12582912'],
      [:skip, 0],
      [:transfer, 0],
      [:skip, 2_172_544],
      [:transfer, 689_920],
      [:transfer, 10_410_368],
      [:session_end, nil]
    ]))
  end

  it 'does not count the offset of the part of file transferred by a session (multi-session)' do
    process(
      {},
      {'Type' => 'INIT'},
      {'Type' => 'STATS', 'TransferBytes' => '702592', 'StartByte' => '2096512', 'FileBytes' => '702592', 'Size' => '4194304'},
      {'Type' => 'STOP', 'TransferBytes' => '2100608', 'StartByte' => '2096512', 'FileBytes' => '2100608', 'Size' => '4194304'}
    )
    expect(events.select { |e| e.first.eql?(:skip) }).to(eq([[:skip, 0]]))
    expect(events.last).to(eq([:transfer, 2_100_608]))
  end

  it 'counts whole files already at destination, and their size when not pre-calculated' do
    process(
      {},
      {'Type' => 'INIT'},
      {'Type' => 'STOP', 'TransferBytes' => '0', 'StartByte' => '4194304', 'FileBytes' => '0', 'Size' => '4194304'},
      {'Type' => 'STOP', 'TransferBytes' => '0', 'StartByte' => '4194304', 'FileBytes' => '0', 'Size' => '4194304'},
      {'Type' => 'DONE'}
    )
    expect(events).to(eq([
      [:session_start, nil],
      [:skip, 4_194_304],
      [:transfer, 0],
      [:skip, 8_388_608],
      [:session_size, 8_388_608],
      [:session_end, nil]
    ]))
  end

  it 'uses the same session id when the session is resumed' do
    ids = []
    allow(progress).to(receive(:event)) { |_type, session_id: nil, **| ids.push(session_id) }
    session = {}
    process(session, {'Type' => 'INIT', 'SessionId' => 'a'}, {'Type' => 'ERROR'}, {'Type' => 'INIT', 'SessionId' => 'b'})
    expect(ids.uniq).to(eq([session[:progress_id]]))
    expect(session[:progress_id]).to(be_a(String))
  end
end
