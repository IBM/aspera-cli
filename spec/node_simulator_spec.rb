# frozen_string_literal: true

# cspell:ignore precalc noxfer
# Tests for NodeSimulator: mapping of transferd messages to Node API, and transfer store.
# transferd is replaced by a fake gRPC client — no daemon required.
# Test values are the ones seen on real transfers (time stamps in milliseconds).
# Tests for NodeSimulatorServlet: HTTP server on a free port, with a fake backend.

require 'bundler/setup'
require 'aspera/node_simulator'
require 'net/http'
require 'tmpdir'

module Aspera
  # Test data and helpers
  module NodeSimulatorTest
    API = ::Transferd::Api

    # Replaces `Transferd::Api::TransferService::Stub`
    class FakeTransferClient
      attr_reader :requests, :stop_requests, :modify_requests

      # @param sequences [Array<Array>] responses streamed for each started transfer, the last sequence is repeated
      def initialize(*sequences, error: nil, stop_response: nil, modify_response: nil)
        @sequences = sequences
        @error = error
        @stop_response = stop_response
        @modify_response = modify_response
        @requests = []
        @stop_requests = []
        @modify_requests = []
      end

      def start_transfer_with_monitor(request, &block)
        @requests.push(request)
        raise @error if @error
        (@sequences[@requests.length - 1] || @sequences.last).each(&block)
      end

      def stop_transfer(request)
        @stop_requests.push(request)
        @stop_response || API::StopTransferResponse.new(stopResult: request.transferId.map { |id| API::StopInfo.new(transferId: id, stopped: true) })
      end

      def modify_transfer(request)
        @modify_requests.push(request)
        @modify_response || API::TransferModificationResponse.new(transferId: request.transferId, status: :RUNNING)
      end
    end

    # Backend of the servlet, with one known transfer
    class FakeSimulator
      # calls to `transfers`, `cancel` and `modify`
      attr_reader :calls

      def initialize(start_error: nil)
        @start_error = start_error
        @calls = []
      end

      def start(_transfer_spec)
        raise @start_error if @start_error
        TRANSFER_ID
      end

      def transfer(id)
        {'id' => TRANSFER_ID, 'status' => 'running'} if id.eql?(TRANSFER_ID)
      end

      def transfers(**filters)
        @calls.push([:transfers, filters])
        [transfer(TRANSFER_ID)]
      end

      def cancel(id)
        @calls.push([:cancel, id])
        id.eql?(TRANSFER_ID)
      end

      def modify(id, changes)
        @calls.push([:modify, id, changes])
        id.eql?(TRANSFER_ID)
      end
    end

    TRANSFER_ID = 'cb71b88d-e4ac-499e-9673-70ab34ddf416'
    SESSION_ID = '3482c330-7356-4d08-a3eb-8ff0e5b6c2c8'
    FILE_ID = 'bc8fc988-175afb21-583dd464-dc2c4518-7c777e58'
    START_MSEC = 1_790_595_422_000
    START_USEC = START_MSEC * 1000

    extend self

    def transfer_response(status, event, info: {}, session: nil, file: nil, error: nil, transfer_id: TRANSFER_ID)
      API::TransferResponse.new(
        transferId:    transfer_id,
        status:        status,
        transferEvent: event,
        transferInfo:  API::TransferInfo.new(direction: 'send', **info),
        sessionInfo:   session && API::SessionTransferInformation.new(sessionId: SESSION_ID, id: '4bdaa685-66ba-4e1a-ad0b-a11a671844f5', startTimeUsec: START_MSEC, **session),
        fileInfo:      file && API::FileTransferInformation.new(**file),
        error:         error
      )
    end

    # Sequence of events of a successful upload of one file of 30 MB
    QUEUED_EVENT = transfer_response(:QUEUED, :CONNECTING, session: {status: 'Draft'})
    RUNNING_EVENT = transfer_response(:RUNNING, :SESSION_START, session: {status: 'Running', precalc: 'Yes', serverNodeId: 'f6b762bd', remoteAddress: '149.81.35.193'})
    PROGRESS_EVENT = transfer_response(
      :RUNNING, :PROGRESS,
      info:    {averageRateKbps: 56772, bytesTransferred: 14_219_392, bytesWritten: 14_219_392, bytesLost: 1408, elapsedUsec: 2_003_695},
      session: {status: 'Running', precalc: 'Yes', preTransferBytes: 30_000_000, preTransferFiles: 1, bytesTransferred: 14_219_392, elapsedUsec: 2_003_695},
      file:    {fileId: FILE_ID, sessionId: SESSION_ID, path: '/tmp/sim_test_30M.bin', status: 'TRANSFERRING', size: 30_000_000, bytesWritten: 14_219_392}
    )
    ARG_STOP_EVENT = transfer_response(:RUNNING, :ARG_STOP, session: {status: 'Running'}, file: {path: '/tmp/sim_test_30M.bin', status: 'FINISHED'})
    COMPLETED_EVENT = transfer_response(
      :COMPLETED, :SESSION_STOP,
      info:    {averageRateKbps: 66156, bytesTransferred: 30_000_000, bytesWritten: 30_000_000, bytesLost: 1408, elapsedUsec: 3_627_748, endTimeUsec: 1_790_595_425_627, filesCompleted: 1},
      session: {
        status: 'Completed', precalc: 'Yes', preTransferBytes: 30_000_000, preTransferFiles: 1, bytesTransferred: 30_000_000, elapsedUsec: 3_627_748,
        endTimeUsec: 1_790_595_425_627, filesCompleted: 1, sourcePathsScanAttempted: 1, sourcePathsScanCompleted: 1, argScansAttempted: 1, argScansCompleted: 1, transfersAttempted: 1
      }
    )
    SUCCESS_EVENTS = [QUEUED_EVENT, RUNNING_EVENT, PROGRESS_EVENT, ARG_STOP_EVENT, COMPLETED_EVENT].freeze

    def entry_after(events, start_spec = {})
      {start_spec: start_spec, sessions: {}, files: {}, rates: {}}.tap { |entry| events.each { |event| NodeSimulator.update_entry(entry, event) } }
    end

    RSpec.describe(NodeSimulator) do
      include NodeSimulatorTest

      describe '.node_status' do
        {
          UNKNOWN_STATUS: 'waiting',
          QUEUED:         'waiting',
          RUNNING:        'running',
          COMPLETED:      'completed',
          FAILED:         'failed',
          ORPHANED:       'failed',
          CANCELED:       'canceled',
          PAUSED:         'paused'
        }.each do |transferd_status, node_status|
          it "maps #{transferd_status} to #{node_status}" do
            expect(described_class.node_status(transferd_status)).to(eq(node_status))
          end
        end
      end

      describe '.message_to_hash' do
        it 'converts names to snake case, keeps default values, converts milliseconds' do
          hash = described_class.message_to_hash(API::SessionTransferInformation.new(clientIPAddress: '10.0.0.1', startTimeUsec: START_MSEC), {})
          expect(hash['client_ip_address']).to(eq('10.0.0.1'))
          expect(hash['start_time_usec']).to(eq(START_USEC))
          expect(hash['bytes_transferred']).to(eq(0))
          expect(hash['pre_transfer_bytes']).to(eq(0))
        end

        it 'keeps times already in microseconds, and elapsed time' do
          hash = described_class.message_to_hash(API::TransferInfo.new(endTimeUsec: START_USEC, elapsedUsec: 2_003_695), {})
          expect(hash['end_time_usec']).to(eq(START_USEC))
          expect(hash['elapsed_usec']).to(eq(2_003_695))
        end

        it 'applies overrides' do
          hash = described_class.message_to_hash(API::SessionTransferInformation.new(id: 'internal', sessionId: SESSION_ID), {'id' => nil, 'sessionId' => 'id'})
          expect(hash['id']).to(eq(SESSION_ID))
          expect(hash).not_to(have_key('session_id'))
        end
      end

      describe '.session_to_node' do
        let(:session) { described_class.session_to_node(COMPLETED_EVENT.sessionInfo, retry_timeout: 150) }

        it 'maps identification and status' do
          expect(session).to(include('id' => SESSION_ID, 'status' => 'completed', 'retry_count' => 0, 'retry_timeout' => 150, 'stalled' => false))
        end

        it 'maps counters and times' do
          expect(session).to(include(
            'bytes_transferred' => 30_000_000, 'files_completed' => 1, 'elapsed_usec' => 3_627_748,
            'start_time_usec' => START_USEC, 'end_time_usec' => 1_790_595_425_627_000, 'error_code' => 0, 'error_desc' => ''
          ))
          expect(session['avg_rate_kbps']).to(be_within(1).of(66156))
        end

        it 'maps source statistics' do
          expect(session['source_statistics']).to(include(
            'args_scan_attempted' => 1, 'args_scan_completed' => 1, 'paths_scan_attempted' => 1,
            'files_scan_completed' => 1, 'files_xfer_attempted' => 1, 'files_xfer_fail' => 0, 'files_xfer_noxfer' => 0
          ))
        end

        it 'maps precalc' do
          expect(session['precalc']).to(eq(
            'enabled' => true, 'status' => 'ready', 'bytes_expected' => 30_000_000, 'files_expected' => 1, 'directories_expected' => 0, 'files_special' => 0
          ))
        end

        it 'uses the remote address as server address, maps draft to waiting' do
          expect(described_class.session_to_node(RUNNING_EVENT.sessionInfo)['server_ip_address']).to(eq('149.81.35.193'))
          draft = described_class.session_to_node(QUEUED_EVENT.sessionInfo)
          expect(draft['status']).to(eq('waiting'))
          expect(draft['precalc']).to(include('enabled' => false, 'status' => 'pending'))
        end
      end

      describe '.file_to_node' do
        it 'maps a file in progress' do
          file = described_class.file_to_node(PROGRESS_EVENT.fileInfo)
          expect(file).to(include('id' => FILE_ID, 'session_id' => SESSION_ID, 'path' => '/tmp/sim_test_30M.bin', 'status' => 'running', 'size' => 30_000_000, 'bytes_written' => 14_219_392, 'end_time_usec' => 0))
        end

        it 'computes end time of a finished file' do
          file = described_class.file_to_node(API::FileTransferInformation.new(fileId: FILE_ID, status: 'FINISHED', startTimeUsec: START_MSEC, elapsedUsec: 1_000_000, fileType: 'file'))
          expect(file).to(include('status' => 'completed', 'type' => 'file', 'start_time_usec' => START_USEC, 'end_time_usec' => START_USEC + 1_000_000))
        end
      end

      describe '.update_entry and .transfer_to_node' do
        def node_transfer(events, start_spec = {})
          described_class.transfer_to_node(TRANSFER_ID, entry_after(events, start_spec))
        end

        it 'is waiting after queued event' do
          transfer = node_transfer([QUEUED_EVENT])
          expect(transfer).to(include('id' => TRANSFER_ID, 'status' => 'waiting', 'bytes_transferred' => 0, 'start_time_usec' => START_USEC, 'end_time_usec' => 0, 'files' => []))
          expect(transfer['precalc']['status']).to(eq('pending'))
          expect(transfer['sessions'].length).to(eq(1))
        end

        it 'is running with known size after progress' do
          transfer = node_transfer(SUCCESS_EVENTS.first(3))
          expect(transfer).to(include('status' => 'running', 'bytes_transferred' => 14_219_392, 'avg_rate_kbps' => 56772))
          expect(transfer['precalc']).to(include('status' => 'ready', 'bytes_expected' => 30_000_000, 'files_expected' => 1, 'enabled' => true))
          expect(transfer['files'].map { |file| file['status'] }).to(eq(['running']))
        end

        it 'is completed after last event, file without id ignored' do
          transfer = node_transfer(SUCCESS_EVENTS)
          expect(transfer).to(include(
            'status' => 'completed', 'bytes_transferred' => 30_000_000, 'files_completed' => 1,
            'end_time_usec' => 1_790_595_425_627_000, 'error_code' => 0, 'error_desc' => ''
          ))
          expect(transfer['sessions'].map { |session| session['status'] }).to(eq(['completed']))
          expect(transfer['files'].map { |file| file['id'] }).to(eq([FILE_ID]))
        end

        it 'maps a failure' do
          failed = transfer_response(
            :FAILED, :SESSION_ERROR,
            info:    {endTimeUsec: START_MSEC, errorCode: '43', errorDescription: " \n No such file or directory"},
            session: {status: 'Failed', errorCode: 43, errorDesc: 'No such file or directory'}
          )
          transfer = node_transfer([QUEUED_EVENT, RUNNING_EVENT, failed])
          expect(transfer).to(include('status' => 'failed', 'error_code' => 43, 'error_desc' => 'No such file or directory'))
          expect(transfer['precalc']['status']).to(eq('ready'))
          expect(transfer['sessions'].first).to(include('status' => 'failed', 'error_code' => 43))
        end

        it 'uses the error of the response when transfer info has none' do
          failed = transfer_response(:FAILED, :UNKNOWN_EVENT, error: API::Error.new(code: 1, description: 'bad spec'))
          expect(node_transfer([failed])['error_desc']).to(eq('bad spec'))
        end

        it 'takes retry timeout from the transfer spec' do
          transfer = node_transfer([QUEUED_EVENT], {'tags' => {'aspera' => {'xfer_retry' => 150}}})
          expect(transfer['sessions'].first['retry_timeout']).to(eq(150))
        end

        it 'takes current rates from rate modification, not from session information' do
          session = {status: 'Running', targetRateKbps: 1000}
          modified = transfer_response(:RUNNING, :RATE_MODIFICATION, session: session).tap { |event| event.message = '{"Adaptive":"Adaptive","MinRate":100,"Rate":"600"}' }
          progress = transfer_response(:RUNNING, :PROGRESS, session: session)
          invalid = transfer_response(:RUNNING, :RATE_MODIFICATION, session: session).tap { |event| event.message = 'not json' }
          expect(node_transfer([RUNNING_EVENT, progress])['sessions'].first).to(include('target_rate_kbps' => 1000, 'min_rate_kbps' => 0))
          expect(node_transfer([RUNNING_EVENT, modified, progress])['sessions'].first).to(include('target_rate_kbps' => 600, 'min_rate_kbps' => 100))
          expect(node_transfer([RUNNING_EVENT, invalid, progress])['sessions'].first).to(include('target_rate_kbps' => 1000))
        end
      end

      describe 'transfer store' do
        let(:transfer_spec) { {'remote_host' => 'eudemo.asperademo.com', 'remote_password' => 'secret_value', 'direction' => 'send', 'resume_policy' => 'sparse_csum'} }

        def wait_status(simulator, id, status)
          Timeout.timeout(2) { sleep(0.01) until simulator.transfer(id)['status'].eql?(status) }
          simulator.transfer(id)
        end

        it 'starts a transfer and follows its status until completion' do
          client = FakeTransferClient.new(SUCCESS_EVENTS)
          simulator = described_class.new(transfer_client: client)
          id = simulator.start(transfer_spec)
          expect(id).to(eq(TRANSFER_ID))
          transfer = wait_status(simulator, id, 'completed')
          expect(transfer['bytes_transferred']).to(eq(30_000_000))
          expect(simulator.transfers.map { |t| t['id'] }).to(eq([TRANSFER_ID]))
        end

        it 'sends the transfer spec to transferd, returns it without secrets' do
          client = FakeTransferClient.new(SUCCESS_EVENTS)
          simulator = described_class.new(transfer_client: client)
          id = simulator.start(transfer_spec)
          sent = JSON.parse(client.requests.first.transferSpec)
          expect(sent['remote_password']).to(eq('secret_value'))
          expect(sent['resume_policy']).to(eq('sparse_checksum'))
          start_spec = simulator.transfer(id)['start_spec']
          expect(start_spec['remote_host']).to(eq('eudemo.asperademo.com'))
          expect(start_spec['remote_password']).not_to(eq('secret_value'))
        end

        it 'returns nil for an unknown transfer' do
          simulator = described_class.new(transfer_client: FakeTransferClient.new([]))
          expect(simulator.transfer('unknown')).to(be_nil)
          expect(simulator.transfers).to(eq([]))
        end

        it 'raises when transferd fails before the first event' do
          simulator = described_class.new(transfer_client: FakeTransferClient.new([], error: GRPC::Unavailable.new('down')))
          expect { simulator.start(transfer_spec) }.to(raise_error(GRPC::Unavailable))
        end

        it 'raises when transferd closes the stream without event' do
          simulator = described_class.new(transfer_client: FakeTransferClient.new([]))
          expect { simulator.start(transfer_spec) }.to(raise_error(Transfer::Error, /without event/))
        end

        it 'raises when the first event has no transfer id' do
          failed = transfer_response(:FAILED, :UNKNOWN_EVENT, transfer_id: '', error: API::Error.new(code: 1, description: 'invalid transfer spec'))
          simulator = described_class.new(transfer_client: FakeTransferClient.new([failed]))
          expect { simulator.start(transfer_spec) }.to(raise_error(Transfer::Error, 'invalid transfer spec'))
        end

        it 'marks the transfer failed when the stream breaks' do
          client = FakeTransferClient.new([QUEUED_EVENT])
          def client.start_transfer_with_monitor(request, &block)
            super
            raise GRPC::Unavailable, 'daemon died'
          end
          simulator = described_class.new(transfer_client: client)
          id = simulator.start(transfer_spec)
          expect(wait_status(simulator, id, 'failed')['error_desc']).to(include('daemon died'))
        end
      end

      describe '#transfers filters' do
        # transfers in start order: completed upload, running upload, waiting download
        let(:simulator) do
          client = FakeTransferClient.new(
            [transfer_response(:COMPLETED, :SESSION_STOP, transfer_id: 'done_send')],
            [transfer_response(:RUNNING, :PROGRESS, transfer_id: 'run_send')],
            [transfer_response(:QUEUED, :CONNECTING, transfer_id: 'wait_receive')]
          )
          described_class.new(transfer_client: client).tap do |simulator|
            %w[send send receive].each { |direction| simulator.start({'direction' => direction}) }
          end
        end

        def ids(**filters)
          simulator.transfers(**filters).map { |transfer| transfer['id'] }
        end

        it 'returns all transfers, oldest first' do
          expect(ids).to(eq(%w[done_send run_send wait_receive]))
        end

        it 'filters active or terminated transfers' do
          expect(ids(active_only: true)).to(eq(%w[run_send wait_receive]))
          expect(ids(active_only: false)).to(eq(%w[done_send]))
        end

        it 'filters on direction' do
          expect(ids(direction: 'receive')).to(eq(%w[wait_receive]))
          expect(ids(direction: 'send', active_only: true)).to(eq(%w[run_send]))
        end

        it 'limits the number of transfers' do
          expect(ids(count: 2)).to(eq(%w[done_send run_send]))
        end
      end

      describe '#cancel and #modify' do
        def started(client)
          described_class.new(transfer_client: client).tap { |simulator| simulator.start({'direction' => 'send'}) }
        end

        it 'stops the transfer' do
          client = FakeTransferClient.new([RUNNING_EVENT])
          expect(started(client).cancel(TRANSFER_ID)).to(be(true))
          expect(client.stop_requests.map { |request| request.transferId.to_a }).to(eq([[TRANSFER_ID]]))
        end

        it 'raises when transferd does not stop the transfer' do
          refused = API::StopTransferResponse.new(stopResult: [API::StopInfo.new(transferId: TRANSFER_ID, stopped: false, error: API::Error.new(description: 'already ended'))])
          simulator = started(FakeTransferClient.new([RUNNING_EVENT], stop_response: refused))
          expect { simulator.cancel(TRANSFER_ID) }.to(raise_error(Transfer::Error, 'already ended'))
        end

        it 'modifies the transfer spec' do
          client = FakeTransferClient.new([RUNNING_EVENT])
          expect(started(client).modify(TRANSFER_ID, {'target_rate_kbps' => 1000})).to(be(true))
          request = client.modify_requests.first
          expect(request.transferId).to(eq(TRANSFER_ID))
          expect(JSON.parse(request.transferSpec)).to(eq('target_rate_kbps' => 1000))
        end

        it 'raises when transferd refuses the modification' do
          refused = API::TransferModificationResponse.new(transferId: TRANSFER_ID, status: :FAILED, error: API::Error.new(description: 'invalid rate policy'))
          simulator = started(FakeTransferClient.new([RUNNING_EVENT], modify_response: refused))
          expect { simulator.modify(TRANSFER_ID, {'rate_policy' => 'bad'}) }.to(raise_error(Transfer::Error, 'invalid rate policy'))
        end

        it 'does not call transferd for an unknown transfer' do
          client = FakeTransferClient.new([RUNNING_EVENT])
          simulator = started(client)
          expect(simulator.cancel('unknown')).to(be(false))
          expect(simulator.modify('unknown', {'target_rate_kbps' => 1000})).to(be(false))
          expect(client.stop_requests + client.modify_requests).to(be_empty)
        end
      end
    end

    RSpec.describe(NodeSimulatorServlet) do
      let(:browse_root) { File.realpath(Dir.mktmpdir('node_simulator_spec')) }
      let(:basic_sim) { "Basic #{['sim:sim'].pack('m0')}" }
      let(:fake_simulator) { FakeSimulator.new }

      after do
        @server&.shutdown
        FileUtils.rm_rf(browse_root)
      end

      # Start a server on a free port
      def start_server(config = {}, simulator: fake_simulator)
        @server = WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: 0, Logger: WEBrick::Log.new([]), AccessLog: [])
        @server.mount('/', described_class, {browse_root: browse_root}.merge(config), simulator)
        Thread.new { @server.start }
      end

      # @return [Array] HTTP code, header `WWW-Authenticate`, parsed body (`nil` if none)
      def call(verb, path, body: nil, headers: {})
        request = Net::HTTPGenericRequest.new(verb, !body.nil?, true, path, headers)
        request.body = body
        response = Net::HTTP.new('127.0.0.1', @server.config[:Port]).request(request)
        [response.code.to_i, response['WWW-Authenticate'], response.body.to_s.empty? ? nil : JSON.parse(response.body)]
      end

      def expect_error(result, code, message = nil)
        expect(result[0]).to(eq(code))
        expect(result[2]['error']).to(include('code' => code, 'reason' => WEBrick::HTTPStatus.reason_phrase(code)))
        expect(result[2]['error']['user_message']).to(match(message)) unless message.nil?
      end

      context 'with credentials' do
        before { start_server({username: 'sim', password: 'sim'}) }

        it 'rejects a request without credentials' do
          result = call('GET', '/ops/transfers')
          expect_error(result, 401)
          expect(result[1]).to(eq('Basic realm="Aspera Node Simulator"'))
        end

        it 'rejects a wrong password' do
          expect_error(call('GET', '/ops/transfers', headers: {'Authorization' => "Basic #{['sim:bad'].pack('m0')}"}), 401)
        end

        it 'rejects a bearer token' do
          expect_error(call('GET', '/ops/transfers', headers: {'Authorization' => 'Bearer abcdef', 'X-Aspera-AccessKey' => 'ak'}), 401)
        end

        it 'accepts the expected credentials' do
          code, _, body = call('GET', '/ops/transfers', headers: {'Authorization' => basic_sim})
          expect(code).to(eq(200))
          expect(body.map { |transfer| transfer['id'] }).to(eq([TRANSFER_ID]))
        end
      end

      context 'without credentials' do
        before { start_server }

        it 'accepts a request without credentials' do
          code, _, body = call('GET', "/ops/transfers/#{TRANSFER_ID}")
          expect(code).to(eq(200))
          expect(body['status']).to(eq('running'))
        end

        it 'starts a transfer' do
          code, _, body = call('POST', '/ops/transfers', body: '{"direction":"send"}')
          expect(code).to(eq(200))
          expect(body['id']).to(eq(TRANSFER_ID))
        end

        it 'returns 404 for an unknown path' do
          expect_error(call('GET', '/unknown'), 404, %r{/unknown})
          expect_error(call('POST', '/unknown', body: '{}'), 404)
        end

        it 'returns 404 for an unknown transfer' do
          expect_error(call('GET', '/ops/transfers/unknown'), 404, 'Unknown transfer')
        end

        it 'returns 400 for invalid JSON' do
          expect_error(call('POST', '/ops/transfers', body: 'not json'), 400)
        end

        it 'returns 405 for an unsupported verb' do
          expect_error(call('DELETE', '/ops/transfers'), 405)
        end

        it 'passes list filters to the backend' do
          code, _, body = call('GET', '/ops/transfers?active_only=true&direction=send&count=5')
          expect(code).to(eq(200))
          expect(body.length).to(eq(1))
          call('GET', '/ops/transfers?active_only=false')
          call('GET', '/ops/transfers')
          expect(fake_simulator.calls).to(eq([
            [:transfers, {active_only: true, direction: 'send', count: 5}],
            [:transfers, {active_only: false, direction: nil, count: nil}],
            [:transfers, {active_only: nil, direction: nil, count: nil}]
          ]))
        end

        it 'returns 400 for invalid list filters' do
          expect_error(call('GET', '/ops/transfers?active_only=yes'), 400, /active_only/)
          expect_error(call('GET', '/ops/transfers?count=0'), 400, /count/)
          expect_error(call('GET', '/ops/transfers?count=abc'), 400, /count/)
        end

        it 'cancels a transfer' do
          code, _, body = call('CANCEL', "/ops/transfers/#{TRANSFER_ID}")
          expect(code).to(eq(204))
          expect(body).to(be_nil)
          expect(fake_simulator.calls).to(eq([[:cancel, TRANSFER_ID]]))
        end

        it 'returns 404 when canceling an unknown transfer or path' do
          expect_error(call('CANCEL', '/ops/transfers/unknown'), 404, 'Unknown transfer')
          expect_error(call('CANCEL', '/ops/transfers'), 404, /Unknown path/)
        end

        it 'modifies a transfer' do
          code, _, body = call('PUT', "/ops/transfers/#{TRANSFER_ID}", body: '{"target_rate_kbps":1000,"rate_policy":"fair"}')
          expect(code).to(eq(200))
          expect(body['id']).to(eq(TRANSFER_ID))
          expect(fake_simulator.calls).to(eq([[:modify, TRANSFER_ID, {'target_rate_kbps' => 1000, 'rate_policy' => 'fair'}]]))
        end

        it 'cancels a transfer with status' do
          code, _, body = call('PUT', "/ops/transfers/#{TRANSFER_ID}", body: '{"status":"cancelled"}')
          expect(code).to(eq(200))
          expect(body['id']).to(eq(TRANSFER_ID))
          expect(fake_simulator.calls).to(eq([[:cancel, TRANSFER_ID]]))
        end

        it 'returns 400 for unsupported modifications' do
          expect_error(call('PUT', "/ops/transfers/#{TRANSFER_ID}", body: '{"status":"paused"}'), 400, /paused/)
          expect_error(call('PUT', "/ops/transfers/#{TRANSFER_ID}", body: '{"cipher":"none"}'), 400, /cipher/)
          expect_error(call('PUT', "/ops/transfers/#{TRANSFER_ID}", body: '{}'), 400, /Nothing/)
          expect_error(call('PUT', "/ops/transfers/#{TRANSFER_ID}", body: '[]'), 400, /object/)
          expect(fake_simulator.calls).to(be_empty)
        end

        it 'returns 404 when modifying an unknown transfer' do
          expect_error(call('PUT', '/ops/transfers/unknown', body: '{"target_rate_kbps":1000}'), 404, 'Unknown transfer')
        end

        it 'confines browse to the root' do
          expect_error(call('POST', '/files/browse', body: '{"path":"/"}'), 400, /traversal/)
          expect_error(call('POST', '/files/browse', body: '{"path":"/nonexistent_folder_xyz"}'), 404)
          code, _, body = call('POST', '/files/browse', body: {path: browse_root}.to_json)
          expect(code).to(eq(200))
          expect(body['self']['path']).to(eq(browse_root))
        end

        it 'pages browse results' do
          %w[c a d b].each { |name| File.write(File.join(browse_root, name), name) }
          code, _, body = call('POST', '/files/browse', body: {path: browse_root, skip: 1, count: 2}.to_json)
          expect(code).to(eq(200))
          expect(body['items'].map { |item| item['basename'] }).to(eq(%w[b c]))
          expect(body).to(include('item_count' => 2, 'total_count' => 4))
        end
      end

      it 'returns 400 when the transfer is refused' do
        start_server(simulator: FakeSimulator.new(start_error: Transfer::Error.new('invalid transfer spec')))
        expect_error(call('POST', '/ops/transfers', body: '{}'), 400, 'invalid transfer spec')
      end

      it 'returns 500 when transferd fails' do
        start_server(simulator: FakeSimulator.new(start_error: GRPC::Unavailable.new('daemon down')))
        expect_error(call('POST', '/ops/transfers', body: '{}'), 500, /daemon down/)
      end
    end
  end
end
