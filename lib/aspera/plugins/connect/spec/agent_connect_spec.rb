# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Connect::Agent — Connect local REST API is doubled, no Connect application needed.

require_relative '../agent'
require_relative '../../../transfer/error'
require_relative '../../../transfer/spec'
require 'tmpdir'

RSpec.describe(Aspera::Plugins::Connect::Agent) do
  let(:rest) { instance_double(Aspera::Rest::Client) }
  let(:events) { [] }
  # Successive values of `transfer_info`
  let(:infos) { [] }

  before do
    allow(Aspera::Rest::Client).to(receive(:new).and_return(rest))
    allow(Aspera::Log.log).to(receive(:warn))
    allow(rest).to(receive(:create)) do |path, _body|
      case path
      when 'windows/select-open-file-dialog/' then {'dataTransfer' => {'files' => [{'name' => '/a'}, {'name' => '/b'}]}}
      when 'transfers/start' then {'transfer_specs' => [{'transfer_spec' => {'tags' => {'aspera' => {'xfer_id' => 'x1'}}}}]}
      when %r{\Atransfers/info/} then {'transfer_info' => infos.length > 1 ? infos.shift : infos.first}
      end
    end
  end

  describe '.connect_api_url' do
    it 'reads the URL from the URI file in the run folder' do
      Dir.mktmpdir do |dir|
        allow(Aspera::Products).to(receive(:find).and_return([{run_root: dir}]))
        expect { described_class.connect_api_url }.to(raise_error(/no connect uri file found/))
        FileUtils.mkdir_p(File.join(dir, 'var', 'run'))
        File.write(File.join(dir, 'var', 'run', 'https.uri'), "https://127.0.0.1:43003\n")
        expect(described_class.connect_api_url).to(eq('https://127.0.0.1:43003'))
      end
    end
  end

  describe '.transfer_status' do
    before { allow(described_class).to(receive(:connect_api_url).and_return('http://127.0.0.1:33003')) }

    def status(info)
      infos.replace([info])
      described_class.transfer_status('x1', {'app_id' => 'a1'})
    end

    it 'normalizes the status of Connect' do
      expect(status(nil)).to(eq({'status' => 'running', 'bytes_transferred' => 0}))
      expect(status({'status' => 'running', 'bytes_written' => 10})).to(eq({'status' => 'running', 'bytes_transferred' => 10}))
    end

    it 'adds the end time to final states' do
      expect(status({'status' => 'completed', 'bytes_written' => 20})).to(include('status' => 'completed', 'ended_at' => String))
      expect(status({'status' => 'failed', 'error_desc' => 'disk full'})).to(include('status' => 'failed', 'error' => 'disk full', 'ended_at' => String))
      expect(status({'status' => 'cancelled'})).to(include('status' => 'cancelled', 'ended_at' => String))
    end
  end

  context 'with an instance' do
    let(:agent) do
      progress = Object.new
      recorded = events
      progress.define_singleton_method(:event) { |*args, **kwargs| recorded.push([args.first, kwargs[:info]]) }
      described_class.new(progress: progress)
    end

    before do
      stub_const('Aspera::Plugins::Connect::Agent::SLEEP_SEC_BETWEEN_RETRY', 0)
      allow(Aspera::Environment.instance).to(receive_messages(graphical?: true, open_uri_graphical: nil))
      allow(described_class).to(receive(:connect_api_url).and_return('http://127.0.0.1:33003'))
      allow(rest).to(receive(:read).with('info/version').and_return({'version' => '4.2'}))
    end

    describe '#initialize' do
      it 'starts Connect if not reachable, then retries' do
        calls = 0
        allow(described_class).to(receive(:connect_api_url)) do
          calls += 1
          raise Errno::ECONNREFUSED if calls < 3
          'http://127.0.0.1:33003'
        end
        expect(agent.app_id).to(match(/\A[0-9a-f-]{36}\z/))
        expect(Aspera::Environment.instance).to(have_received(:open_uri_graphical).with('fasp://initialize').twice)
      end

      it 'fails after all start methods' do
        allow(described_class).to(receive(:connect_api_url).and_raise(Errno::ECONNREFUSED))
        expect { agent }.to(raise_error(/Unable to start connect 5 times/))
        expect(Aspera::Environment.instance).to(have_received(:open_uri_graphical).exactly(4).times)
      end
    end

    describe '#start_transfer' do
      it 'selects files to upload in the GUI' do
        tspec = {'direction' => 'send', 'paths' => [{'source' => 'ignored'}], 'token' => '<TOKEN>'}
        expect(agent.start_transfer(tspec)).to(eq('x1'))
        expect(tspec).to(include('paths' => [{'source' => '/a'}, {'source' => '/b'}], 'authentication' => 'token'))
      end
    end

    describe '#wait_for_transfers_completion' do
      before do
        allow(agent).to(receive(:sleep))
        agent.start_transfer({'direction' => 'receive'})
      end

      def wait(*statuses)
        infos.concat(statuses)
        agent.wait_for_transfers_completion
      end

      it 'notifies progress until completion' do
        result = wait(
          {'status' => 'queued'},
          {'status' => 'running', 'bytes_expected' => 0, 'bytes_written' => 0},
          {'status' => 'running', 'bytes_expected' => 100, 'bytes_written' => 10},
          {'status' => 'running', 'bytes_expected' => 100, 'bytes_written' => 50},
          {'status' => 'completed'}
        )
        expect(result).to(eq([:success]))
        expect(events).to(eq([
          [:sessions_init, 'queued'],
          [:session_start, nil],
          [:transfer, 0],
          [:session_size, 100],
          [:transfer, 50],
          [:session_end, nil]
        ]))
      end

      it 'returns the error of a failed, cancelled or unknown transfer' do
        expect(wait({'status' => 'failed', 'error_desc' => 'disk full'}).first.message).to(eq('disk full'))
        infos.clear
        expect(wait({'status' => 'cancelled'}).first.message).to(eq('Transfer cancelled by user'))
        infos.clear
        error = wait({'status' => 'weird', 'error_desc' => 'what'}).first
        expect(error).to(be_a(Aspera::Transfer::Error))
        expect(error.message).to(eq('unknown status: weird: what'))
      end
    end
  end
end
