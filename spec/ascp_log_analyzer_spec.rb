# frozen_string_literal: true

# cspell:ignore blks drate dups filewrite httpgateway lport rcvd rexreqs sndr userid xmit
# Unit tests for Aspera::Ascp::LogAnalyzer: analysis of `ascp` log files.

require 'bundler/setup'
require 'tmpdir'
require 'zlib'
require 'stringio'
require 'aspera/ascp/log_analyzer'

RSpec.describe(Aspera::Ascp::LogAnalyzer) do
  # Log file of `ascp` 4 (option `-L`): a receiver session (server side, success) and a sender session (client side, failed)
  # @param extra [Array<Symbol>] additional sessions:
  #   `abrupt_end`: stops logging after an error, without `Session Stop`
  #   `multi_session`: two sessions of a multi-session transfer
  #   `retry`: new session after the failed sender session
  #   `same_process`: two sessions in the same process
  #   `token_expired`, `out_of_disk`, `content_protection`, `bind_udp_socket_failed`, `sharing_violation`,
  #   `filename_too_long`, `configuration_error`, `reverse_path_skew`, `clock_problem`, `peer_clock_problem`
  # @param rates [Array<Integer>, nil] network rates (bps) of the samples of an additional receiver session (process `9a01`), one every 20 seconds
  # @param peer_params [Boolean] the peer changes the rate parameters of the additional session
  def ascp_log(version: '4.4.5.123', extra: [], rates: nil, peer_params: false)
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
    extra_synthetic_sessions(extra, start_fields, initializing, line)
    if rates
      declining = 'eeeeeeee-0000-0000-0000-000000000001'
      line.call('10:10:00', '9a01', initializing)
      line.call('10:10:00', '9a01', "LOG FASP Session Start #{start_fields.call(declining, 'recv', 'started', '10.0.0.1:33001', '10.0.0.7:51001', '6:1:1')}")
      line.call('10:10:00', '9a01', 'LOG Peer requested rate params adopted,  target_rate 50000000 min_rate 0 transfer_policy fair') if peer_params
      rates.each_with_index do |rate, i|
        seconds = 21 + (20 * i)
        bytes = 1_000_000 * (i + 1)
        line.call(format('10:%02d:%02d', (600 + seconds) / 60, seconds % 60), '9a01', "LOG Receiver bl t/o/r/d/ts/c/h=#{bytes / 1408}/#{bytes / 1408}/0/0/0/0/0 " \
          'rex_rtt l/h/s/o=0/60/50/8 ooo_rtt l/h/s/o=0/0/23/8 rate_rtt b/l/h/s/r/f=45/40/60/50/0/2 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 ' \
          'bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 ' \
          "rate t/m/c/n/vl/vr/r=100000000/0/#{rate}/#{rate}/100000000/100000000/100000000 prog t/f/e=#{bytes}/#{bytes}/#{seconds * 1_000_000} rcvD=0")
      end
      stop = 621 + (20 * rates.size)
      line.call(format('10:%02d:%02d', stop / 60, stop % 60), '9a01', "LOG FASP Session Stop #{start_fields.call(declining, 'recv', 'success', '10.0.0.1:33001', '10.0.0.7:51001', '6:1:1')}")
    end
    "#{lines.join("\n")}\n"
  end

  def extra_synthetic_sessions(extra, start_fields, initializing, line)
    {
      token_expired:          ['9b01', 'send', '52004', '10.0.0.3:33001', '10:1:5678', 'ERR Token expired 120 seconds ago', 12, 'Token expired'],
      out_of_disk:            ['9b02', 'recv', '33001', '10.0.0.2:51002', '6:1:1', 'ERR fc_filewrite_sz: Could not write cache bytes 0-1407, off=0, fh=3, errno=28', 15, 'Disk full'],
      content_protection:     ['9b03', 'recv', '33001', '10.0.0.2:51003', '6:1:1', 'ERR Server requires content protection', 18, 'Content protection required'],
      bind_udp_socket_failed: ['9b04', 'send', '52005', '10.0.0.3:33001', '10:1:5678', 'ERR bind udp socket failed, error=48', 19, 'Bind failed'],
      sharing_violation:      ['9b05', 'recv', '33001', '10.0.0.2:51005', '6:1:1', 'ERR Could not open C:/dst/file1, errno 32 errstr The process cannot access the file because it is being used by another process.', 32, 'Sharing violation'],
      configuration_error:    ['9b07', 'send', '52007', '10.0.0.3:33001', '10:1:5678', 'ERR aspera.conf parsing error: root element is not <CONF>', 1, 'Conf error']
    }.each do |key, (pid, op, lport, peer, peerlic, err, code, msg)|
      next unless extra.include?(key)
      uuid = "eeeeeeee-#{pid}-0000-0000-000000000000"
      local = "10.0.0.1:#{lport}"
      line.call('10:02:00', pid, initializing)
      line.call('10:02:00', pid, "LOG FASP Session Start #{start_fields.call(uuid, op, 'started', local, peer, peerlic)}")
      line.call('10:02:01', pid, err)
      line.call('10:02:01', pid, "LOG FASP Session Stop #{start_fields.call(uuid, op, %Q(failed errcode=#{code} errstr="#{msg}"), local, peer, peerlic)}")
      line.call('10:02:01', pid, 'LOG ======= end File Transfer statistics =======')
    end
    extra_synthetic_complex_sessions(extra, start_fields, initializing, line)
  end

  def extra_synthetic_complex_sessions(extra, start_fields, initializing, line)
    if extra.include?(:filename_too_long)
      uuid = 'eeeeeeee-6666-0000-0000-000000000006'
      long_name = "C:/dst/#{'a' * 250}.txt"
      line.call('10:07:00', '9b06', initializing)
      start_line = start_fields.call(uuid, 'recv', 'started', '10.0.0.1:33001', '10.0.0.2:51006', '6:1:1').sub('Linux 5.14', 'Windows 10')
      stop_line = start_fields.call(uuid, 'recv', 'failed errcode=78 errstr="Filename too long"', '10.0.0.1:33001', '10.0.0.2:51006', '6:1:1').sub('Linux 5.14', 'Windows 10')
      line.call('10:07:00', '9b06', "LOG FASP Session Start #{start_line}")
      line.call('10:07:01', '9b06', "LOG FASP Transfer Stop uuid=#{uuid} op=recv status=failed file=\"#{long_name}\" size=1000 start_byte=0 rate=0.00Mbps loss=0.00 rexreqs=0 overhead=0 errcode=78 errstr=\"Filename too long\"")
      line.call('10:07:01', '9b06', "LOG FASP Session Stop #{stop_line}")
      line.call('10:07:01', '9b06', 'LOG ======= end File Transfer statistics =======')
    end
    extra_synthetic_sample_sessions(extra, start_fields, initializing, line)
  end

  def extra_synthetic_sample_sessions(extra, start_fields, initializing, line)
    if extra.include?(:clock_problem)
      uuid = 'eeeeeeee-8888-0000-0000-000000000008'
      line.call('10:00:00', '9b08', initializing)
      line.call('10:00:00', '9b08', "LOG FASP Session Start #{start_fields.call(uuid, 'recv', 'started', '10.0.0.1:33001', '10.0.0.2:51008', '6:1:1')}")
      line.call('10:00:25', '9b08', 'LOG Receiver bl t/o/r/d/ts/c/h=100/100/0/0/0/0/0 rex_rtt l/h/s/o=0/0/0/0 ooo_rtt l/h/s/o=0/0/0/0 ' \
        'rate_rtt b/l/h/s/r/f=100/100/100/100/0/0 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 ' \
        'disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=100000000/0/100000000/100000000/100000000/100000000/100000000 prog t/f/e=1000000/1000000/25000000 rcvD=0')
      line.call('10:00:45', '9b08', 'LOG Receiver bl t/o/r/d/ts/c/h=200/200/0/0/0/0/0 rex_rtt l/h/s/o=0/0/0/0 ooo_rtt l/h/s/o=0/0/0/0 ' \
        'rate_rtt b/l/h/s/r/f=40/40/40/40/0/0 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 ' \
        'disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=100000000/0/50000000/50000000/100000000/100000000/100000000 prog t/f/e=2000000/2000000/45000000 rcvD=0')
      line.call('10:00:50', '9b08', "LOG FASP Session Stop #{start_fields.call(uuid, 'recv', 'success', '10.0.0.1:33001', '10.0.0.2:51008', '6:1:1')}")
      line.call('10:00:50', '9b08', 'LOG ======= end File Transfer statistics =======')
    end
    if extra.include?(:reverse_path_skew)
      uuid = 'eeeeeeee-9999-0000-0000-000000000009'
      line.call('10:00:00', '9b09', initializing)
      line.call('10:00:00', '9b09', "LOG FASP Session Start #{start_fields.call(uuid, 'recv', 'started', '10.0.0.1:33001', '10.0.0.2:51009', '6:1:1')}")
      line.call('10:00:25', '9b09', 'LOG Receiver bl t/o/r/d/ts/c/h=100/100/0/0/0/0/0 rex_rtt l/h/s/o=0/0/0/0 ooo_rtt l/h/s/o=0/0/0/0 ' \
        'rate_rtt b/l/h/s/r/f=100/100/100/100/0/0 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 ' \
        'disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=100000000/0/100000000/100000000/100000000/100000000/100000000 prog t/f/e=1000000/1000000/25000000 rcvD=0')
      [95, 90, 85, 80, 65].each_with_index do |brtt, i|
        sec = 30 + (i * 5)
        line.call("10:00:#{sec}", '9b09', 'LOG Receiver bl t/o/r/d/ts/c/h=200/200/0/0/0/0/0 rex_rtt l/h/s/o=0/0/0/0 ooo_rtt l/h/s/o=0/0/0/0 ' \
          "rate_rtt b/l/h/s/r/f=#{brtt}/#{brtt}/#{brtt}/#{brtt}/0/0 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 " \
          "disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=100000000/0/80000000/80000000/100000000/100000000/100000000 prog t/f/e=2000000/2000000/#{sec * 1_000_000} rcvD=0")
      end
      line.call('10:00:55', '9b09', "LOG FASP Session Stop #{start_fields.call(uuid, 'recv', 'success', '10.0.0.1:33001', '10.0.0.2:51009', '6:1:1')}")
      line.call('10:00:55', '9b09', 'LOG ======= end File Transfer statistics =======')
    end
    if extra.include?(:peer_clock_problem)
      uuid = 'eeeeeeee-aaaa-0000-0000-00000000000a'
      line.call('10:02:00', '9b0a', initializing)
      line.call('10:02:00', '9b0a', "LOG FASP Session Start #{start_fields.call(uuid, 'send', 'started', '10.0.0.1:5200a', '10.0.0.3:33001', '10:1:5678')}")
      (21..25).each do |sec|
        line.call("10:02:#{sec}", '9b0a', 'LOG Sender bl t/o/r/dl/c/h=100/100/0/0/0/0 ctl bm/bs=0/0 rex b/r/n=0/0/0 r_ott q/s/n=0/0/0 ' \
          'rate t/m/c/rc/n/vl/vr/r=100000000/0/100000000/100000000/100000000/100000000/100000000/100000000 prog t/f/e=1000000/1000000/' \
          "#{sec * 1_000_000} xmtD=0 drate=100000000")
      end
      (26..30).each do |sec|
        line.call("10:02:#{sec}", '9b0a', 'LOG Sender bl t/o/r/dl/c/h=200/200/0/0/0/0 ctl bm/bs=0/0 rex b/r/n=0/0/0 r_ott q/s/n=0/0/0 ' \
          'rate t/m/c/rc/n/vl/vr/r=100000000/0/30000000/30000000/30000000/100000000/100000000/100000000 prog t/f/e=2000000/2000000/' \
          "#{sec * 1_000_000} xmtD=0 drate=100000000")
      end
      line.call('10:02:35', '9b0a', "LOG FASP Session Stop #{start_fields.call(uuid, 'send', 'success', '10.0.0.1:5200a', '10.0.0.3:33001', '10:1:5678')}")
      line.call('10:02:35', '9b0a', 'LOG ======= end File Transfer statistics =======')
    end
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
  # @param thresholds [Hash] diagnostic thresholds
  def analyze(version: '4.4.5.123', extra: [], client: false, thresholds: {}, **log_options)
    Dir.mktmpdir do |dir|
      analyzer = described_class.new(thresholds: thresholds)
      path = File.join(dir, 'aspera-scp-transfer.log')
      File.write(path, ascp_log(version: version, extra: extra, **log_options))
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

  it 'gives a recommendation in diagnostics only, for diagnostics that have one' do
    analyze(rates: [100_000_000] * 5 + [50_000_000] * 7) do |a|
      expect(a.diagnostics).to(include(include('id' => 'rate_decline', 'recommendation' => described_class::RECOMMENDATIONS[:rate_decline])))
      expect(a.diagnostics.find { |d| d['id'] == 'cipher_set_by_server' }).not_to(include('recommendation'))
      expect(a.sessions.to_json).not_to(include('recommendation'))
      expect(a.summary.to_json).not_to(include('recommendation'))
    end
  end

  it 'has a recommendation for each flag diagnostic, or lists it as without recommendation' do
    flag_ids = described_class::Session::FLAG_DIAGNOSTICS.keys.map(&:to_s)
    expect(flag_ids - described_class::RECOMMENDATIONS.keys.map(&:to_s) - described_class::NO_RECOMMENDATION).to(be_empty)
    expect(described_class::NO_RECOMMENDATION - flag_ids).to(be_empty)
    expect(described_class::NO_RECOMMENDATION & described_class::RECOMMENDATIONS.keys.map(&:to_s)).to(be_empty)
  end

  it 'diagnoses a rate decline between the first and second half of the samples' do
    # 12 samples, the last 10% are dropped as end of session: 5 at 100 Mbps, then 5 at 50 Mbps (50%)
    analyze(rates: [100_000_000] * 5 + [50_000_000] * 7) do |a|
      expect(a.diagnostics).to(include(include(
        'pid' => '9a01', 'id' => 'rate_decline', 'severity' => 'warning',
        'message' => 'The rate declined during the transfer: 50,000,000 bps on average in the second half, 100,000,000 bps in the first half (50%).'
      )))
    end
  end

  it 'does not diagnose a rate decline above the threshold, with the peer changing the rate, or with too few samples' do
    ids = ->(a) { a.diagnostics.select { |d| d['pid'] == '9a01' }.map { |d| d['id'] } }
    # 80% of the first half
    analyze(rates: [100_000_000] * 5 + [80_000_000] * 7) { |a| expect(ids.call(a)).not_to(include('rate_decline')) }
    # Rate parameters changed by the peer
    analyze(rates: [100_000_000] * 5 + [50_000_000] * 7, peer_params: true) { |a| expect(ids.call(a)).not_to(include('rate_decline')) }
    # 9 samples: 8 remain after dropping the end of the session
    analyze(rates: [100_000_000] * 5 + [50_000_000] * 4) { |a| expect(ids.call(a)).not_to(include('rate_decline')) }
    # Lower threshold on the number of samples
    analyze(rates: [100_000_000] * 5 + [50_000_000] * 4, thresholds: {rate_decline_min_samples: 8}) { |a| expect(ids.call(a)).to(include('rate_decline')) }
    # Lower ratio
    analyze(rates: [100_000_000] * 5 + [50_000_000] * 7, thresholds: {rate_decline_ratio: 0.5}) { |a| expect(ids.call(a)).not_to(include('rate_decline')) }
  end

  # Log of one sender session (`aaaa`) with the given `Initializing FASP version` details and extra lines
  # @param before [Array<String>] lines between `Initializing` and `Session Start`
  # @param port   [String]        `tcp_port=33001` or `wss_port=9093` of `Session Start`
  # @param params [String]        additional fields of `Session Params`
  def minor_log(license: 'license max rate=(unlimited)', lines: [], target_rate: 100_000_000, before: [], port: 'tcp_port=33001', params: '')
    fields = "uuid=ffffffff-0000-0000-0000-000000000001 op=send status=%s source=/src dest=/dst source_prefix=- local=10.0.0.1:52000 peer=10.0.0.3:33001 #{port} " \
      'os="Linux 5.14" ver=4.4.8.2596 lic=10:1:1234 peeros="Linux 5.14" peerver=4.4.8.2596 peerlic=6:1:1'
    [
      'LOG Configuration: using v2 configuration file "/opt/aspera/etc/aspera.conf", user -',
      "LOG Initializing FASP version 4.4.8.2596 b12cd13, #{license}, account no.=1, license no.=1234 product=10",
      *before,
      *lines.first(1),
      "LOG FASP Session Start #{format(fields, 'started')}",
      "LOG FASP Session Params uuid=ffffffff-0000-0000-0000-000000000001 userid=0 user=\"xfer\" targetrate=#{target_rate} minrate=0 rate_policy=fair cipher=aes-256-gcm " \
        "resume=2 ovr=1 rd_sz=0 wr_sz=0 xfer_id=-#{params}",
      *lines.drop(1),
      "LOG FASP Session Stop #{format(fields, 'success')}",
      'LOG ======= end File Transfer statistics ======='
    ].map { |text| "2026-01-10 10:00:00.000 [aaaa-140001] #{text}\n" }.join
  end

  def analyze_minor(**log_options)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'aspera-scp-transfer.log')
      File.write(path, minor_log(**log_options))
      analyzer = described_class.new(zero_bytes: true)
      analyzer.add(path)
      yield(analyzer, analyzer.diagnostics.to_h { |d| [d['id'], d] })
    end
  end

  # @return [Hash] the session of a log made by `minor_log`
  def minor_session(**log_options)
    analyze_minor(**log_options) { |analyzer, _diagnostics| return analyzer.sessions.first }
  end

  it 'diagnoses a sender that receives no packet from the receiver' do
    lines = ['LOG Sender has not received a packet for 3 seconds!', 'LOG Sender has not received a packet for 4 seconds!', 'LOG Sender has not received a packet for 5 seconds!']
    analyze_minor(lines: lines) do |_analyzer, diagnostics|
      expect(diagnostics).to(include('feedback_interruption' => include('severity' => 'warning', 'message' => /up to 5 seconds \(5 seconds in total\)/, 'recommendation' => be_a(String))))
      expect(diagnostics).not_to(include('reception_interruption'))
    end
    analyze_minor(lines: ['LOG Receiver has not received a packet for 2 seconds!']) do |_analyzer, diagnostics|
      expect(diagnostics).to(include('reception_interruption'))
      expect(diagnostics).not_to(include('feedback_interruption'))
    end
  end

  it 'counts overflows of the retransmission timer' do
    lines = Array.new(3) { 'LOG Warning: rex timer overflow auto-adjusted crt_tick=162970 rex_timer crt/max=121689/131689' }
    analyze_minor(lines: lines) do |_analyzer, diagnostics|
      expect(diagnostics).to(include('rex_timer_overflow' => include('severity' => 'warning', 'message' => /at least 3 times/, 'recommendation' => be_a(String))))
    end
    analyze_minor { |_analyzer, diagnostics| expect(diagnostics).not_to(include('rex_timer_overflow')) }
  end

  it 'diagnoses a license that limits the rate below the target rate' do
    analyze_minor(license: 'license max rate=10 Mbps') do |_analyzer, diagnostics|
      expect(diagnostics).to(include('license_rate_limit' => include('severity' => 'warning', 'message' => /limits the rate to 10,000,000 bps, below the target rate of 100,000,000 bps/, 'recommendation' => be_a(String))))
    end
    analyze_minor(license: 'license max rate=100 Mbps') { |_analyzer, diagnostics| expect(diagnostics).not_to(include('license_rate_limit')) }
    analyze_minor { |_analyzer, diagnostics| expect(diagnostics).not_to(include('license_rate_limit')) }
  end

  it 'diagnoses a license that expires soon or has expired' do
    analyze_minor(license: 'license expires on Thu Jan 22 09:59:59 2026, max rate=(unlimited)') do |_analyzer, diagnostics|
      expect(diagnostics).to(include('license_expiry' => include('severity' => 'warning', 'message' => /expires on Thu Jan 22 09:59:59 2026, 11 days after/, 'recommendation' => be_a(String))))
    end
    analyze_minor(license: 'license expires on Tue Jun 30 09:59:59 2015, max rate=(unlimited)') do |_analyzer, diagnostics|
      expect(diagnostics).to(include('license_expiry' => include('message' => 'The license expired on Tue Jun 30 09:59:59 2015.')))
    end
    analyze_minor(license: 'license expires on Sat Jan  1 00:00:00 2033, max rate=(unlimited)') { |_analyzer, diagnostics| expect(diagnostics).not_to(include('license_expiry')) }
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'aspera-scp-transfer.log')
      File.write(path, minor_log(license: 'license expires on Thu Jan 22 09:59:59 2026, max rate=(unlimited)'))
      analyzer = described_class.new(zero_bytes: true, thresholds: {license_expiry_days: 5})
      analyzer.add(path)
      expect(analyzer.diagnostics.map { |d| d['id'] }).not_to(include('license_expiry'))
    end
  end

  it 'mentions configuration noise in findings of the summary, without diagnostic' do
    lines = ['ERR /opt/aspera/httpgateway/lib/ossl-modules not found', 'ERR Warning: unable to submit change event  1-1000000, rc=-1']
    analyze_minor(lines: lines) do |analyzer, diagnostics|
      expect(diagnostics.keys).not_to(include('ossl_modules_missing', 'change_event_failed'))
      expect(analyzer.summary['findings']).to(include(a_string_matching(/OpenSSL modules folder/), a_string_matching(/schedule of the virtual link capacity/)))
    end
  end

  it 'reports the product from the line logged by ascp, with or without IBM' do
    server = minor_session(before: ['LOG IBM Aspera High-Speed Transfer Server version 4.4.8.2596'])
    expect(server).to(include('product' => 10, 'product_name' => 'Aspera High-Speed Transfer Server'))
    expect(minor_session(before: ['LOG Aspera Connect version 3.6.0.106805'])).to(include('product_name' => 'Aspera Connect'))
    expect(minor_session(before: ['LOG IBM Aspera Transfer SDK version 4.4.8.2592'])).to(include('product_name' => 'Aspera Transfer SDK'))
    expect(minor_session).not_to(include('product_name'))
  end

  it 'reports the authentication type, never its value' do
    token = 'LOG ASPERA_AUTH_TOKEN is set to TOKEN.  Applying overrides.'
    node = 'LOG Node storage access_key=ak-test identity_user=ASPERA_NODE_ADMIN file_id=(NULL) root=file:////data/files'
    expect(minor_session(before: [token, node])).to(include('authentication' => 'token'))
    expect(minor_session(before: [token])).to(include('authentication' => 'token'))
    expect(minor_session(before: [node])).to(include('authentication' => 'node'))
    expect(minor_session).not_to(include('authentication'))
    expect(minor_session(before: [token, node]).to_s).not_to(match(%r{ak-test|ASPERA_NODE_ADMIN|data/files}))
  end

  it 'reports the transport from the port of Session Start' do
    expect(minor_session).to(include('transport' => 'ssh'))
    expect(minor_session(port: 'wss_port=9093')).to(include('transport' => 'wss'))
  end

  it 'reports the proxy and FIPS mode from Session Params, never the cookie' do
    session = minor_session(params: ' fips_enabled=no proxy_ip=- cookie="aspera.aoc:private-data"')
    expect(session).to(include('fips' => false))
    expect(session).not_to(include('proxy'))
    expect(session.to_s).not_to(match(/cookie|private-data/))
    expect(minor_session(params: ' fips_enabled=yes proxy_ip=10.1.2.3')).to(include('fips' => true, 'proxy' => '10.1.2.3'))
    expect(minor_session).not_to(include('fips', 'proxy'))
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

  it 'groups samples into time buckets aligned on the period' do
    sample = ->(sec, blk, bytes) do
      time = format('10:%02d:%02d', sec / 60, sec % 60)
      "2026-01-10 #{time}.000 [1a2b-1] LOG Receiver bl t/o/r/d/ts/c/h=#{blk}/#{blk}/0/0/0/0/0 rex_rtt l/h/s/o=0/0/0/0 ooo_rtt l/h/s/o=0/0/0/0 " \
        'rate_rtt b/l/h/s/r/f=20/20/20/20/0/1 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 ' \
        'disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=10000000/0/10000000/10000000/10000000/10000000/10000000 ' \
        "prog t/f/e=#{bytes}/#{bytes}/#{sec * 1_000_000} rcvD=0"
    end
    init = [
      '2026-01-10 10:00:15.000 [1a2b-1] LOG Configuration: using v2 configuration file "/opt/aspera/etc/aspera.conf", user xfer',
      '2026-01-10 10:00:15.000 [1a2b-1] LOG Initializing FASP version 4.4.5, license max rate=(unlimited), account no.=1, license no.=1 product=10',
      '2026-01-10 10:00:15.000 [1a2b-1] LOG FASP Session Start uuid=11111111-0000-0000-0000-000000000001 op=recv status=started ' \
        'source=/src dest=/dst source_prefix=- local=10.0.0.1:33001 peer=10.0.0.2:51000 tcp_port=33001 os="Linux" ver=4.4.5 lic=10:1:1 peeros="Linux" peerver=4.4.5 peerlic=6:1:1'
    ]
    fin = [
      '2026-01-10 10:03:00.000 [1a2b-1] LOG FASP Session Stop uuid=11111111-0000-0000-0000-000000000001 op=recv status=success local=10.0.0.1:33001 peer=10.0.0.2:51000',
      '2026-01-10 10:03:00.000 [1a2b-1] LOG ======= end File Transfer statistics ======='
    ]
    Dir.mktmpdir do |dir|
      log = (init + [sample.call(20, 100, 100_000), sample.call(59, 500, 500_000), sample.call(60, 600, 600_000), sample.call(110, 1000, 1_000_000)] + fin).join("\n")
      path = File.join(dir, 'test.log')
      File.write(path, log)
      analyzer = described_class.new(period: 60, timezone: 'UTC').add(path)
      times = analyzer.snapshots.map { |s| s['time'] }
      expect(times).to(eq(['2026-01-10T10:00:00Z', '2026-01-10T10:01:00Z']))
      expect(analyzer.snapshots.first['sessions']).to(eq(1))
      expect(analyzer.snapshots.first['rate']).to(be_positive)
    end
  end

  it 'does not report empty periods and handles a single sample in a bucket' do
    sample = ->(sec, blk, bytes) do
      time = format('10:%02d:%02d', sec / 60, sec % 60)
      "2026-01-10 #{time}.000 [1a2b-1] LOG Receiver bl t/o/r/d/ts/c/h=#{blk}/#{blk}/0/0/0/0/0 rex_rtt l/h/s/o=0/0/0/0 ooo_rtt l/h/s/o=0/0/0/0 " \
        'rate_rtt b/l/h/s/r/f=20/20/20/20/0/1 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 ' \
        'disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=10000000/0/10000000/10000000/10000000/10000000/10000000 ' \
        "prog t/f/e=#{bytes}/#{bytes}/#{sec * 1_000_000} rcvD=0"
    end
    init = [
      '2026-01-10 10:00:00.000 [1a2b-1] LOG Configuration: using v2 configuration file "/opt/aspera/etc/aspera.conf", user xfer',
      '2026-01-10 10:00:00.000 [1a2b-1] LOG Initializing FASP version 4.4.5, license max rate=(unlimited), account no.=1, license no.=1 product=10',
      '2026-01-10 10:00:00.000 [1a2b-1] LOG FASP Session Start uuid=11111111-0000-0000-0000-000000000001 op=recv status=started ' \
        'source=/src dest=/dst source_prefix=- local=10.0.0.1:33001 peer=10.0.0.2:51000 tcp_port=33001 os="Linux" ver=4.4.5 lic=10:1:1 peeros="Linux" peerver=4.4.5 peerlic=6:1:1'
    ]
    fin = [
      '2026-01-10 10:05:00.000 [1a2b-1] LOG FASP Session Stop uuid=11111111-0000-0000-0000-000000000001 op=recv status=success local=10.0.0.1:33001 peer=10.0.0.2:51000',
      '2026-01-10 10:05:00.000 [1a2b-1] LOG ======= end File Transfer statistics ======='
    ]
    Dir.mktmpdir do |dir|
      # Minute 0: 2 samples (rate computed)
      # Minute 1: empty (no sample)
      # Minute 2: 1 single sample (no delta -> rate is 0 -> not reported without zero_bytes)
      # Minute 3: 2 samples (rate computed)
      log = (init + [sample.call(10, 100, 100_000), sample.call(40, 400, 400_000), sample.call(130, 500, 500_000), sample.call(190, 600, 600_000), sample.call(220, 900, 900_000)] + fin).join("\n")
      path = File.join(dir, 'test.log')
      File.write(path, log)
      analyzer = described_class.new(period: 60, timezone: 'UTC').add(path)
      times = analyzer.snapshots.map { |s| s['time'] }
      expect(times).to(eq(['2026-01-10T10:00:00Z', '2026-01-10T10:03:00Z']))

      # With zero_bytes: true, single-sample and zero-rate periods are reported
      zero_analyzer = described_class.new(period: 60, zero_bytes: true, timezone: 'UTC').add(path)
      zero_times = zero_analyzer.snapshots.map { |s| s['time'] }
      expect(zero_times).to(eq(['2026-01-10T10:00:00Z', '2026-01-10T10:02:00Z', '2026-01-10T10:03:00Z']))
    end
  end

  it 'applies samples in log order between two rate changes of the peer' do
    sample = ->(sec, target) do
      time = format('10:%02d:%02d', sec / 60, sec % 60)
      "2026-01-10 #{time}.000 [1a2b-1] LOG Receiver bl t/o/r/d/ts/c/h=#{sec}00/#{sec}00/0/0/0/0/0 rex_rtt l/h/s/o=0/0/0/0 ooo_rtt l/h/s/o=0/0/0/0 " \
        'rate_rtt b/l/h/s/r/f=20/20/20/20/0/1 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/0/0/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=0/0/0/0/0/0/0/0/0/0 ' \
        "disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=#{target}/0/#{target}/#{target}/#{target}/#{target}/#{target} " \
        "prog t/f/e=#{sec}000/#{sec}000/#{sec * 1_000_000} rcvD=0"
    end
    peer_rate = ->(sec, target) { format("2026-01-10 10:%02d:%02d.000 [1a2b-1] LOG Peer requested rate params adopted,  target_rate #{target} min_rate 0 transfer_policy fair", 0, sec) }
    lines = [
      '2026-01-10 10:00:00.000 [1a2b-1] LOG Configuration: using v2 configuration file "/opt/aspera/etc/aspera.conf", user xfer',
      '2026-01-10 10:00:00.000 [1a2b-1] LOG Initializing FASP version 4.4.5, license max rate=(unlimited), account no.=1, license no.=1 product=10',
      '2026-01-10 10:00:00.000 [1a2b-1] LOG FASP Session Start uuid=11111111-0000-0000-0000-000000000001 op=recv status=started ' \
        'source=/src dest=/dst source_prefix=- local=10.0.0.1:33001 peer=10.0.0.2:51000 tcp_port=33001 os="Linux" ver=4.4.5 lic=10:1:1 peeros="Linux" peerver=4.4.5 peerlic=6:1:1',
      '2026-01-10 10:00:00.000 [1a2b-1] LOG FASP Session Params uuid=11111111-0000-0000-0000-000000000001 userid=0 user="xfer" targetrate=100000000 minrate=0 ' \
        'rate_policy=fair cipher=aes-128 resume=0 ovr=1 rd_sz=0 wr_sz=0 xfer_id=-',
      sample.call(10, 100_000_000),
      # The peer removes the limit, then the next sample still shows the previous target rate, then the peer sets another limit
      peer_rate.call(20, 0),
      sample.call(25, 100_000_000),
      peer_rate.call(30, 80_000_000),
      sample.call(40, 80_000_000), sample.call(50, 80_000_000),
      '2026-01-10 10:01:00.000 [1a2b-1] LOG FASP Session Stop uuid=11111111-0000-0000-0000-000000000001 op=recv status=success local=10.0.0.1:33001 peer=10.0.0.2:51000',
      '2026-01-10 10:01:00.000 [1a2b-1] LOG ======= end File Transfer statistics ======='
    ]
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.log')
      File.write(path, lines.join("\n"))
      analyzer = described_class.new(timezone: 'UTC').add(path)
      change = analyzer.diagnostics.find { |d| d['id'].eql?('rate_change') }
      expect(change['message']).to(eq('Last of multiple parameter changes by peer: Target rate changed from 100,000,000 bps to 80,000,000 bps.'))
      expect(analyzer.sessions.first['target_rate']).to(eq(80_000_000))
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

  # `ascp` writes `<name>.<n>.log` (n from 0 to log_count, circular), and `<name>.log` is a hard link to the current one
  it 'analyzes once a log file linked to its rotated name, in a folder' do
    Dir.mktmpdir do |dir|
      current = File.join(dir, 'aspera-scp-transfer.3.log')
      File.write(current, ascp_log)
      File.link(current, File.join(dir, 'aspera-scp-transfer.log'))
      older = File.join(dir, 'aspera-scp-transfer.2.log')
      File.write(older, ascp_log)
      paths = described_class.log_paths(dir)
      expect(paths.map { |p| File.basename(p) }).to(contain_exactly('aspera-scp-transfer.2.log', a_string_matching(/\Aaspera-scp-transfer(\.3)?\.log\z/)))
      expect(described_class.new.add(dir).summary['files']).to(eq(2))
      expect(described_class.new.add(current).summary['sessions']).to(eq(2))
      expect(described_class.new.add(dir).summary['sessions']).to(eq(4))
    end
  end

  it 'analyzes log files of a circular rotation with a missing hole in a folder' do
    Dir.mktmpdir do |dir|
      [0, 1, 2, 3, 5, 6].each do |n|
        path = File.join(dir, "aspera-scp-transfer.#{n}.log")
        File.write(path, ascp_log)
      end
      analyzer = described_class.new.add(dir)
      expect(analyzer.summary['files']).to(eq(6))
      expect(analyzer.summary['sessions']).to(eq(12))
    end
  end

  # @param path [String] File to create
  # @param text [String] Content, compressed with gzip
  def write_gzip(path, text)
    Zlib::GzipWriter.open(path) { |gz| gz.write(text) }
  end

  it 'reads a log file compressed with gzip, like the same plain log' do
    Dir.mktmpdir do |dir|
      plain = File.join(dir, 'aspera.log')
      File.write(plain, ascp_log)
      packed = File.join(dir, 'aspera.log-20260110.gz')
      write_gzip(packed, ascp_log)
      expected = described_class.new.add(plain)
      analyzer = described_class.new.add(packed)
      expect(analyzer.summary['sessions']).to(eq(2))
      %i[summary sessions diagnostics snapshots peers].each do |table|
        expect(analyzer.public_send(table).to_s.gsub(packed, plain)).to(eq(expected.public_send(table).to_s))
      end
      expect(described_class::Records.list(:sessions, [packed])).to(eq(described_class::Records.list(:sessions, [plain])))
    end
  end

  it 'analyzes log files compressed with gzip in a folder, with rotation names' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'aspera-scp-transfer.log'), ascp_log)
      write_gzip(File.join(dir, 'aspera-scp-transfer.1.log.gz'), ascp_log)
      write_gzip(File.join(dir, 'aspera.log-20260101.gz'), ascp_log)
      analyzer = described_class.new.add(dir)
      expect(analyzer.summary['files']).to(eq(3))
      expect(analyzer.summary['sessions']).to(eq(6))
    end
  end

  it 'reads logs from the standard input, plain or compressed with gzip' do
    input = $stdin
    begin
      $stdin = StringIO.new(ascp_log)
      expect(described_class.new.add('-').summary['sessions']).to(eq(2))
      $stdin = StringIO.new(Zlib.gzip(ascp_log))
      expect(described_class.new.add('-').summary['sessions']).to(eq(2))
    ensure
      $stdin = input
    end
  end

  it 'ignores files that are not ascp logs in a folder, and rejects them when given explicitly' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'aspera-scp-transfer.log'), ascp_log)
      File.write(File.join(dir, 'other.log'), "hello\nnot an ascp log\n")
      write_gzip(File.join(dir, 'other.log.gz'), "hello\n")
      File.binwrite(File.join(dir, 'broken.log.gz'), Zlib.gzip(ascp_log)[0, 30])
      expect(described_class.new.add(dir).summary['files']).to(eq(1))
      expect { described_class.new.add(File.join(dir, 'other.log')) }.to(raise_error(Aspera::ParameterError, /Not an ascp log: .*other\.log/))
      expect { described_class.new.add(File.join(dir, 'broken.log.gz')) }.to(raise_error(Aspera::ParameterError, /Cannot read .*broken\.log\.gz/))
      expect { described_class::Records.list(:sessions, [File.join(dir, 'other.log')]) }.to(raise_error(Aspera::ParameterError, /Not an ascp log/))
    end
  end

  it 'detects synthetic diagnostic errors without real log fixtures' do
    synthetic_ids = %i[
      token_expired
      out_of_disk
      content_protection
      bind_udp_socket_failed
      sharing_violation
      filename_too_long
      configuration_error
      clock_problem
      reverse_path_skew
      peer_clock_problem
    ]
    synthetic_ids.each do |extra_id|
      analyze(extra: [extra_id]) do |analyzer|
        expect(analyzer.diagnostics.map { |d| d['id'] }).to(include(extra_id.to_s))
      end
    end
  end

  it 'warns about ascp older than 4.0, and does not categorize its errors' do
    analyze(version: '3.9.6.1234') do |analyzer|
      expect(analyzer.warnings).to(contain_exactly(/ascp 3\.9\.6\.1234 is older than 4\.0/))
      expect(analyzer.sessions.first['diagnostics']).to(include(/older than 4\.0/))
      expect(session_of(analyzer, '2c3d')).not_to(have_key('error_category'))
    end
  end

  it 'uses default thresholds and allows overriding them to change diagnostics' do
    analyzer = described_class.new
    expect(analyzer.thresholds).to(eq(described_class::DEFAULT_THRESHOLDS))
    # With default threshold (efficiency: 90.0), 85% efficiency emits a warning
    analyze do |a|
      expect(session_of(a, '1a2b')['diagnostics']).to(include(/Only 85\.0% of the data blocks sent were useful/))
    end
    # With overridden threshold (efficiency: 80.0), 85% efficiency does not emit a warning
    analyze(thresholds: {efficiency: 80.0}) do |a|
      expect(session_of(a, '1a2b')['diagnostics']).not_to(include(/useful/))
    end
    # Overriding retry_window changes retry detection
    analyze(extra: %i[retry], thresholds: {retry_window: 10}) do |a|
      expect(session_of(a, '2c3d')).not_to(have_key('retried_by'))
    end
    # Unknown threshold raises ArgumentError
    expect { described_class.new(thresholds: {unknown_threshold: 42}) }.to(raise_error(ArgumentError, /Unknown threshold: unknown_threshold/))
  end

  # Syslog log (lines without year) of two sessions on both sides of a new year: December 30, then January 1
  # @param mtime [Time] modification date of the file
  # @param timezone [String, nil] time zone of the log lines
  def syslog_analyzer(mtime, timezone: nil)
    session = ->(pid, uuid, status, stamp) do
      "#{stamp} host ascp[#{pid}]: LOG FASP Session #{status} uuid=#{uuid} op=recv status=#{status == 'Start' ? 'started' : 'success'} source=/src dest=/dst " \
        'local=10.0.0.1:33001 peer=10.0.0.2:51000 ver=4.4.5.123 lic=10:1:1234'
    end
    lines = [
      session.call('1a2b', 'aaaaaaaa-1111-2222-3333-444444444444', 'Start', 'Dec 30 23:00:00'),
      session.call('1a2b', 'aaaaaaaa-1111-2222-3333-444444444444', 'Stop', 'Dec 31 12:00:00'),
      session.call('2c3d', 'bbbbbbbb-1111-2222-3333-444444444444', 'Start', 'Jan  1 01:00:00'),
      session.call('2c3d', 'bbbbbbbb-1111-2222-3333-444444444444', 'Stop', 'Jan  1 02:00:00')
    ]
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'aspera.log')
      File.write(path, "#{lines.join("\n")}\n")
      File.utime(mtime, mtime, path)
      return described_class.new(zero_bytes: true, timezone: timezone).add(path)
    end
  end

  it 'deduces the year of syslog lines from the modification date of the file, over a new year' do
    # Analyzed in March: December is of the previous year (it was of the current year when guessed from the current date)
    starts = syslog_analyzer(Time.utc(2026, 3, 15), timezone: 'UTC').sessions.map { |s| s['start'] }
    expect(starts).to(eq(%w[2025-12-30T23:00:00Z 2026-01-01T01:00:00Z]))
    # File modified in the year of the log
    starts = syslog_analyzer(Time.utc(2026, 1, 2), timezone: 'UTC').sessions.map { |s| s['start'] }
    expect(starts).to(eq(%w[2025-12-30T23:00:00Z 2026-01-01T01:00:00Z]))
    # The year does not depend on the current date
    expect(syslog_analyzer(Time.utc(2020, 1, 2), timezone: 'UTC').summary['first_log']).to(eq('2019-12-30T23:00:00Z'))
  end

  it 'reads times in the time zone of the analyst by default, and in the time zone of the option' do
    mtime = Time.utc(2026, 3, 15)
    local = syslog_analyzer(mtime).sessions.map { |s| s['start'] }
    expect(local).to(eq([Time.new(2025, 12, 30, 23, 0, 0).iso8601, Time.new(2026, 1, 1, 1, 0, 0).iso8601]))
    expect(syslog_analyzer(mtime, timezone: '+02:00').sessions.map { |s| s['start'] }).to(eq(%w[2025-12-30T23:00:00+02:00 2026-01-01T01:00:00+02:00]))
    # Same line, different time zone: different instant
    utc = Time.parse(syslog_analyzer(mtime, timezone: 'UTC').summary['first_log'])
    plus2 = Time.parse(syslog_analyzer(mtime, timezone: '+02:00').summary['first_log'])
    expect(utc - plus2).to(eq(7200))
    expect(described_class::Records.list(:sessions, [], timezone: '+02:00')).to(eq([]))
  end

  it 'refuses an invalid time zone' do
    expect { described_class.new(timezone: 'Mars') }.to(raise_error(Aspera::ParameterError, /Invalid time zone: "Mars"/))
    expect { described_class::Records.list(:sessions, [], timezone: '+25:00') }.to(raise_error(Aspera::ParameterError, /Invalid time zone/))
  end

  it 'diagnoses small files when many files with a small mean size are transferred' do
    uuid = 'ffffffff-0000-0000-0000-000000000001'
    transfers = (1..110).map do |i|
      "LOG FASP Transfer Stop uuid=#{uuid} op=send status=success file=\"/src/file#{i}.txt\" size=4096 start_byte=0 rate=1.00Mbps loss=0.00 rexreqs=0 overhead=0"
    end
    analyze_minor(lines: transfers) do |_analyzer, diagnostics|
      expect(diagnostics).to(include('small_files' => include('severity' => 'warning', 'message' => /110 files.*mean size.*4,096 bytes/, 'recommendation' => be_a(String))))
    end
  end

  it 'does not diagnose small files when the count is below the threshold' do
    uuid = 'ffffffff-0000-0000-0000-000000000001'
    transfers = (1..50).map do |i|
      "LOG FASP Transfer Stop uuid=#{uuid} op=send status=success file=\"/src/file#{i}.txt\" size=4096 start_byte=0 rate=1.00Mbps loss=0.00 rexreqs=0 overhead=0"
    end
    analyze_minor(lines: transfers) { |_analyzer, diagnostics| expect(diagnostics).not_to(include('small_files')) }
  end

  it 'does not diagnose small files when the mean size is above the threshold' do
    uuid = 'ffffffff-0000-0000-0000-000000000001'
    transfers = (1..110).map do |i|
      "LOG FASP Transfer Stop uuid=#{uuid} op=send status=success file=\"/src/file#{i}.txt\" size=5000000 start_byte=0 rate=1.00Mbps loss=0.00 rexreqs=0 overhead=0"
    end
    analyze_minor(lines: transfers) { |_analyzer, diagnostics| expect(diagnostics).not_to(include('small_files')) }
  end

  it 'respects the small_files thresholds' do
    uuid = 'ffffffff-0000-0000-0000-000000000001'
    transfers = (1..20).map do |i|
      "LOG FASP Transfer Stop uuid=#{uuid} op=send status=success file=\"/src/file#{i}.txt\" size=500000 start_byte=0 rate=1.00Mbps loss=0.00 rexreqs=0 overhead=0"
    end
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'aspera-scp-transfer.log')
      File.write(path, minor_log(lines: transfers))
      # With custom thresholds: fires at 20 files and 500 KB
      analyzer = described_class.new(zero_bytes: true, thresholds: {small_files_min_count: 20, small_files_max_mean: 1_000_000})
      expect(analyzer.add(path).diagnostics.map { |d| d['id'] }).to(include('small_files'))
      # Default thresholds (100 files): does not fire
      analyzer2 = described_class.new(zero_bytes: true)
      expect(analyzer2.add(path).diagnostics.map { |d| d['id'] }).not_to(include('small_files'))
    end
  end

  it 'diagnoses a small path MTU, which suggests a VPN or a tunnel' do
    lines = ['LOG Measured pMTU: 1006 Bytes, start_brtt: 32 ms', 'LOG datagram size 992B, block size 928B, path MTU 1006B']
    analyze_minor(lines: lines) do |_analyzer, diagnostics|
      expect(diagnostics).to(include('small_mtu' => include('severity' => 'info', 'message' => /path MTU measured by ascp is 1006 bytes.*datagram size: 992 bytes/, 'recommendation' => be_a(String))))
    end
  end

  it 'does not diagnose the usual path MTU' do
    analyze_minor(lines: ['LOG datagram size 1472B, block size 1408B, path MTU 1492B']) { |_analyzer, diagnostics| expect(diagnostics).not_to(include('small_mtu')) }
    # Old format without path MTU: no diagnostic
    analyze_minor(lines: ['LOG datagram size 960B, block size 896B']) { |_analyzer, diagnostics| expect(diagnostics).not_to(include('small_mtu')) }
  end

  it 'respects the small_mtu_max threshold' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'aspera-scp-transfer.log')
      File.write(path, minor_log(lines: ['LOG datagram size 1472B, block size 1408B, path MTU 1492B']))
      expect(described_class.new(zero_bytes: true, thresholds: {small_mtu_max: 1500}).add(path).diagnostics.map { |d| d['id'] }).to(include('small_mtu'))
    end
  end

  describe Aspera::Ascp::LogAnalyzer::Diagnostics do
    it 'diagnoses license expiry isolated on a session' do
      session = Aspera::Ascp::LogAnalyzer::Session.new('1234')
      session[:license_expires] = '2026-10-10'
      session[:start] = Time.parse('2026-10-01').to_i
      diagnostics = described_class.new(session)
      diagnostics.diagnose_license
      expect(diagnostics.list).to(eq([
        {'id' => 'license_expiry', 'severity' => 'warning', 'message' => 'The license expires on 2026-10-10, 9 days after the start of this session.'}
      ]))
    end

    it 'diagnoses low efficiency isolated on a session' do
      session = Aspera::Ascp::LogAnalyzer::Session.new('1234')
      session[:efficiency] = 75.0
      session.increment(:tx_bytes, 1000)
      diagnostics = described_class.new(session)
      diagnostics.diagnose_quality
      expect(diagnostics.list).to(eq([
        {'id' => 'low_efficiency', 'severity' => 'warning', 'message' => 'Only 75.0% of the data blocks sent were useful: retransmissions reduce the effective rate.'}
      ]))
    end
  end

  describe 'AscpLogsActions health command' do
    before do
      require 'aspera/cli/error'
      require 'aspera/cli/result'
      require 'aspera/cli/ascp_logs_actions'
    end

    # Helper to create a dummy CLI plugin that includes AscpLogsActions
    let(:plugin) do
      # Define the class in the correct namespace to resolve BadArgument, etc.
      unless defined?(Aspera::Cli::DummyHealthPlugin)
        module Aspera
          module Cli
            class DummyHealthPlugin
              class << self
                def option(*_args); end
              end

              include Aspera::Cli::AscpLogsActions

              BadArgument = Aspera::Cli::BadArgument
              ParameterError = Aspera::ParameterError
              Result = Aspera::Cli::Result
              attr_accessor :ascp_logs_options

              def initialize
                @ascp_logs_options = {}
              end

              def options
                self
              end

              def get_option(name)
                return @ascp_logs_options if name == :ascp_logs
                nil
              end
            end
          end
        end
      end
      Aspera::Cli::DummyHealthPlugin.new
    end

    it 'returns OK when no failures or low efficiency are present' do
      log_ok = <<~EOF
        2026-01-10 10:00:00.000 [aaaa-140001] LOG FASP Session Start uuid=ffffffff-0000-0000-0000-000000000001 op=send status=started local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
        2026-01-10 10:00:10.000 [aaaa-140001] LOG FASP Session Stop uuid=ffffffff-0000-0000-0000-000000000001 op=send status=success local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
      EOF
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ascp.log')
        File.write(path, log_ok)
        File.utime(Time.parse('2026-01-10 10:10:00'), Time.parse('2026-01-10 10:10:00'), path)

        now = Time.parse('2026-01-10 10:30:00')
        result = plugin.action_ascp_logs_health(paths: [path], now: now)
        expect(result.data).to(eq([
          {'status' => 'ok', 'component' => 'ascp logs', 'message' => '0 failed, 0 low efficiency in last 60 min'}
        ]))
      end
    end

    it 'returns WARNING when low efficiency is present' do
      log_warning = <<~EOF
        2026-01-10 10:00:00.000 [aaaa-140001] LOG FASP Session Start uuid=ffffffff-0000-0000-0000-000000000001 op=send status=started local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
        2026-01-10 10:00:05.000 [aaaa-140001] LOG FASP Session Statistics [Sender] id=ffffffff-0000-0000-0000-000000000001 delay=8ms rex_delay=30ms solicited_rex=25.00% unsolicited_rex=0.00% ave_xmit_rate 10.00Mbps effective=75.00% effective_rate=10.00Mbps (progress: tx_bytes 1000 file_bytes 1000 tx_time 1000)
        2026-01-10 10:00:10.000 [aaaa-140001] LOG FASP Session Stop uuid=ffffffff-0000-0000-0000-000000000001 op=send status=success local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
      EOF
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ascp.log')
        File.write(path, log_warning)
        File.utime(Time.parse('2026-01-10 10:10:00'), Time.parse('2026-01-10 10:10:00'), path)

        now = Time.parse('2026-01-10 10:30:00')
        result = plugin.action_ascp_logs_health(paths: [path], now: now)
        expect(result.data).to(eq([
          {'status' => 'warning', 'component' => 'ascp logs', 'message' => '0 failed, 1 low efficiency in last 60 min'}
        ]))
      end
    end

    it 'returns CRITICAL when a failure is present' do
      log_critical = <<~EOF
        2026-01-10 10:00:00.000 [aaaa-140001] LOG FASP Session Start uuid=ffffffff-0000-0000-0000-000000000001 op=send status=started local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
        2026-01-10 10:00:10.000 [aaaa-140001] LOG FASP Session Stop uuid=ffffffff-0000-0000-0000-000000000001 op=send status=failed errcode=36 errstr="Session data transfer timeout" local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
      EOF
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ascp.log')
        File.write(path, log_critical)
        File.utime(Time.parse('2026-01-10 10:10:00'), Time.parse('2026-01-10 10:10:00'), path)

        now = Time.parse('2026-01-10 10:30:00')
        result = plugin.action_ascp_logs_health(paths: [path], now: now)
        expect(result.data).to(eq([
          {'status' => 'critical', 'component' => 'ascp logs', 'message' => '1 failed, 0 low efficiency in last 60 min'}
        ]))
      end
    end

    it 'ignores old errors outside the time window and counts recent ones' do
      log_mixed = <<~EOF
        2026-01-10 09:00:00.000 [aaaa-140001] LOG FASP Session Start uuid=ffffffff-0000-0000-0000-000000000001 op=send status=started local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
        2026-01-10 09:00:10.000 [aaaa-140001] LOG FASP Session Stop uuid=ffffffff-0000-0000-0000-000000000001 op=send status=failed errcode=36 errstr="Session data transfer timeout" local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
        2026-01-10 10:00:00.000 [aaaa-140001] LOG FASP Session Start uuid=ffffffff-0000-0000-0000-000000000002 op=send status=started local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
        2026-01-10 10:00:10.000 [aaaa-140001] LOG FASP Session Stop uuid=ffffffff-0000-0000-0000-000000000002 op=send status=failed errcode=36 errstr="Session data transfer timeout" local=10.0.0.1:52000 peer=10.0.0.3:33001 tcp_port=33001 os="Linux" ver=4.4.8 lic=10:1:1234
      EOF
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ascp.log')
        File.write(path, log_mixed)
        File.utime(Time.parse('2026-01-10 10:10:00'), Time.parse('2026-01-10 10:10:00'), path)

        now = Time.parse('2026-01-10 10:30:00')
        result = plugin.action_ascp_logs_health(paths: [path], now: now)
        expect(result.data).to(eq([
          {'status' => 'critical', 'component' => 'ascp logs', 'message' => '1 failed, 0 low efficiency in last 60 min'}
        ]))
      end
    end
  end
end
