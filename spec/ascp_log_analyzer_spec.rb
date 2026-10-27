# frozen_string_literal: true

# cspell:ignore blks drate dups rcvd rexreqs sndr userid xmit
# Unit tests for Aspera::Ascp::LogAnalyzer: analysis of `ascp` log files.

require 'bundler/setup'
require 'tmpdir'
require 'aspera/ascp/log_analyzer'

RSpec.describe(Aspera::Ascp::LogAnalyzer) do
  # Log file of `ascp` 4 (option `-L`): a receiver session (server side, success) and a sender session (client side, failed)
  # @param extra [Array<Symbol>] additional sessions:
  #   `abrupt_end`: stops logging after an error, without `Session Stop`
  #   `multi_session`: two sessions of a multi-session transfer
  #   `retry`: new session after the failed sender session
  #   `same_process`: two sessions in the same process
  def ascp_log(version: '4.4.5.123', extra: [])
    lines = []
    line = ->(time, pid, text) { lines.push("2026-01-10 #{time}.000 [#{pid}-140001] #{text}") }
    start_fields = ->(uuid, op, status, local, peer, peerlic) do
      "uuid=#{uuid} op=#{op} status=#{status} source=/src dest=/dst source_prefix=- local=#{local} peer=#{peer} tcp_port=33001 " \
        "os=\"Linux 5.14\" ver=#{version} lic=10:1:1234 peeros=\"Darwin 24.0\" peerver=#{version} peerlic=#{peerlic} proto_sess=20003 proto_udp=20000 proto_bwmeas=20000 proto_data=2000d"
    end
    initializing = "LOG Initializing FASP version #{version}, license max rate=(unlimited), account no.=1, license no.=1234 product=10"
    rx = '11111111-2222-3333-4444-555555555555'
    tx = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    line.call('10:00:00', '1a2b', 'LOG Configuration: using v2 configuration file "/opt/aspera/etc/aspera.conf", user xfer')
    line.call('10:00:00', '1a2b', initializing)
    line.call('10:00:00', '1a2b', 'LOG server configuration specifies transit encryption cipher 9, user requests 1')
    line.call('10:00:00', '1a2b', "LOG FASP Session Start #{start_fields.call(rx, 'recv', 'started', '10.0.0.1:33001', '10.0.0.2:51000', '6:1:1')}")
    line.call('10:00:00', '1a2b', "LOG FASP Session Params uuid=#{rx} userid=0 user=\"xfer\" targetrate=100000000 minrate=0 rate_policy=fair cipher=aes-256-gcm " \
      'resume=2 create=0 extra_create=0 ovr=1 times=0 precalc=yes precalc_disable=false mf=0 mf_path=- rd_sz=0 wr_sz=0 net_rc_alg=alg_delay xfer_id=-')
    line.call('10:00:00', '1a2b', 'LOG Downgrading resume policy to RESUME_POLICY_ATTRS')
    line.call('10:00:00', '1a2b', 'LOG datagram size 1448B, block size 1408B, path MTU 1492B')
    line.call('10:00:00', '2c3d', 'LOG Configuration: using v2 configuration file "/opt/aspera/etc/aspera.conf", user -')
    line.call('10:00:00', '2c3d', initializing)
    line.call('10:00:00', '2c3d', "LOG FASP Session Start #{start_fields.call(tx, 'send', 'started', '10.0.0.1:52000', '10.0.0.3:33001', '10:1:5678')}")
    line.call('10:00:05', '1a2b', 'LOG Peer requested rate params adopted,  target_rate 50000000 min_rate 0 transfer_policy fair')
    (0..4).each do |i|
      time = format('10:%02d:%02d', (1 + (20 * i)) / 60, (1 + (20 * i)) % 60)
      elapsed_us = (1 + (20 * i)) * 1_000_000
      bytes = 5_000_000 * i
      blocks = bytes / 1408
      line.call(time, '1a2b', "LOG Receiver bl t/o/r/d/ts/c/h=#{blocks}/#{blocks}/0/0/0/0/0 rex_rtt l/h/s/o=0/60/50/8 ooo_rtt l/h/s/o=0/0/23/8 " \
        "rate_rtt b/l/h/s/r/f=45/40/60/50/0/2 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=#{10 * i}/0/0/0/0/0/0/0/0/0 " \
        'disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=50000000/0/40000000/40000000/50000000/50000000/50000000 ' \
        "prog t/f/e=#{bytes}/#{bytes}/#{elapsed_us} rcvD=0")
      next if i > 2
      # Calculated rate limited by the network rate of the receiver, slow read from disk
      line.call(time, '2c3d', "LOG Sender bl t/o/r/dl/c/h=#{blocks}/#{blocks}/0/0/0/0 ctl bm/bs=0/0 rex b/r/n=0/0/0 r_ott q/s/n=0/0/0 " \
        'rate t/m/c/rc/n/vl/vr/r=20000000/0/15000000/15000000/15000000/20000000/20000000/20000000 ' \
        "prog t/f/e=#{bytes}/#{bytes}/#{elapsed_us} xmtD=0 drate=10000000")
    end
    line.call('10:00:45', '2c3d', "LOG FASP Session Stop #{start_fields.call(tx, 'send', 'failed errcode=36 errstr="Session data transfer timeout"', '10.0.0.1:52000', '10.0.0.3:33001', '10:1:5678')}")
    if extra.include?(:abrupt_end)
      line.call('10:00:00', '3e4f', 'ERR Unrelated error at start')
      line.call('10:00:00', '3e4f', initializing)
      line.call('10:00:00', '3e4f', "LOG FASP Session Start #{start_fields.call('33333333-4444-5555-6666-777777777777', 'send', 'started', '10.0.0.1:52001', '10.0.0.4:33001', '10:1:5678')}")
      line.call('10:00:10', '3e4f', 'ERR Cannot read from management socket localhost:12345, Connection reset by peer (client)')
    end
    if extra.include?(:multi_session)
      %w[7a01 7a02].each_with_index do |pid, node|
        uuid = "77777777-0000-0000-0000-00000000000#{node}"
        line.call('10:00:50', pid, initializing)
        line.call('10:00:50', pid, "LOG FASP Session Start #{start_fields.call(uuid, 'send', 'started', "10.0.0.1:5300#{node}", '10.0.0.5:33001', '10:1:5678')}")
        line.call('10:00:50', pid, "LOG FASP Session Params uuid=#{uuid} userid=0 user=\"xfer\" targetrate=100000000 minrate=0 rate_policy=fair cipher=aes-128 " \
          "resume=0 ovr=1 rd_sz=0 wr_sz=0 cluster_num_nodes=2 cluster_node_id=#{node} xfer_id=99999999-8888-7777-6666-555555555555")
        line.call('10:00:55', pid, "LOG FASP Session Stop #{start_fields.call(uuid, 'send', 'success', "10.0.0.1:5300#{node}", '10.0.0.5:33001', '10:1:5678')}")
        line.call('10:00:55', pid, 'LOG ======= end File Transfer statistics =======')
      end
    end
    if extra.include?(:retry)
      retry_uuid = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
      line.call('10:01:00', '8b01', initializing)
      line.call('10:01:00', '8b01', "LOG FASP Session Start #{start_fields.call(retry_uuid, 'send', 'started', '10.0.0.1:52002', '10.0.0.3:33001', '10:1:5678')}")
      line.call('10:01:10', '8b01', "LOG FASP Session Stop #{start_fields.call(retry_uuid, 'send', 'success', '10.0.0.1:52002', '10.0.0.3:33001', '10:1:5678')}")
      line.call('10:01:10', '8b01', 'LOG ======= end File Transfer statistics =======')
    end
    if extra.include?(:same_process)
      %w[dddddddd-0000-0000-0000-000000000001 dddddddd-0000-0000-0000-000000000002].each_with_index do |uuid, index|
        time = "10:00:#{20 + (index * 10)}"
        line.call(time, 'd4e5', initializing) if index.zero?
        line.call(time, 'd4e5', "LOG FASP Session Start #{start_fields.call(uuid, 'send', 'started', '10.0.0.1:52003', '10.0.0.6:33001', '10:1:5678')}")
        line.call(time, 'd4e5', "LOG FASP Session Stop #{start_fields.call(uuid, 'send', 'failed errcode=89 errstr="SSH authentication failed"', '10.0.0.1:52003', '10.0.0.6:33001', '10:1:5678')}")
        line.call(time, 'd4e5', 'LOG ======= end File Transfer statistics =======')
      end
    end
    line.call('10:00:45', '2c3d', 'ERR [asssh] channel eof wait rc=-9')
    line.call('10:00:45', '2c3d', 'ERR [asssh] channel wait close rc=-34')
    line.call('10:00:45', '2c3d', 'LOG ======= end File Transfer statistics =======')
    line.call('10:01:30', '1a2b', "LOG FASP Transfer Stop uuid=#{rx} op=recv status=success file=\"/dst/file1\" size=20000000 start_byte=0 rate=1.78Mbps loss=0.00 rexreqs=0 overhead=0")
    line.call('10:01:30', '1a2b', "LOG FASP Session Stop #{start_fields.call(rx, 'recv', 'success', '10.0.0.1:33001', '10.0.0.2:51000', '6:1:1')}")
    # 85% efficiency, 10% loss of control messages from receiver, loss of retransmission requests below the minimum number
    line.call('10:01:30', '1a2b', "LOG FASP Session Statistics [Receiver] id=#{rx} delay=50ms rex_delay=60ms ooo_delay=8ms solicited_rex=15.00% rcvd_rex=0.00% rcvd_dups=0.00% " \
      'ave_xmit_rate 1.80Mbps effective=85.00% effective_rate=1.78Mbps (detail: good_blks 14204 bl_total 14204 bl_orig 14204 bl_rex 0 dup_blks 0 ' \
      'dup_last_blks 0 drop_blks_xnf 0) (sndr ctl: sent 100 rcvd 100 lost 0 lost 0.00%) (rcvr ctl: sent 200 rcvd 180 lost 20 lost 10.00%) ' \
      '(rex  ctl: sent 5 rcvd 4 lost 1 lost 20.00%) (progress: tx_bytes 20000000 file_bytes 20000000 tx_time 90000000) rex_xmit_blks 0  xmit_total 14204 rex_xmit_pct 0.00%')
    line.call('10:01:31', '1a2b', 'LOG ======= end File Transfer statistics =======')
    "#{lines.join("\n")}\n"
  end

  # Log of the client side of the receiver session of `ascp_log`
  def client_log
    fields = 'uuid=11111111-2222-3333-4444-555555555555 op=send status=%s source=/src dest=/dst source_prefix=- local=10.0.0.2:51000 peer=10.0.0.1:33001 ' \
      'tcp_port=33001 os="Darwin 24.0" ver=4.4.5.123 lic=6:1:1 peeros="Linux 5.14" peerver=4.4.5.123 peerlic=10:1:1234'
    [
      '10:00:00 LOG Configuration: using v2 configuration file "/etc/aspera.conf", user -',
      '10:00:00 LOG Initializing FASP version 4.4.5.123, license max rate=(unlimited), account no.=1, license no.=1 product=6',
      "10:00:00 LOG FASP Session Start #{format(fields, 'started')}",
      "10:01:30 LOG FASP Session Stop #{format(fields, 'success')}",
      '10:01:30 LOG FASP Session Statistics [Sender] id=11111111-2222-3333-4444-555555555555 effective=100.00% effective_rate=1.78Mbps ' \
        '(progress: tx_bytes 20000000 file_bytes 20000000 tx_time 90000000)',
      '10:01:31 LOG ======= end File Transfer statistics ======='
    ].map { |text| "2026-01-10 #{text.sub(' ', '.000 [c1d2-140001] ')}\n" }.join
  end

  # @param client [Boolean] also analyze the log of the client side
  def analyze(version: '4.4.5.123', extra: [], client: false)
    Dir.mktmpdir do |dir|
      analyzer = described_class.new
      path = File.join(dir, 'aspera-scp-transfer.log')
      File.write(path, ascp_log(version: version, extra: extra))
      analyzer.add(path)
      if client
        path = File.join(dir, 'client.log')
        File.write(path, client_log)
        analyzer.add(path)
      end
      yield(analyzer)
    end
  end

  def session_of(analyzer, pid)
    analyzer.sessions.find { |s| s['pid'] == pid }
  end

  it 'summarizes sessions of an ascp 4 log' do
    analyze do |analyzer|
      summary = analyzer.summary
      expect(summary.slice('files', 'sessions', 'success', 'failed')).to(eq('files' => 1, 'sessions' => 2, 'success' => 1, 'failed' => 1))
      expect(summary['errors']).to(eq('Session data transfer timeout' => 1))
      expect(summary['error_categories']).to(eq('network' => 1))
      expect(summary['warnings']).to(be_empty)
    end
  end

  it 'reports receiver session from session lines, params and samples' do
    analyze do |analyzer|
      session = session_of(analyzer, '1a2b')
      expect(session).to(include(
        'user' => 'xfer', 'role' => 'server', 'status' => 'success', 'version' => '4.4.5.123', 'peer' => '10.0.0.2',
        'encryption' => 'aes-256-gcm', 'resume' => 'With sparse checksum', 'mtu' => 1448, 'payload' => 1408,
        'target_rate' => 50_000_000, 'average_rate' => 1_780_000, 'transmitted_bytes' => 20_000_000, 'files' => 1, 'constraints' => ['network']
      ))
      expect(session['diagnostics']).to(include('Parameter change by peer: Target rate changed from 100,000,000 bps to 50,000,000 bps.'))
    end
  end

  it 'reports quality metrics and parameters set by the server' do
    analyze do |analyzer|
      session = session_of(analyzer, '1a2b')
      expect(session).to(include('efficiency' => 85.0, 'retransmitted_rate' => 15.0, 'duplicate_rate' => 0.0))
      expect(session['diagnostics']).to(include(
        'Only 85.0% of the data blocks sent were useful: retransmissions reduce the effective rate.',
        '10.0% of control messages from receiver to sender were lost.',
        'Encryption cipher set by server configuration: aes-256-gcm (requested: aes-128).',
        'Resume policy lowered to file attributes: checksum-based resume is not supported by the storage.'
      ))
      expect(session['diagnostics'].grep(/requesting retransmission/)).to(be_empty)
    end
  end

  it 'reads ascp 4 sender samples, and attributes the rate limit' do
    analyze do |analyzer|
      session = session_of(analyzer, '2c3d')
      expect(session).to(include(
        'role' => 'client', 'status' => 'failed', 'error' => 'Session data transfer timeout', 'transmitted_bytes' => 10_000_000,
        'target_rate' => 20_000_000, 'disk_read_rate' => 10_000_000, 'constraints' => ['Receiver']
      ))
      expect(session['max_rate']).to(be_positive)
      expect(session.dig('constraint', 'Receiver', 'causes')).to(eq('network' => 2))
      expect(session['diagnostics']).to(include(
        'Rate limited by the receiver: network (100% of samples).',
        'Reading from storage (10,000,000 bps) is slower than the calculated rate (15,000,000 bps): sender storage limits the transfer.',
        'The SSH connection to the server was not closed properly: [asssh] channel eof wait rc=-9 (timeout: no answer from server)'
      ))
    end
  end

  it 'categorizes errors of ascp 4' do
    analyze do |analyzer|
      session = session_of(analyzer, '2c3d')
      expect(session).to(include('error_code' => 36, 'error_category' => 'network', 'error_retry' => true))
      expect(session['diagnostics']).to(include(Aspera::Ascp::SessionErrors.hint('network')))
    end
  end

  it 'lists diagnostics with identifier and severity' do
    analyze do |analyzer|
      expect(analyzer.diagnostics).to(include(
        include('pid' => '2c3d', 'id' => 'error_network', 'severity' => 'error'),
        include('pid' => '2c3d', 'id' => 'slow_storage_read', 'severity' => 'warning'),
        include('pid' => '1a2b', 'id' => 'cipher_set_by_server', 'severity' => 'info')
      ))
      expect(analyzer.summary['diagnostics']).to(include('error' => be_positive, 'warning' => be_positive, 'info' => be_positive))
    end
  end

  it 'separates sessions of the same process' do
    analyze(extra: %i[same_process]) do |analyzer|
      sessions = analyzer.sessions.select { |s| s['pid'] == 'd4e5' }
      expect(sessions.map { |s| s['session'] }).to(eq(%w[dddddddd-0000-0000-0000-000000000001 dddddddd-0000-0000-0000-000000000002]))
      expect(sessions.map { |s| s['error_category'] }).to(all(eq('authentication')))
    end
  end

  it 'joins the client and server sides of a session' do
    analyze(client: true) do |analyzer|
      server = session_of(analyzer, '1a2b')
      client = session_of(analyzer, 'c1d2')
      expect(server['peer_side']).to(include('pid' => 'c1d2', 'role' => 'client', 'status' => 'success'))
      expect(client['peer_side']).to(include('pid' => '1a2b', 'role' => 'server', 'status' => 'success'))
      expect(client['peer_diagnostics']).to(include('Encryption cipher set by server configuration: aes-256-gcm (requested: aes-128).'))
    end
  end

  it 'lists transferred files and snapshots' do
    analyze do |analyzer|
      expect(analyzer.transfers).to(contain_exactly(include('path' => '/dst/file1', 'size' => 20_000_000, 'status' => 'success')))
      expect(analyzer.snapshots).not_to(be_empty)
      expect(analyzer.snapshots.map { |s| s['rate'] }).to(all(be >= 0))
    end
  end

  it 'shows last error of a session that stopped logging' do
    analyze(extra: %i[abrupt_end]) do |analyzer|
      session = session_of(analyzer, '3e4f')
      expect(session).to(include('status' => 'failed', 'error' => 'ascp exited, or was in IOwait or stopped logging'))
      expect(session['diagnostics']).to(include(
        'Last error before ascp stopped logging: Cannot read from management socket localhost:12345, Connection reset by peer (client)'
      ))
      expect(analyzer.sessions.flat_map { |s| s['diagnostics'] }.grep(/Last error/).size).to(eq(1))
    end
  end

  it 'groups sessions of a multi-session transfer' do
    analyze(extra: %i[multi_session]) do |analyzer|
      expect(analyzer.multi_sessions).to(contain_exactly(include(
        'transfer_id' => '99999999-8888-7777-6666-555555555555', 'nodes' => 2, 'pids' => %w[7a01 7a02], 'peer' => '10.0.0.5', 'direction' => 'send', 'status' => 'success'
      )))
      expect(analyzer.summary['multi_session']).to(eq(1))
    end
  end

  it 'links a failed session to its retry' do
    analyze(extra: %i[retry]) do |analyzer|
      session = session_of(analyzer, '2c3d')
      expect(session).to(include('retried_by' => '8b01'))
      expect(session['diagnostics']).to(include('Retried by session 8b01.'))
      expect(analyzer.summary['retries']).to(eq(1))
    end
  end

  it 'warns about ascp older than 4.0, and does not categorize its errors' do
    analyze(version: '3.9.6.1234') do |analyzer|
      expect(analyzer.warnings).to(contain_exactly(/ascp 3\.9\.6\.1234 is older than 4\.0/))
      expect(analyzer.sessions.first['diagnostics']).to(include(/older than 4\.0/))
      expect(session_of(analyzer, '2c3d')).not_to(have_key('error_category'))
    end
  end
end
