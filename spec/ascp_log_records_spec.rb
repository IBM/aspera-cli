# frozen_string_literal: true

# cspell:ignore abrtxfer blks drate dups instru mgmt rcvd rcvD rcvr rexreqs sndr userid xmit xmtD
# Unit tests for Aspera::Ascp::LogAnalyzer::Records: lines of `ascp` logs parsed into records.

require 'bundler/setup'
require 'tmpdir'
require 'aspera/ascp/log_analyzer'
require 'aspera/schema/validator'

RSpec.describe(Aspera::Ascp::LogAnalyzer::Records) do
  rx = '11111111-2222-3333-4444-555555555555'
  tx = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
  session_fields = ->(uuid, op, status) do
    "uuid=#{uuid} op=#{op} status=#{status} source=/src/my file dest=/dst source_prefix=- local=10.0.0.1:33001 peer=10.0.0.2:51000 tcp_port=33001 " \
      'os="Linux 5.14" ver=4.4.8.2596 b12cd13 lic=10:1:1234 peeros="Darwin 24.0" peerver=4.4.5.123 69b1c15a9 peerlic=6:1:1 ' \
      'proto_sess=20003 proto_udp=20000 proto_bwmeas=20000 proto_data=2000f'
  end
  lines = [
    ['10:00:00', '1a2b', "LOG FASP Session Start #{session_fields.call(rx, 'recv', 'started')}"],
    ['10:00:00', '1a2b', "LOG FASP Session Params uuid=#{rx} userid=0 user=\"xfer\" targetrate=100000000 minrate=0 rate_policy=fair cipher=aes-128-gcm resume=1 " \
      'cookie="<COOKIE>" vl_proto_ver=1  peer_vl_proto_ver=1 range=0-0 exclude_older/newer_than=10/20 xfer_id=99999999-8888-7777-6666-555555555555 job_id=-'],
    ['10:00:00', '1a2b', "LOG FASP Transfer Start uuid=#{rx} op=recv status=started file=\"/dst/my file\" size=20000000 start_byte=0 rate=100.00Mbps loss=0.00 rexreqs=0 overhead=0"],
    ['10:00:20', '1a2b', 'LOG Receiver bl t/o/r/d/ts/c/h=9272/8606/624/42/0/8929/9231 rex_rtt l/h/s/o=50/91/70/96 ooo_rtt l/h/s/o=0/0/56/64 ' \
      'rate_rtt b/l/h/s/r/f=44/44/115/66/0/1 ctl bm/bs=0/0 rex n/s/q/v/a/r=0/668/9/0/0/0 bl l/d/o/r/a/x/dl/df/dm/ds=624/42/0/0/0/0/0/0/0/0 ' \
      'disk l/h/b=0/0/0 vlink lq/lo/rq/ro=0/0/0/0 rate t/m/c/n/vl/vr/r=100000000/0/80000000/80000000/100000000/100000000/100000000 ' \
      'prog t/f/e=12995840/12995840/1000012 rcvD=0'],
    ['10:00:20', '1a2b', 'LOG Receiver DS Qs ds/n/rq/pa/ao/ap/rd/ru/no/po/pc/do/tv/sv=1/0/0/0/0/0/0/1/0/0/0/0/0/0 Rs i/o=1/1 mgmt backlog i/s/n = 0/3/0 1/4/12'],
    ['10:00:30', '1a2b', "LOG FASP Transfer Stop uuid=#{rx} op=recv status=success file=\"/dst/my file\" size=20000000 start_byte=0 rate=1.78Mbps elapsed=29.50s " \
      'loss=2.30 rexreqs=17 overhead=3 ol_legal_hold=on ol_retention=[mode=governance,until=2027-01-01T00:00:00Z]'],
    ['10:00:30', '1a2b', "LOG FASP Session Stop #{session_fields.call(rx, 'recv', 'failed errcode=27 errstr="Peer aborted session" [peer errcode=36 errstr="Session data transfer timeout"]')}"],
    ['10:00:30', '1a2b', "LOG FASP Session Statistics [Receiver] id=#{rx} delay=45ms rex_delay=69ms ooo_delay=64ms solicited_rex=2.98% rcvd_rex=2.29% rcvd_dups=0.48% " \
      'ave_xmit_rate 144.90Mbps effective=97.03% effective_rate=140.60Mbps (detail: good_blks 744825 bl_total 748441 bl_orig 727577 bl_rex 17151 dup_blks 3616 ' \
      'dup_last_blks 0 drop_blks_xnf 97) (sndr ctl: sent 68 rcvd 67 lost 1 lost 1.47%) (rcvr ctl: sent 2148 rcvd 2145 lost 3 lost 0.14%) ' \
      '(rex  ctl: sent 358 rcvd 358 lost 0 lost 0.00%) (progress: tx_bytes 1048576000 file_bytes 1048576000 tx_time 61669078) ' \
      'rex_xmit_blks 22877  xmit_total 767605 rex_xmit_pct 2.98%'],
    ['10:01:00', '2c3d', "LOG FASP Session Start #{session_fields.call(tx, 'send', 'started')}"],
    ['10:01:01', '2c3d', 'LOG Sender bl t/o/r/dl/c/h=100/90/10/0/80/100 ctl bm/bs=0/0 rex b/r/n=10/2/0 r_ott q/s/n=5/3/40 ' \
      'rate t/m/c/rc/n/vl/vr/r=20000000/0/15000000/15000000/15000000/20000000/20000000/20000000 prog t/f/e=140800/140800/1000000 xmtD=0 drate=10000000'],
    ['10:01:01', '2c3d', 'LOG Sender DS Qs ds/re/a/d/ao/eo/n/ap/rq/rd/ru/cl/di/do=1/0/0/0/0/0/0/0/0/0/1/0/0/0 Rs o/i=1/1 mgmt backlog i/s/n = 0/3/0'],
    ['10:01:05', '2c3d', "LOG FASP Session Stop #{session_fields.call(tx, 'send', 'success')}"],
    ['10:01:05', '2c3d', "LOG FASP Session Statistics [Sender] id=#{tx} delay=4ms rex_delay=6ms solicited_rex=2.59% unsolicited_rex=0.00% ave_xmit_rate 877.88Mbps " \
      'effective=97.41% effective_rate=855.15Mbps (detail: good_blks 76 bl_total 78 bl_orig 76 bl_rex 2 dup_last_blks 0) (sndr ctl: sent 1051 rcvd 1015 lost 36 lost 3.43%) ' \
      '(rcvr ctl: sent 173671 rcvd 173670 lost 1 lost 0.00%) (rex  ctl: sent 16268 rcvd 16266 lost 2 lost 0.01%) ' \
      '(progress: tx_bytes 107374182400 file_bytes 107374182400 tx_time 1032990989) (estimate transfer size: 107374182400 bytes)  ' \
      'sess->instru.num_rex_xfer_not_found 0 sess->instru.num_rex_abrtxfer_not_found 1']
  ]
  log = lines.map { |time, pid, text| "2026-01-10 #{time}.000 [#{pid}-140001] #{text}\n" }.join

  def with_log(content, name: 'aspera-scp-transfer.log')
    Dir.mktmpdir do |dir|
      path = File.join(dir, name)
      File.write(path, content)
      yield(path, dir)
    end
  end

  def records(content)
    with_log(content) { |path| return described_class.new(path).parse }
  end

  it 'merges a sample line with its DS Qs line: groups and fields of the log' do
    sample = records(log).samples.find { |s| s['side'] == 'Receiver' }
    expect(sample).to(include('pid' => '1a2b', 'uuid' => rx, 'rcvD' => 0))
    expect(sample['time']).to(start_with('2026-01-10T10:00:20'))
    expect(sample['bl']).to(eq('t' => 9272, 'o' => 8606, 'r' => 624, 'd' => 42, 'ts' => 0, 'c' => 8929, 'h' => 9231))
    expect(sample['bl2']).to(include('l' => 624, 'd' => 42))
    expect(sample['rate']).to(include('t' => 100_000_000, 'c' => 80_000_000, 'n' => 80_000_000))
    expect(sample['DS']['Qs']).to(include('ds' => 1, 'ru' => 1, 'no' => 0))
    expect(sample['DS']['Rs']).to(eq('i' => 1, 'o' => 1))
    expect(sample['DS']['mgmt_backlog']).to(eq([{'i' => 0, 's' => 3, 'n' => 0}, {'i' => 1, 's' => 4, 'n' => 12}]))
  end

  it 'reads sender samples: fields outside groups' do
    sample = records(log).samples.find { |s| s['side'] == 'Sender' }
    expect(sample).to(include('uuid' => tx, 'xmtD' => 0, 'drate' => 10_000_000))
    expect(sample['rate']).to(include('rc' => 15_000_000))
    expect(sample['r_ott']).to(eq('q' => 5, 's' => 3, 'n' => 40))
    expect(sample['DS']['Rs']).to(eq('o' => 1, 'i' => 1))
  end

  it 'merges the lines of a session: Session Stop replaces values of Session Start' do
    session = records(log).sessions.find { |s| s['uuid'] == rx }
    expect(session).to(include(
      'pid' => '1a2b', 'op' => 'recv', 'status' => 'failed', 'errcode' => 27, 'errstr' => 'Peer aborted session',
      'peer_errcode' => 36, 'peer_errstr' => 'Session data transfer timeout',
      'source' => '/src/my file', 'ver' => '4.4.8.2596 b12cd13', 'peerver' => '4.4.5.123 69b1c15a9', 'proto_sess' => '20003', 'proto_data' => '2000f',
      'user' => 'xfer', 'targetrate' => 100_000_000, 'resume' => 1, 'peer_vl_proto_ver' => 1, 'range' => '0-0',
      'exclude_older_than' => 10, 'exclude_newer_than' => 20, 'job_id' => '-'
    ))
    expect(session['start']).to(start_with('2026-01-10T10:00:00'))
    expect(session['stop']).to(start_with('2026-01-10T10:00:30'))
    expect(session).not_to(have_key('cookie'))
  end

  it 'reads session statistics: numbers without unit, groups' do
    sessions = records(log).sessions
    receiver = sessions.find { |s| s['uuid'] == rx }
    expect(receiver).to(include(
      'delay' => 45, 'solicited_rex' => 2.98, 'ave_xmit_rate' => 144_900_000, 'effective' => 97.03, 'effective_rate' => 140_600_000,
      'rex_xmit_blks' => 22_877, 'xmit_total' => 767_605, 'rex_xmit_pct' => 2.98
    ))
    expect(receiver['detail']).to(include('good_blks' => 744_825, 'drop_blks_xnf' => 97))
    expect(receiver['sndr_ctl']).to(eq('sent' => 68, 'rcvd' => 67, 'lost' => 1, 'lost_pct' => 1.47))
    expect(receiver['rex_ctl']).to(include('lost_pct' => 0.0))
    expect(receiver['progress']).to(eq('tx_bytes' => 1_048_576_000, 'file_bytes' => 1_048_576_000, 'tx_time' => 61_669_078))
    expect(receiver).not_to(have_key('id'))
    sender = sessions.find { |s| s['uuid'] == tx }
    expect(sender).to(include('status' => 'success', 'unsolicited_rex' => 0.0, 'estimate_transfer_size' => 107_374_182_400, 'num_rex_abrtxfer_not_found' => 1))
  end

  it 'merges Transfer Start and Transfer Stop of a file' do
    transfers = records(log).transfers
    expect(transfers.size).to(eq(1))
    expect(transfers.first).to(include(
      'uuid' => rx, 'pid' => '1a2b', 'op' => 'recv', 'status' => 'success', 'file' => '/dst/my file', 'size' => 20_000_000,
      'rate' => 1_780_000, 'elapsed' => 29.5, 'loss' => 2.3, 'rexreqs' => 17, 'overhead' => 3,
      'ol_legal_hold' => 'on', 'ol_retention' => {'mode' => 'governance', 'until' => '2027-01-01T00:00:00Z'}
    ))
    expect(transfers.first['start']).to(start_with('2026-01-10T10:00:00'))
  end

  it 'reads syslog lines' do
    syslog = "Oct 26 09:35:57 host ascp[62699]: LOG Receiver bl t/o/r/d/ts/c/h=1/1/0/0/0/0/0 prog t/f/e=10/10/20 rcvD=0\n" \
      "Oct 26 09:35:57 host asperanoded[100]: LOG Receiver bl t/o/r/d/ts/c/h=2/2/0/0/0/0/0\n"
    samples = records(syslog).samples
    expect(samples.size).to(eq(1))
    expect(samples.first).to(include('pid' => '62699', 'side' => 'Receiver', 'bl' => include('t' => 1), 'prog' => {'t' => 10, 'f' => 10, 'e' => 20}))
  end

  it 'adds the log file to records when several log files are read' do
    with_log(log) do |path, dir|
      other = File.join(dir, 'other.log')
      File.write(other, log)
      expect(described_class.list(:transfers, [path]).first).not_to(have_key('log_file'))
      expect(described_class.list(:transfers, [dir]).map { |t| t['log_file'] }).to(contain_exactly(path, other))
    end
  end

  it 'produces records described by the schema' do
    parsed = records(log)
    described_class::SCHEMAS.each do |kind, schema|
      rows = parsed.public_send(kind)
      expect(rows).not_to(be_empty)
      rows.each { |row| expect(Aspera::Schema::Validator.instance.errors(row, schema)).to(be_empty, "#{kind}: #{row}") }
    end
  end

  it 'types values with the schema, and numbers of fields not in the schema' do
    expect(described_class.value('2000f', 'string')).to(eq('2000f'))
    expect(described_class.value('1.5Gbps', 'integer')).to(eq(1_500_000_000))
    expect(described_class.value('12.50%', 'number')).to(eq(12.5))
    expect(described_class.value('n/a', 'integer')).to(eq('n/a'))
    expect(described_class.value('42', nil)).to(eq(42))
    expect(described_class.value('4.2', nil)).to(eq(4.2))
    expect(described_class.value('42ms', nil)).to(eq('42ms'))
  end
end
