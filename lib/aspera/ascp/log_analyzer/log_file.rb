# frozen_string_literal: true

# cspell:words nstore pids throughputs
require 'set'
require 'time'
require 'aspera/assert'
require 'aspera/ascp/log_analyzer/rules'
require 'aspera/ascp/log_analyzer/advice'
require 'aspera/ascp/log_analyzer/lines'
require 'aspera/ascp/log_analyzer/session'

module Aspera
  module Ascp
    class LogAnalyzer
      # Analysis of one ascp log file: sessions, snapshot periods and statistics
      class LogFile
        include Lines

        # Statistic => finding, when not zero
        FINDINGS = {
          stuck_nack:           'Retransmission requests (NACKs) were stuck in %d transfers: check the logs.',
          filename_too_long:    '%d files failed because their Windows path is longer than 260 characters.',
          gap:                  'ascp was blocked (IO wait) %d times.',
          gap_ssh:              'ascp was blocked (IO wait) %d times, with an SSH timeout.',
          buffer_died:          'The system ran out of buffer memory, and ascp exited, %d times.',
          timeout_died:         'A data or SSH timeout made ascp exit %d times.',
          decryption_died:      'A file decryption error made ascp exit %d times.',
          table_died:           'ascp exited at the end of %d sessions, without logging the statistics table.',
          died:                 'ascp exited, was blocked (IO wait), or stopped logging, %d times: check the logs.',
          win_clock:            'The clock of the system moves backwards: update the firmware of the motherboard.',
          vm:                   'This system may run on a VM, or have another clock problem, which affected %d transfers.',
          disable_reverse:      'Reverse path congestion inference skew affected %d transfers: check the logs, and disable it if appropriate.',
          vm_peer:              'Peers may run on a VM, or have another clock problem, which affected %d transfers.',
          ossl_modules_missing: 'The OpenSSL modules folder of ascp was not found in %d sessions (configuration, e.g. installation of the HTTP gateway): no effect unless an OpenSSL provider (e.g. FIPS) is needed.',
          change_event_failed:  'A change of the schedule of the virtual link capacity could not be registered in %d sessions: the schedule is not applied.'
        }.freeze
        # Totals of a snapshot period
        PERIOD_TOTALS = %i[rate rate_in rate_out calc calc_in calc_out target target_in target_out loss_in loss_out].freeze
        # A retry has the same values for these
        RETRY_KEYS = %i[peer op source dest].freeze

        attr_reader :path, :stats, :licenses, :first_time, :last_time, :thresholds

        # @param path       [String]       Log file
        # @param period     [Integer]      Snapshot period in seconds
        # @param zero_bytes [Boolean]      Include sessions without transferred bytes
        # @param mtu        [Integer, nil] MTU to use when not found in logs
        # @param thresholds [Hash]         Diagnostic thresholds
        # @param timezone   [String, nil]  Time zone of the log lines: `UTC` or `+HH:MM`. Time zone of the analyst if nil.
        def initialize(path, period: 60, zero_bytes: false, mtu: nil, thresholds: {}, timezone: nil)
          @path = path
          @timezone = timezone
          @period = period
          @zero_bytes = zero_bytes
          @mtu = mtu
          thresholds = thresholds.transform_keys(&:to_sym)
          unknown = thresholds.keys - DEFAULT_THRESHOLDS.keys
          Aspera.assert(unknown.empty?, type: ArgumentError) { "Unknown threshold: #{unknown.join(', ')}" }
          @thresholds = DEFAULT_THRESHOLDS.merge(thresholds)
          # PID => current Session of process
          @current = {}
          # All sessions, in order of creation
          @sessions = []
          # PID => user and version from configuration lines
          @config = Hash.new { |h, k| h[k] = {} }
          @stats = Hash.new(0)
          @stats[:errors] = Hash.new(0)
          @stats[:error_categories] = Hash.new(0)
          # Start time => {start:, stop:, slots: {Session => Hash}, totals: Hash}
          @periods = {}
          # Start time of the latest period with samples
          @bucket = nil
          # [license number, IP] => {product:, account:, os:}
          @licenses = {}
        end

        # Read and analyze the log file
        # @return [self]
        def analyze
          LogAnalyzer.read_lines(@path, Encoding::BINARY) { |line| parse_line(normalize(line)) }
          @sessions.each(&:evaluate_atm)
          @periods.sort.each { |time, period| end_of_period(time, period) }
          compute_statistics
          self
        end

        # @return [Array<Session>] transfer sessions to report, sorted by date
        def sessions
          transfer_sessions.select { |s| counted?(s) }.sort_by { |s| [s.num(:date), s[:user].to_s] }
        end

        # @return [Array<Hash>] one row per session
        def session_reports
          windows_log = @path.match?(/\w:/)
          sessions.map { |s| {'file' => @path}.merge(s.report(windows_log: windows_log)) }
        end

        class << self
          # @param stats [Hash] statistics of one or several log files
          # @return [Array<String>] findings from statistics
          def findings(stats)
            result = FINDINGS.filter_map do |key, message|
              if stats[key].positive?
                message.include?('%d') ? format(message, stats[key]) : message
              end
            end
            result.insert(1, 'The stuck retransmission requests may have been caused by high packet loss.') if stats[:stuck_nack_loss] > 0.4
            if stats[:smart_reset].positive?
              result.push("ascp reset the base RTT #{stats[:smart_reset]} times.#{' Consider changing the rtt_autocorrect parameters.' if stats[:smart_reset] > 100}")
            end
            result
          end
        end

        # @return [Array<Hash>] one row per multi-session transfer: sessions with the same transfer identifier
        def multi_sessions
          parallel = transfer_sessions.select { |s| s.num(:cluster_nodes) > 1 && s[:xfer_id] }
          parallel.group_by { |s| s[:xfer_id] }.map do |xfer_id, group|
            group = group.sort_by { |s| s.num(:cluster_node) }
            start = group.filter_map { |s| s[:start] }.min
            stop = group.filter_map { |s| s[:stop] || s[:last] }.max
            bytes = group.sum { |s| s.num(:tx_bytes) }
            {
              'file'              => @path,
              'transfer_id'       => xfer_id,
              'nodes'             => group.first[:cluster_nodes],
              'pids'              => group.map(&:pid),
              'peer'              => group.first[:peer],
              'direction'         => group.first.direction,
              'status'            => group.all? { |s| s[:status] == 'success' } ? 'success' : 'failed',
              'start'             => iso(start),
              'stop'              => iso(stop),
              'transmitted_bytes' => bytes,
              'average_rate'      => (bytes * 8 / (stop - start) if start && stop && stop > start)
            }.compact
          end
        end

        # @return [Array<Hash>] one row per diagnostic of sessions: id, severity, message, recommendation (if any)
        def diagnostics
          windows_log = @path.match?(/\w:/)
          sessions.flat_map do |s|
            s.report(windows_log: windows_log)
            s.diagnostics.map do |diagnostic|
              {'file' => @path, 'pid' => s.pid, 'session' => s[:uuid]}.compact.merge(diagnostic, 'recommendation' => RECOMMENDATIONS[diagnostic['id'].to_sym]).compact
            end
          end
        end

        # @return [Array<String>] ascp versions found in log, older than supported
        def old_versions
          transfer_sessions.filter_map { |s| s[:ver] if Session.version_older?(s[:ver], MIN_VERSION) }.uniq
        end

        # @return [Array<Hash>] one row per snapshot period
        def snapshots
          reported_periods.map do |time, period|
            t = period[:totals]
            row = {'file' => @path, 'time' => iso(time), 'sessions' => active_sessions(period[:slots])}
            if @period > 600 && period[:stop].to_i > period[:start].to_i
              duration = period[:stop] - period[:start]
              row.merge!('rate' => t[:data] / duration, 'rate_in' => t[:data_in] / duration, 'rate_out' => t[:data_out] / duration)
            else
              row.merge!(PERIOD_TOTALS.to_h { |k| [k.to_s, t[k]] })
            end
          end
        end

        # @return [Array<Hash>] one row per session in each snapshot period
        def snapshot_sessions
          reported_periods.flat_map do |time, period|
            period[:slots].sort_by { |session, _| session.pid.to_i }.filter_map do |session, slot|
              next if !@zero_bytes && slot[:net_rate].to_i.zero?
              progress = (100.0 * slot[:tx_bytes].to_i / session[:tx_bytes]).round(2) if session.flag?(:statistics) && session.num(:tx_bytes).nonzero?
              {
                'file'       => @path,
                'time'       => iso(time),
                'pid'        => session.pid,
                'session'    => session[:uuid],
                'rate'       => slot[:net_rate].to_i,
                'calculated' => slot[:avg_calc],
                'target'     => slot[:target_rate],
                'loss'       => slot[:loss_rate]&.round(2),
                'progress'   => progress,
                'direction'  => slot[:receiver] ? 'receive' : 'send',
                'constraint' => slot[:calc_1]&.join(',')
              }.compact
            end
          end
        end

        private

        # @return [Boolean] true if session is counted in statistics and reported
        def counted?(session)
          @zero_bytes || session.num(:tx_bytes).nonzero? || session[:status] == 'failed'
        end

        # @return [Session] current session of process
        def session(pid)
          @current[pid] || new_session(pid)
        end

        # A process starts a new session
        # @return [Session] new current session of process
        def new_session(pid)
          s = Session.new(pid, thresholds: @thresholds, timezone: @timezone)
          @sessions.push(s)
          @current[pid] = s
        end

        # A new process (configuration line) reuses the PID of a process whose session ended
        def check_pid_reuse(pid)
          current = @current[pid]
          new_session(pid) if current && (current.flag?(:statistics) || current[:stop])
        end

        # @return [Boolean] true if line is not relevant
        def ignored?(line, pid)
          return true unless line.match?(/\w/)
          return true if IGNORED_TEXTS.any? { |text| line.include?(text) } || line.match?(IGNORED_LINES)
          line.match?(OTHER_PROCESSES) && line.match?(/(?:#{OTHER_PROCESSES.source}).*?#{pid}/)
        end

        def parse_line(line)
          track_ascp(line)
          pid = line[PID, 1] or return
          time = parse_time(line[LINE_TIME, 1])
          if time
            @first_time = time if @first_time.nil? || time < @first_time
            @last_time = time if @last_time.nil? || time > @last_time
          end
          if line.include?('rex buffer full')
            session(pid).set(:rex_buffer_full)
            return
          end
          return if ignored?(line, pid)
          @stats[:win_clock] = 1 if line.include?('_usec_since') && line.match?(/get(?:nstore)?_usec_since/)
          process = line[PROCESS, 1]
          ascp = process.nil? || process.match?(ASCP_PROCESS)
          if ascp && line.include?('Configuration:') && (user = line[/Configuration:\s+using.*?user\s+(.*)/, 1])
            check_pid_reuse(pid)
            @config[pid][:user] = user
            session(pid)[:role] = user == '-' ? 'client' : 'server'
          end
          if ascp && line.include?('Initializing') && (version = line[/Initializing\s+FASP\s+version\s+((?:\d\.?)+)/, 1])
            check_pid_reuse(pid)
            session(pid).set(:transfer)
            @config[pid][:ver] = version
            # Authentication is logged after this line (the product name before or after it, depending on the version)
            @config[pid].delete(:auth)
            license(@config[pid], line)
          end
          return if line.include?('ascmd') || line.include?('aspshell')
          return unless ascp
          s = session(pid)
          if line.include?('ERR') && (error = line[LOG_ERROR, 1])
            s[:last_error] = error.strip
            s[:last_error_time] = time
          end
          s.set(:no_reverse_infer) if line.include?('Disabling reverse path congestion inference')
          if line.include?('Session') && (m = line.match(SESSION_START_STOP))
            s = session_line(s, pid, m[2].downcase.to_sym, m[1], line)
          end
          if time && s[:last] && time - s[:last] > 23
            gap = time - s[:last] - 21
            s[:gap] = gap if gap > s.num(:gap)
            s[:gap_last] = time
          end
          s[:last] = time
          s.session_params(Records.key_values(line[/Session\s+Params\s+(.*)/, 1] || line)) if line.include?('FASP Session Params')
          if line.include?(' DS Qs ')
            parse_ds_qs(pid, line)
          else
            apply_rules(s, line)
          end
        end

        # Apply the first matching rule of LINE_RULES
        def apply_rules(s, line)
          match, effects = LINE_RULES.find { |regexes, _| Array(regexes).all? { |re| line.match?(re) } }
          return unless effects
          effects[:call] ? send(effects[:call], s, line.match(Array(match).first)) : s.apply(effects)
        end

        # Maximum rate (bps, nil if unlimited) and expiry date (nil if none) of the license, from the `Initializing FASP version` line
        def license(config, line)
          mbps = line[LICENSE_RATE, 1]
          config[:license_rate] = mbps && (mbps.to_i * 1_000_000)
          config[:license_expires] = line[LICENSE_EXPIRES, 1]
        end

        # `Session Start` or `Session Stop` line
        # @return [Session] session of line: a new one if the process starts another session
        def session_line(s, pid, kind, stamp, line)
          fields = Records.key_values(line[/Session\s+(?:Start|Stop)\s+(.*)/, 1] || line)
          f = {
            uuid: fields['uuid'] || fields['id'], op: fields['op'], user: fields['user'],
            source: (fields['source']&.match?(/\s/) ? fields['source'].split.first : fields['source']),
            dest: (fields['dest']&.match?(/\s/) ? fields['dest'].split.first : fields['dest']),
            transport: (fields.key?('wss_port') ? 'wss' : ('ssh' if fields.key?('tcp_port'))),
            os: fields['os'], ver: fields['ver']&.split&.first, peeros: fields['peeros'], peerver: fields['peerver']&.split&.first, lic: fields['lic'], peerlic: fields['peerlic']
          }.compact
          if f[:uuid] && s[:uuid] && s[:uuid] != f[:uuid]
            role = s[:role]
            s = new_session(pid)
            s[:role] = role
          end
          s[:gap] = 0 if kind.eql?(:start)
          f[:local], f[:l_port] = address(fields['local'])
          f[:peer], f[:p_port] = address(fields['peer'])
          s.set(:transfer) if f[:peer]
          record_license(f[:lic], f[:local], f[:os])
          record_license(f[:peerlic], f[:peer], f[:peeros])
          s.session_line(kind, f, parse_time(stamp), @config[pid])
          s.stop_error(line, fields['status']) if kind.eql?(:stop)
          s
        end

        # @return [Array] IP and port from `IP:port`
        def address(value)
          m = value.to_s.match(/\A(.*):(\d+)\z/) or return [nil, nil]
          [m[1], m[2].to_i]
        end

        # @param license [String] product:account:license
        def record_license(license, ip, os)
          return if license.nil?
          product, account, number = license.split(':').map(&:to_i)
          @licenses[[number, ip]] = {product: product, account: account, os: os} unless product == 6
        end

        # --- LINE_RULES handlers ---

        def end_of_statistics(s, _m)
          s.set(:stats_end)
          s.delete(:last)
        end

        def transfer_stop(s, m)
          fields = Records.key_values(m[1])
          s[:uuid] ||= fields['uuid']
          @stats[:filename_too_long] += 1 if s.transfer_stop(fields['op'], fields['status'], fields['file'], fields['size'].to_i, fields['start_byte'].to_i, fields['errstr'])
        end

        def brtt_reset(s, _m)
          s.increment(:brtt_reset)
          @stats[:smart_reset] += 1
        end

        def rate_params(s, m)
          s.rate_params(m[2].to_i, m[3].to_i, m[4], by_peer: m[1].start_with?('Peer'))
        end

        def path_mtu(s, m)
          s[:mtu] = m[1].to_i
          s[:start_brtt] = m[2].to_i
        end

        def datagram_size(s, m)
          s[:mtu] = m[1].to_i
          s[:payload] = m[2].to_i
          s[:path_mtu] = m[3].to_i if m[3]
        end

        def conf_parse_error(s, m)
          s[:conf_parse] = m[1]
        end

        # Error when closing the SSH connection: keep the first one
        def ssh_disconnect_error(s, m)
          s[:ssh_disconnect] ||= m[0]
        end

        # Kernel line: error on the PID, and on PID - 11
        def segfault(s, _m)
          s[:error] = 'segfault'
          session((s.pid.to_i - 11).to_s)[:error] = 'segfault'
        end

        # No packet received: the receiver logs it from 2 seconds, the sender (no feedback of the receiver) from 3 seconds
        def no_data(s, m)
          sender = m[1] == 'Sender'
          key = sender ? :no_feedback : :no_data
          first = sender ? 3 : 2
          seconds = m[2].to_i
          s[key] = seconds if s.num(key) <= seconds
          s.increment(:"#{key}_total", seconds == first ? first : 1)
        end

        # Product name: `IBM Aspera High-Speed Transfer Server version 4.4.8.2596`, logged once by the process
        def product_name(s, m)
          @config[s.pid][:product_name] = m[1]
        end

        # Authentication with a token (`ASPERA_AUTH_TOKEN`), also when the line of the access key of the node storage follows
        def token_auth(s, _m)
          @config[s.pid][:auth] = 'token'
        end

        # Storage of a node access key, without token: authentication of the node user
        def node_auth(s, _m)
          @config[s.pid][:auth] ||= 'node'
        end

        def rex_timer_overflow(s, _m)
          s.increment(:rex_overflow)
        end

        def session_statistics(s, m)
          fields = Records.statistics_fields(m[1])
          s.set(:statistics)
          s[:effective_rate] = fields['effective_rate']
          progress = fields['progress'] || {}
          s[:tx_bytes] = progress['tx_bytes'].to_i
          s[:tx_time] = progress['tx_time'].to_i
          s[:retransmitted] = fields['solicited_rex']&.to_f
          s[:duplicates] = fields['rcvd_dups']&.to_f
          s[:efficiency] = fields['effective']&.to_f
          s[:control_loss] = %w[sndr rcvr rex].filter_map { |dir| (ctl = fields["#{dir}_ctl"]) && [dir, [ctl['sent'].to_i, ctl['lost_pct'].to_f]] }.to_h
        end

        # Cipher of server configuration replaces the requested one
        def cipher_override(s, m)
          s[:cipher_override] = m.captures.map { |id| CIPHERS.fetch(id.to_i, id) }
        end

        def resume_downgrade(s, m)
          s[:resume_downgrade] = m[1]
        end

        def job_size_change(s, m)
          s[:job_size] = m.captures.map(&:to_i)
        end

        # Virtual link: bandwidth limit shared by sessions
        def vlink_init(s, m)
          (s[:vlinks] ||= {})[m[1].to_i] = {'type' => m[2], 'capacity' => m[3].to_i}
        end

        # --- Snapshot periods ---

        def add_sample(_s, m)
          sample_match = m.string.match(SAMPLE) or return
          receiver = sample_match[3].eql?('Receiver')
          values = Records.group_fields(sample_match[4])
          data = (receiver ? RECEIVER_SAMPLE : SENDER_SAMPLE).transform_values { |path| values.dig(*path) }
          return if data.values_at(:tx_bytes, :written, :elapsed_us).any?(&:nil?)
          data[:disk_read_rate] = values['drate'] unless receiver
          session = session(sample_match[2])
          session[:dir] = receiver ? 'receive' : 'send'
          time = parse_time(sample_match[1]) or return
          data.merge!(time: time, receiver: receiver, elapsed: format('%.2f', data[:elapsed_us] / 1_000_000.0).to_f)
          bucket = (time / @period) * @period
          # The previous period is complete: ATM detection works on consecutive periods, in log order
          @sessions.each(&:evaluate_atm) if @bucket && bucket > @bucket
          @bucket = bucket if @bucket.nil? || bucket > @bucket
          period = (@periods[bucket] ||= {slots: {}})
          period[:start] ||= time
          period[:stop] = time
          @stats[:smart_reset] += data[:brtt_resets] if data[:brtt_resets].to_i.positive?
          first = !period[:slots].key?(session)
          slot = (period[:slots][session] ||= {})
          session.add_sample(data, slot, first: first, smart_reset: @stats[:smart_reset].positive?, mtu: @mtu)
          @stats[:last] = time
        end

        # Parse and accumulate a `DS Qs` line into the current session
        def parse_ds_qs(pid, line)
          text = line[/(?:Receiver|Sender)\s+DS\s+(.*)/, 1] or return
          queues = Records.queues_fields(text)
          qs = queues['Qs'] || {}
          qs['mgmt_backlog'] = queues['mgmt_backlog'].sum { |h| h['n'].to_i } if queues['mgmt_backlog']
          session(pid).add_ds_qs_sample(qs) unless qs.empty?
        end

        # @return [Integer] number of sessions in period
        def active_sessions(slots)
          @zero_bytes ? slots.size : slots.count { |_, slot| slot[:total1].to_i.positive? || slot[:total2].to_i.positive? }
        end

        # Totals of period, concurrency of sessions, maximum throughputs
        def end_of_period(date, period)
          slots = period[:slots]
          active = active_sessions(slots)
          totals = period[:totals] = Hash.new(0)
          slots.each_key do |s|
            slot = slots[s]
            s.set(:transfer)
            if slot[:elapsed2].to_f == slot[:elapsed1].to_f
              slots.delete(s)
              next
            end
            calc = slot[:calc_rate]
            slot[:avg_calc] = Session.average(calc).to_i
            slot[:avg_calc] = [slot[:avg_calc], calc.max].max if slot[:avg_calc] < slot[:net_rate].to_i
            way = slot[:receiver] ? :in : :out
            data = slot[:total2].to_i - slot[:total1].to_i
            if data.positive?
              totals[:"calc_#{way}"] += slot[:avg_calc]
              totals[:data] += data
              totals[:"data_#{way}"] += data
              totals[:"target_#{way}"] += slot[:target_rate].to_i
            end
            totals[:rate] += slot[:net_rate].to_i
            totals[:"rate_#{way}"] += slot[:net_rate].to_i
            totals[:"loss_#{way}"] += slot[:loss_speed].to_i
            s[:sess_min] = active if s.num(:sess_min).zero? || s[:sess_min] >= active
            if s.num(:sess_max) <= active
              s[:sess_max] = active
              s[:sess_max_time] = date
            end
          end
          totals[:calc] = totals[:calc_in] + totals[:calc_out]
          totals[:target] = totals[:target_in] + totals[:target_out]
          {max_sess: active, max_total: totals[:rate], max_out: totals[:rate_out], max_in: totals[:rate_in]}.each do |key, value|
            next if value <= @stats[key]
            @stats[key] = value
            @stats[:"#{key}_time"] = date
          end
        end

        # @return [Array] periods with traffic
        def reported_periods
          @periods.sort.select { |_, period| period[:totals] && (@zero_bytes || period[:totals][:rate_in].nonzero? || period[:totals][:rate_out].nonzero?) }
        end

        # --- Statistics ---

        def compute_statistics
          starts = transfer_sessions.filter_map { |s| s[:start] }
          transfer_sessions.each do |s|
            s.shared_link(starts)
            s.clear(:vm) if @stats[:smart_reset].positive?
            exit_category = s.check_exit(@stats[:last])
            @stats[exit_category] += 1 if exit_category
            cancelled = s[:error].to_s.match?(/cancelled/i)
            if counted?(s)
              @stats[:total_sessions] += 1
              case s[:status]
              when 'success' then @stats[:success] += 1
              when 'failed' then @stats[:failed] += 1 unless cancelled
              end
            end
            @stats[:http_fallback] += 1 if s.flag?(:http_fallback)
            if s.num(:gap).positive?
              @stats[:gap] += 1 unless s.flag?(:ssh_timeout)
              @stats[:gap_ssh] += 1 if s.flag?(:ssh_timeout)
            end
            if s[:error]
              @stats[:cancelled] += 1 if cancelled
              @stats[:errors][s[:error]] += 1 unless cancelled
            end
            @stats[:ossl_modules_missing] += 1 if s.flag?(:ossl_modules_missing)
            @stats[:change_event_failed] += 1 if s.flag?(:change_event_failed)
            @stats[:vm] += 1 if s.flag?(:vm)
            @stats[:vm_peer] += 1 if s.flag?(:vm_peer)
            @stats[:disable_reverse] += 1 if s.flag?(:disable_reverse) && !s.flag?(:no_reverse_infer)
            if s.stuck_nack?
              @stats[:stuck_nack] += 1
              @stats[:stuck_nack_loss] = [@stats[:stuck_nack_loss], s.num(:loss_rate)].max
            end
            @stats[:error_categories][s.error_category] += 1 if counted?(s) && s[:status] == 'failed' && s.error_category
          end
          link_retries
        end

        # @return [Array<Session>] all transfer sessions, including those not reported
        def transfer_sessions
          @sessions.select { |s| s.flag?(:transfer) }
        end

        # Link a failed session to the next session with same peer, direction, source and destination
        def link_retries
          groups = transfer_sessions.select { |s| s[:source] && s[:start] }.group_by { |s| RETRY_KEYS.map { |key| s[key] } }
          groups.each_value do |group|
            group.sort_by { |s| s[:start] }.each_cons(2) do |previous, current|
              next unless previous[:status] == 'failed' && current[:start] > previous[:start]
              next if previous[:xfer_id] && previous[:xfer_id] == current[:xfer_id]
              next if current[:start] - (previous[:stop] || previous[:last] || previous[:start]) > @thresholds[:retry_window]
              previous[:retried_by] = current.pid
              current[:retry_of] = previous.pid
              @stats[:retries] += 1
            end
          end
        end
      end
    end
  end
end
