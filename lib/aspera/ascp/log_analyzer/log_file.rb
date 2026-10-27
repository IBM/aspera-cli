# frozen_string_literal: true

# cspell:words MSGID nstore pids PROCID rsyslog throughputs
require 'set'
require 'time'
require 'aspera/ascp/log_analyzer/rules'
require 'aspera/ascp/log_analyzer/session'

module Aspera
  module Ascp
    class LogAnalyzer
      # Analysis of one ascp log file: sessions, snapshot periods and statistics
      class LogFile
        MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
        # Statistic => finding, when not zero
        FINDINGS = {
          stuck_nack:        'Retransmission requests (NACKs) were stuck in %d transfers: check the logs.',
          filename_too_long: '%d files failed because their Windows path is longer than 260 characters.',
          gap:               'ascp was blocked (IO wait) %d times.',
          gap_ssh:           'ascp was blocked (IO wait) %d times, with an SSH timeout.',
          buffer_died:       'The system ran out of buffer memory, and ascp exited, %d times.',
          timeout_died:      'A data or SSH timeout made ascp exit %d times.',
          decryption_died:   'A file decryption error made ascp exit %d times.',
          table_died:        'ascp exited at the end of %d sessions, without logging the statistics table.',
          died:              'ascp exited, was blocked (IO wait), or stopped logging, %d times: check the logs.',
          win_clock:         'The clock of the system moves backwards: update the firmware of the motherboard.',
          vm:                'This system may run on a VM, or have another clock problem, which affected %d transfers.',
          disable_reverse:   'Reverse path congestion inference skew affected %d transfers: check the logs, and disable it if appropriate.',
          vm_peer:           'Peers may run on a VM, or have another clock problem, which affected %d transfers.'
        }.freeze
        # Totals of a snapshot period
        PERIOD_TOTALS = %i[rate rate_in rate_out calc calc_in calc_out target target_in target_out loss_in loss_out].freeze
        # Maximum seconds between the end of a failed session and a new session, to consider it a retry
        RETRY_WINDOW = 3600
        # A retry has the same values for these
        RETRY_KEYS = %i[peer op source dest].freeze

        attr_reader :path, :stats, :licenses, :first_time, :last_time

        # @param path       [String]       Log file
        # @param period     [Integer]      Snapshot period in seconds
        # @param zero_bytes [Boolean]      Include sessions without transferred bytes
        # @param mtu        [Integer, nil] MTU to use when not found in logs
        def initialize(path, period: 60, zero_bytes: false, mtu: nil)
          @path = path
          @period = period
          @zero_bytes = zero_bytes
          @mtu = mtu
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
          # [license number, IP] => {product:, account:, os:}
          @licenses = {}
          # Sample lines of current period
          @pending = []
          # Sample line that starts the next period
          @held = nil
          @period_start = nil
          @period_end = nil
          @now = Time.now
          @time_cache = {}
        end

        # Read and analyze the log file
        # @return [self]
        def analyze
          File.foreach(@path, mode: 'rb') { |line| parse_line(normalize(line)) }
          process_samples unless @pending.empty?
          if @held
            start_period(@held)
            @pending.push(@held)
            process_samples
          end
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
              'start'             => (Time.at(start).iso8601 if start),
              'stop'              => (Time.at(stop).iso8601 if stop),
              'transmitted_bytes' => bytes,
              'average_rate'      => (bytes * 8 / (stop - start) if start && stop && stop > start)
            }.compact
          end
        end

        # @return [Array<Hash>] one row per diagnostic of sessions: id, severity, message
        def diagnostics
          windows_log = @path.match?(/\w:/)
          sessions.flat_map do |s|
            s.report(windows_log: windows_log)
            s.diagnostics.map { |diagnostic| {'file' => @path, 'pid' => s.pid, 'session' => s[:uuid]}.compact.merge(diagnostic) }
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
            row = {'file' => @path, 'time' => Time.at(time).iso8601, 'sessions' => active_sessions(period[:slots])}
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
                'time'       => Time.at(time).iso8601,
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
          s = Session.new(pid)
          @sessions.push(s)
          @current[pid] = s
        end

        # A new process (configuration line) reuses the PID of a process whose session ended
        def check_pid_reuse(pid)
          current = @current[pid]
          new_session(pid) if current && (current.flag?(:statistics) || current[:stop])
        end

        # Fix variants of log formats
        def normalize(line)
          if line.match?(/\A\d+-\d+-\d+T/)
            line = line.sub(/(\d+-\d+-\d+)T(\d+:\d+:\d+)(?:\.\d+)?[+-]\d+:\d+(.*)$/, '\1 \2 \3') # ISO 8601 with time zone (rsyslog)
            line = line.sub(/^(\d+-\d+-\d+)T(\d+:\d+:\d+)Z(.*)$/, '\1 \2 \3') # ISO 8601 UTC
          end
          line = line.sub(/(^.*?\s+ascp)\s+(\d+)\s+-\s+-(.*)/, '\1[\2]\3') if line.include?(' - -') # RFC 5424: APP-NAME PROCID MSGID
          line = line.sub(/^<\d+>\d\s+(.*)/, '\1') if line.start_with?('<') # RFC 5424: PRI VERSION
          line
        end

        # @return [Boolean] true if line is not relevant
        def ignored?(line, pid)
          return true unless line.match?(/\w/)
          return true if IGNORED_TEXTS.any? { |text| line.include?(text) } || line.match?(IGNORED_LINES)
          line.match?(OTHER_PROCESSES) && line.match?(/(?:#{OTHER_PROCESSES.source}).*?#{pid}/)
        end

        # @return [Integer, nil] epoch time of `Mon DD HH:MM:SS` (year guessed) or `YYYY-MM-DD HH:MM:SS`
        def parse_time(text)
          return if text.nil?
          @time_cache.clear if @time_cache.size > 10_000
          @time_cache[text] ||=
            if (m = text.match(/^(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)/)) && (month = MONTHS.index(m[1]))
              month += 1
              day = m[2].to_i
              year = month > @now.month || (month == @now.month && day > @now.day) ? @now.year - 1 : @now.year
              Time.local(year, month, day, m[3].to_i, m[4].to_i, m[5].to_i).to_i
            elsif (m = text.match(/^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)/))
              Time.local(*m.captures.map(&:to_i)).to_i
            end
        end

        # @return [Hash] key=value from line
        def key_values(line)
          line.scan(KEY_VALUE).to_h { |k, v| [k, v.delete_prefix('"').delete_suffix('"')] }
        end

        def parse_line(line)
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
          end
          return if line.include?('ascmd') || line.include?('aspshell')
          # Other processes (e.g. asperanoded): only time is used
          return next_period(line, time) unless ascp
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
          s.session_params(key_values(line)) if line.include?('FASP Session Params')
          # No rule applies to file queue samples
          apply_rules(s, line) unless line.include?(' DS Qs ')
          next_period(line, time)
        end

        # Apply the first matching rule of LINE_RULES
        def apply_rules(s, line)
          match, effects = LINE_RULES.find { |regexes, _| Array(regexes).all? { |re| line.match?(re) } }
          return unless effects
          effects[:call] ? send(effects[:call], s, line.match(Array(match).first)) : s.apply(effects)
        end

        # `Session Start` or `Session Stop` line
        # @return [Session] session of line: a new one if the process starts another session
        def session_line(s, pid, kind, stamp, line)
          fields = key_values(line)
          f = {
            uuid: fields['uuid'] || fields['id'], op: fields['op'], user: fields['user'], source: fields['source'], dest: fields['dest'],
            os: fields['os'], ver: fields['ver'], peeros: fields['peeros'], peerver: fields['peerver'], lic: fields['lic'], peerlic: fields['peerlic']
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

        def queue_sample(_s, m)
          @pending.push(m.string)
        end

        def transfer_stop(s, m)
          uuid, op, status, file, size, start_byte = m.captures
          s[:uuid] ||= uuid
          @stats[:filename_too_long] += 1 if s.transfer_stop(op, status, file, size.to_i, start_byte.to_i, m.string)
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

        def no_data(s, m)
          seconds = m[1].to_i
          s[:no_data] = seconds if s.num(:no_data) <= seconds
          s.increment(:no_data_total, seconds == 2 ? 2 : 1)
        end

        def session_statistics(s, m)
          s.set(:statistics)
          s[:effective_rate] = m[1]
          s[:tx_bytes] = m[2].to_i
          s[:tx_time] = m[3].to_i
          STATISTICS_RATES.each { |name, regex| s[name] = m.string[regex, 1]&.to_f }
          # Direction => [sent, lost percent]
          s[:control_loss] = m.string.scan(CONTROL_MESSAGES).to_h { |direction, sent, _received, lost| [direction, [sent.to_i, lost.to_f]] }
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

        # Process samples when the line is after the end of current period
        def next_period(line, time)
          if @held
            start_period(@held)
            @pending.push(@held)
            @held = nil
          elsif @period_start.nil?
            start_period(line)
          elsif time && time > @period_end
            last = @pending.last
            @held = @pending.pop if last && (last_time = parse_time(last[LINE_TIME, 1])) && last_time > @period_end
            process_samples unless @pending.empty?
          end
        end

        def start_period(line)
          @period_start = parse_time(line[STAMP, 1])
          @period_end = @period_start.to_i + @period
        end

        def process_samples
          period = (@periods[@period_start] ||= {slots: {}})
          @pending.each { |line| add_sample(line, period) }
          @pending.clear
          end_of_period(period)
        end

        # @return [Hash] values from sample line
        def sample_values(line)
          seen = Hash.new(0)
          values = {}
          line.scan(SAMPLE_GROUP) do |group, keys, numbers|
            seen[group] += 1
            group = "#{group}#{seen[group]}" if seen[group] > 1
            keys.split('/').zip(numbers.split('/')) { |key, value| values["#{group}.#{key}"] = value&.to_i }
          end
          values
        end

        def add_sample(line, period)
          m = line.match(SAMPLE) or return
          receiver = m[3].eql?('Receiver')
          values = sample_values(line)
          s = (receiver ? RECEIVER_SAMPLE : SENDER_SAMPLE).transform_values { |key| values[key] }
          return if s.values_at(:tx_bytes, :written, :elapsed_us).any?(&:nil?)
          s[:disk_read_rate] = line[DISK_READ_RATE, 1]&.to_i unless receiver
          session = session(m[2])
          session[:dir] = receiver ? 'receive' : 'send'
          time = parse_time(m[1]) or return
          s.merge!(time: time, receiver: receiver, elapsed: format('%.2f', s[:elapsed_us] / 1_000_000.0).to_f)
          period[:start] ||= time
          period[:stop] = time
          @stats[:smart_reset] += s[:brtt_resets] if s[:brtt_resets].to_i.positive?
          first = !period[:slots].key?(session)
          slot = (period[:slots][session] ||= {})
          session.add_sample(s, slot, first: first, smart_reset: @stats[:smart_reset].positive?, mtu: @mtu)
          @stats[:last] = time
        end

        # @return [Integer] number of sessions in period
        def active_sessions(slots)
          @zero_bytes ? slots.size : slots.count { |_, slot| slot[:total1].to_i.positive? || slot[:total2].to_i.positive? }
        end

        # Totals of period, concurrency of sessions, maximum throughputs
        def end_of_period(period)
          date = @period_start
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
          @sessions.each(&:evaluate_atm)
        end

        # @return [Array] periods with traffic
        def reported_periods
          @periods.sort.select { |_, period| period[:totals] && (@zero_bytes || period[:totals][:rate_in].nonzero? || period[:totals][:rate_out].nonzero?) }
        end

        # --- Statistics ---

        def compute_statistics
          transfer_sessions.each do |s|
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
              next if current[:start] - (previous[:stop] || previous[:last] || previous[:start]) > RETRY_WINDOW
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
