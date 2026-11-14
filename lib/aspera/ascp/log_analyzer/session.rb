# frozen_string_literal: true

# cspell:words commify Isilon nacks nohear onefs overdriven
require_relative '../../assert'
require_relative '../session_errors'
require_relative 'diagnostics'
require 'set'
require 'time'

module Aspera
  module Ascp
    class LogAnalyzer
      # Data of one ascp session (process), collected from its log lines and its samples
      class Session
        # Calculated rates (bps) of 1 packet per second, for various payload sizes: maximum disk throttling
        DISK_THROTTLE_RATES = [11_584, 11_712, 11_936, 7_824, 8_048, 3_840, 4_064, 2_144, 2_368].freeze
        DEFAULT_MTU = 1492
        # Sender (ascp 4): limit of the receiver => sample values
        RECEIVER_CAUSES = {'network' => %i[peer_net_rate], 'disk' => %i[peer_disk_rate], 'vlink' => %i[peer_vlink_local peer_vlink_remote]}.freeze
        # Control messages in `Session Statistics`: direction => description
        CONTROL_DIRECTIONS = Diagnostics::CONTROL_DIRECTIONS
        # Constraint on the rate => series of its sample values
        CONSTRAINT_SERIES = {'network' => :network, 'disk' => :disk, 'vlink_local' => :vlink_local, 'vlink_remote' => :vlink_remote, 'Receiver' => :calc}.freeze
        # Receiver: constraint => sample value
        RECEIVER_CONSTRAINTS = {'network' => :net_rate, 'disk' => :disk_rate, 'vlink_local' => :vlink_local, 'vlink_remote' => :vlink_remote}.freeze
        # Receiver: sample value => series, kept after 20 seconds of transfer
        RECEIVER_SERIES = {srtt: :srtt, rex_srtt: :rex_srtt, rtt_high: :rtt, net_rate: :network, vlink_local: :vlink_local, vlink_remote: :vlink_remote, disk_rate: :disk}.freeze
        RESUME = {0 => 'Do not resume', 1 => 'With file attribute check', 2 => 'With sparse checksum', 3 => 'With full checksum'}.freeze
        OVERWRITE = {255 => 'Always overwrite', 1 => 'If source different', 3 => 'If source different and newer', 63 => 'Never overwrite'}.freeze
        # Rate policy in log lines => policy name
        POLICIES = {'0' => 'fixed', '1' => 'fair', '2' => 'low', 'adapt' => 'fair', 'trickle' => 'low'}.freeze
        # Flag => severity and message of diagnostic (identifier: name of flag)
        FLAG_DIAGNOSTICS = Diagnostics::FLAG_DIAGNOSTICS

        class << self
          # @return [Float] mean of values, 0 if none
          def average(values)
            values.empty? ? 0 : values.sum.fdiv(values.size)
          end

          # @return [Numeric] median of values, 0 if none
          def median(values)
            return 0 if values.empty?
            sorted = values.sort
            mid = sorted.size / 2
            sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
          end

          # @return [Float] population standard deviation of values, 0 if none
          def standard_deviation(values)
            return 0 if values.empty?
            mean = average(values)
            Math.sqrt(values.sum { |v| (v - mean)**2 } / values.size)
          end

          # @return [String] integer with thousands separators, for messages
          def commify(value)
            value.to_i.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')
          end

          # @return [Boolean] true if version is known and older than reference
          def version_older?(version, reference)
            number = version.to_s[/\A\d+(?:\.\d+)*/] or return false
            Gem::Version.new(number) < Gem::Version.new(reference)
          end

          # @return [Integer, nil] rate in bps, from text with unit, e.g. `3.33Mbps`
          def rate_bps(text)
            m = text.to_s.match(/\A(\d+\.\d+)([A-Za-z]+)/) or return
            (m[1].to_f * {'Kbps' => 1e3, 'Mbps' => 1e6, 'Gbps' => 1e9}.fetch(m[2], 1)).round
          end
        end

        attr_accessor :pid
        # Files transferred: name => {op:, size:, status:, error:}
        attr_reader :files
        # Diagnostics of last report: {id, severity, message}
        attr_reader :diagnostics, :thresholds, :data, :flags, :series, :constraint, :constraints, :params, :sizes, :receiver_causes, :rate_samples, :ds_qs_samples, :timezone

        # @param pid        [String] Process identifier
        # @param thresholds [Hash]   Diagnostic thresholds
        # @param timezone   [String, nil] Time zone of the reported times: `UTC` or `+HH:MM`. Time zone of the analyst if nil.
        def initialize(pid, thresholds: {}, timezone: nil)
          @pid = pid
          @timezone = timezone
          thresholds = thresholds.transform_keys(&:to_sym)
          unknown = thresholds.keys - DEFAULT_THRESHOLDS.keys
          Aspera.assert(unknown.empty?, type: ArgumentError) { "Unknown threshold: #{unknown.join(', ')}" }
          @thresholds = DEFAULT_THRESHOLDS.merge(thresholds)
          @data = {}
          @flags = Set.new
          @series = Hash.new { |h, k| h[k] = [] }
          # Constraint name => {min_rate:, base_rtt:, smooth_rtt:}
          @constraint = {}
          # Names of constraints that limited the rate
          @constraints = Set.new
          # Changes of rate parameters during session
          @params = nil
          @files = {}
          # Sizes of transferred files
          @sizes = []
          # Detection of ATM / tail-drop rate limiting
          @atm = nil
          # Detection of stuck NACKs on sender
          @send_nack = nil
          # Detection of clock problems on peer
          @vm = nil
          # Sender: limit of the receiver => number of samples
          @receiver_causes = Hash.new(0)
          # Rate samples after the delay: [elapsed time (us), time, bps], receiver network rate or sender calculated rate
          @rate_samples = []
          # File-queue stats: one hash per DS Qs sample, keys 'ao', 'ap', 'mgmt_backlog'
          @ds_qs_samples = []
        end

        def [](key)
          @data[key]
        end

        def []=(key, value)
          @data[key] = value
        end

        def delete(key)
          @data.delete(key)
        end

        # @return [Numeric] value, 0 if not set
        def num(key)
          @data[key] || 0
        end

        def increment(key, value = 1)
          @data[key] = num(key) + value
        end

        # @return [Boolean] true if any of the flags is set
        def flag?(*names)
          names.any? { |n| @flags.include?(n) }
        end

        def set(*names)
          @flags.merge(names)
        end

        def clear(*names)
          @flags.subtract(names)
        end

        # Apply effects of a rule (see LINE_RULES), unless cancelled by a flag
        def apply(effects)
          return if effects[:unless] && flag?(*effects[:unless])
          set(*effects[:set]) if effects[:set]
          clear(*effects[:clear]) if effects[:clear]
          @data[:error] = effects[:error] if effects[:error]
          @data[:status] = effects[:status] if effects[:status]
        end

        # Apply the first rule whose flags are all set
        # @param rules [Array] list of [flags, effects]
        def apply_first(rules)
          rule = rules.find { |flags, _| flags.all? { |f| flag?(f) } }
          apply(rule.last) if rule
        end

        # Information from a `Session Start` or `Session Stop` line
        # @param kind [Symbol] :start or :stop
        # @param f [Hash] values from line
        # @param time [Integer, nil] time of line
        # @param config [Hash] user and version from configuration lines
        def session_line(kind, f, time, config)
          %i[uuid op user source dest local os ver peeros peerver transport].each { |k| @data[k] = f[k] if f[k] }
          if f[:lic]
            @data[:product] = f[:lic].split(':').first.to_i
            @data[:role] = 'client' if [6, 7].include?(@data[:product])
          end
          if f[:peerlic]
            @data[:peer_product] = f[:peerlic].split(':').first.to_i
            @data[:role] = 'server' if @data[:peer_product] == 6
          end
          @data[:user] ||= config[:user]
          @data[:role] = 'client' if config[:user] && config[:user] != '-' && @data[:user] && !config[:user].match?(/#{Regexp.escape(@data[:user])}/i)
          if f[:l_port]
            @data[:start_l_port] = @data[:l_port] if kind.eql?(:stop) && @data[:l_port] && @data[:l_port] != f[:l_port]
            @data[:l_port] = f[:l_port]
          end
          @data[:peer] ||= f[:peer]
          @data[:p_port] = f[:p_port] if f[:p_port]
          @data[:ver] ||= config[:ver]
          @data[:product_name] ||= config[:product_name]
          @data[:auth] ||= config[:auth]
          @data[:license_rate] ||= config[:license_rate]
          @data[:license_expires] ||= config[:license_expires]
          @data[kind] = time
          @data[:date] = @data[:stop] || @data[:start]
        end

        # Values from `Session Params` line
        # @param fields [Hash] key=value from line
        def session_params(fields)
          SESSION_PARAMS.each do |name, key|
            next unless fields.key?(name)
            value = fields[name]
            @data[key] = value.match?(/\A\d+\z/) && key != :user ? value.to_i : value
          end
          @data[:policy] = POLICIES.fetch(@data[:policy], @data[:policy]) if @data[:policy]
          # `proxy_ip=-`: no proxy
          @data[:proxy] = fields['proxy_ip'] if fields['proxy_ip'] && fields['proxy_ip'] != '-'
          @data[:fips] = fields['fips_enabled'] == 'yes' if fields.key?('fips_enabled')
        end

        # Error and status of `Session Stop` line
        def stop_error(line, status)
          e1, e2 = line.match(ERRSTR)&.captures
          error =
            if !e2.to_s.empty? then e2 == 'Undefined' ? e1 : e2
            elsif e1.to_s.empty? then nil
            elsif e1 == 'Undefined' && flag?(:invalid_conf_file) then 'Invalid Configuration File'
            elsif e1 == 'Undefined' && flag?(:invalid_argument) then 'Invalid argument'
            else e1
            end
          @data[:error] = error if error
          # Code of the error retained (local or peer)
          code = line.scan(ERRCODE).to_h { |number, text| [text, number.to_i] }[error]
          @data[:error_code] = code if code&.nonzero?
          @data[:status] = 'success' if status == 'success'
          return unless status == 'failed'
          if e2.to_s.empty? && e1 == 'Undefined'
            apply_first(UNDEFINED_ERROR_RULES)
            @data[:error] = 'Unable to bind to UDP socket' if flag?(:bind_udp_socket_failed)
          end
          apply_first(ERROR_REFINEMENTS[error]) if ERROR_REFINEMENTS.key?(error)
          @data[:status] = 'failed' unless @data[:status] == 'success'
        end

        # Rate parameters changed
        # @param by_peer [Boolean] rate parameters requested by peer
        def rate_params(t_rate, m_rate, policy, by_peer:)
          @params[:multiple] = true if @params
          @params&.delete(:peer) unless by_peer
          policy = POLICIES.fetch(policy, policy)
          change_param(:policy, policy) unless @data[:policy] == policy
          change_param(:target_rate, t_rate) unless num(:target_rate) == t_rate
          change_param(:min_rate, m_rate) unless num(:min_rate) == m_rate
          @params[:peer] = true if by_peer && @params
        end

        # `Transfer Stop` line
        # @return [Boolean] true if file failed because its name is too long for Windows
        def transfer_stop(op, status, file, size, start_byte, errstr = nil)
          too_long = false
          case status
          when 'success'
            if start_byte == size
              increment(:files_skipped)
            else
              size -= start_byte
              increment(:files_success)
              @sizes.push(size)
            end
          when 'failed'
            increment(:files_failed)
            too_long = file.length >= 240 && (file.match?(/\w:/) || windows?)
            increment(:filename_too_long) if too_long
          else
            return false
          end
          increment(:transfer_stop_count)
          entry = (@files[file] ||= {})
          error = errstr&.match?(/errstr="./) ? errstr[/errstr="(.*?)"/, 1] : errstr
          entry[:error] = error if status == 'failed' && error && !error.empty?
          entry.merge!(op: op, size: size, status: status)
          too_long
        end

        # Process a `bl` sample (Receiver or Sender)
        # @param s [Hash] values of sample, see RECEIVER_SAMPLE, SENDER_SAMPLE
        # @param slot [Hash] data of this session in the current snapshot period
        # @param first [Boolean] first sample of this session in the period
        # @param smart_reset [Boolean] base RTT is reset by ascp
        # @param mtu [Integer, nil] MTU to use when not found in logs
        def add_sample(s, slot, first:, smart_reset:, mtu:)
          receiver = s[:receiver]
          elapsed = s[:elapsed]
          @data[:elapsed_start] = s[:elapsed_us] if num(:elapsed_start).zero?
          @data[:elapsed_us] = s[:elapsed_us]
          if receiver
            increment(:brtt_reset, s[:brtt_resets]) if s[:brtt_resets].to_i.positive?
            RECEIVER_SERIES.each { |key, series| @series[series].push(s[key].to_i) } if elapsed > 20
            if s[:net_rate].to_i == s[:calc_rate].to_i
              queue = s[:srtt].to_i - s[:brtt].to_i
              @data[:max_queue] = queue if @data[:max_queue].nil? || queue > @data[:max_queue]
            end
          else
            check_sender_nacks(s)
            @data[:disk_read_rate] = s[:disk_read_rate] if s[:disk_read_rate].to_i.positive?
          end
          @data[:start_block] = s[:blocks] if num(:start_block).zero?
          @data[:mtu] = format('%.0f', s[:tx_bytes].fdiv(s[:blocks]) + 40).to_i if num(:mtu) <= 8000 && s[:blocks].to_i.positive? && s[:tx_bytes].fdiv(s[:blocks]) > 8000
          @data[:mtu] = mtu if mtu && !@data[:payload]
          @data[:mtu] ||= DEFAULT_MTU
          t_bits = s[:blocks].to_i * @data[:mtu] * 8
          @data[:target_rate] = s[:target_rate] if num(:target_rate).zero?
          @data[:min_rate] = s[:min_rate]
          @series[:calc].push(s[:calc_rate].to_i)
          @rate_samples.push([s[:elapsed_us], s[:time], (receiver ? s[:net_rate] : s[:calc_rate]).to_i]) if elapsed > @thresholds[:rate_decline_delay]
          increment(:disk_max) if DISK_THROTTLE_RATES.include?(s[:calc_rate])
          check_stuck_nack(s)
          check_stuck_rex(s) if receiver
          @data[:tx_bytes] = s[:tx_bytes] if s[:tx_bytes] > num(:tx_bytes)
          log_brtt(s, elapsed, first: first, smart_reset: smart_reset)
          if first
            slot.merge!(
              total1: t_bits, blocks1: s[:blocks], loss1: s[:lost], orig1: s[:orig], rex1: s[:rex], elapsed1: elapsed, date1: s[:time],
              target_rate: s[:target_rate], calc_rate: [s[:calc_rate].to_i], receiver: receiver
            )
          else
            (@atm ||= {})[:samples] = @atm[:samples].to_i + 1
            slot[:calc_rate].push(s[:calc_rate].to_i)
            update_slot(s, slot, t_bits, elapsed, receiver)
          end
          @data[:elapsed] = elapsed
          check_high_rtt(s) if receiver
          if s[:written].nonzero?
            rate_constraint(s, slot, elapsed, receiver, first)
            update_calc_points(s[:calc_rate].to_i, t_bits, elapsed)
            if receiver
              @data[:recv_max] = [num(:recv_max), calc_speed].max
              check_atm(s, t_bits, elapsed) unless first
            else
              detect_peer_vm(s) unless first
              @data[:send_max] = [num(:send_max), calc_speed].max
            end
          end
          @atm = (@atm || {}).merge(total0: t_bits, elapsed0: elapsed, loss0: s[:lost].to_i, orig0: s[:orig].to_i) if first
          if receiver
            buffers = [s[:ring_high], s[:ring_full]].find { |b| b.to_i >= 5 }
            @data[:buffers] = buffers if buffers && buffers > num(:buffers)
            @data[:ooo] = s[:ooo].to_i.fdiv(s[:blocks]) if s[:blocks].to_i.nonzero?
            @data[:loss_rate] = s[:lost].to_i.fdiv(s[:lost].to_i + s[:orig].to_i) if (s[:lost].to_i + s[:orig].to_i).nonzero?
          elsif (!first || s[:written].nonzero?) && s[:blocks].to_i.nonzero?
            @data[:loss_rate] = s[:rex].to_i.fdiv(s[:blocks])
          end
        end

        # Accumulate file-queue statistics from one `DS Qs` sample
        # @param qs [Hash] keys: `'ao'` (open-async), `'ap'` (attrprep), `'mgmt_backlog'` (bytes buffered)
        def add_ds_qs_sample(qs)
          @ds_qs_samples.push(qs)
        end

        # Tell if another session starts while the rate samples are recorded: it may share the link
        # @param starts [Array<Integer>] start times of the transfer sessions of the log
        def shared_link(starts)
          return if @rate_samples.empty?
          first, last = @rate_samples.map { |sample| sample[1] }.minmax
          @data[:shared_link] = starts.any? { |time| time > first && time <= last }
        end

        # Evaluate ATM / tail-drop rate limiting detection, at end of a snapshot period
        def evaluate_atm
          return if @atm.nil? || @atm[:samples].nil?
          if @atm[:periods].to_i < 2
            @atm[:periods] = @atm[:periods].to_i + 1
            return
          end
          return unless @atm[:samples] == 6
          increment(:atm) if %i[atm_loss atm_ratio atm_queue].all? { |k| @atm[k].to_i / 6.0 >= 0.83 }
          @atm = nil
        end

        # Final status of session, if ascp stopped logging before end of session
        # @param last_time [Integer] time of last sample in log file
        # @return [Symbol, nil] category of exit
        def check_exit(last_time)
          return if last_time.to_i - num(:last) <= 30 || flag?(:stats_end)
          category =
            if @data[:error] == 'Out of buffer memory'
              @data[:error] = 'Out of buffer memory, and ascp exited.'
              :buffer_died
            elsif flag?(:decryption_error)
              @data[:error] = 'File decryption error, and ascp exited.'
              :decryption_died
            elsif flag?(:data_transfer_timeout)
              @data[:error] = "#{@data[:error]}, and ascp exited."
              :timeout_died
            elsif @data[:error] == 'segfault'
              @data[:error] = 'ascp exited: segfault.'
              :died
            elsif @data[:status]
              return if flag?(:ssh_timeout, :cannot_connect_to_management_socket)
              set(:table_died)
              :table_died
            else
              @data[:error] = 'ascp exited, or was in IOwait or stopped logging'
              :died
            end
          @data[:status] = 'failed' unless @data[:status] == 'success' || category == :table_died
          @data[:exit] = category
        end

        # @return [Boolean] true if session has the stuck NACK problem
        def stuck_nack?
          return false if @data[:status] == 'success'
          num(:stuck_nack_count) >= 5 || ((flag?(:send_nack_stuck) || num(:sender_stuck_nack_count) >= 5) && num(:loss_rate) < 0.9)
        end

        def windows?
          [@data[:os], @data[:peeros]].any? { |os| os.to_s.match?(/windows/i) }
        end

        # @return [String, nil] `send` or `receive`
        def direction
          (@data[:op] == 'recv' ? 'receive' : @data[:op]) || @data[:dir]
        end

        # @return [Integer, nil] error code of session, if it is in the numbering of supported versions
        def error_code
          @data[:error_code] unless self.class.version_older?(@data[:ver], MIN_VERSION)
        end

        # @return [String, nil] category of error code, see SessionErrors::CATEGORIES
        def error_category
          code = error_code or return
          SessionErrors.category(code)
        end

        # @return [Symbol, nil] probable cause of loss on sender: :storage or :network (shallow queues)
        def overdrive
          return unless @data[:dir] == 'send' && num(:loss_rate) > 0.10 && @constraints.size == 1
          return :storage if DISK_THROTTLE_RATES.include?(@constraint.dig('Receiver', :min_rate))
          return if num(:stuck_nack_count) >= 10 || @params
          :network if @constraint.key?('Receiver') && constraint_average('Receiver') >= 0.8 * num(:target_rate)
        end

        # @param windows_log [Boolean] log file is on Windows
        # @return [Hash] report of session: one table row
        def report(windows_log: false)
          d = @data
          sample_dir = d[:dir]
          avg = d[:effective_rate] ? self.class.rate_bps(d[:effective_rate]).to_i : num(:avg)
          avg = d[:target_rate] if num(:target_rate).positive? && avg > d[:target_rate]
          loss = num(:loss_rate)
          min_rate_high = d[:min_rate] if d[:policy] == 'fair' && (num(:min_rate) >= 5_000_000 || num(:min_rate) > num(:target_rate) / 2.0)
          rtt = series_stats(:rtt)
          srtt = series_stats(:srtt)
          constraints = @constraint.reject { |_, c| c[:min_rate].nil? }.to_h do |name, c|
            series = @series[CONSTRAINT_SERIES[name]]
            entry = {'max' => c[:min_rate], 'average' => constraint_average(name), 'std_dev' => self.class.standard_deviation(series).to_i, 'samples' => series.size}
            if name == 'network'
              entry['base_rtt'] = c[:base_rtt]
              entry['smoothed_rtt'] = c[:smooth_rtt]
            end
            entry['causes'] = @receiver_causes.sort_by { |_, count| -count }.to_h if name == 'Receiver' && @receiver_causes.any?
            [name, entry]
          end
          slowdown = constraints.values.any? { |c| c['max'] < 8 * (num(:mtu) - 40) }
          tx_time = d[:tx_time].to_i.nonzero? ? d[:tx_time] / 1_000_000.0 : d[:elapsed].to_f
          @diagnostics = Diagnostics.new(self, windows_log: windows_log).evaluate(
            loss:          loss,
            slowdown:      slowdown,
            sample_dir:    sample_dir,
            avg:           avg,
            min_rate_high: min_rate_high,
            rtt:           rtt,
            srtt:          srtt
          )
          {
            'pid'                     => @pid,
            'session'                 => d[:uuid],
            'user'                    => d[:user],
            'direction'               => direction,
            'role'                    => d[:role] || role_from_ports,
            'status'                  => d[:status],
            'error'                   => d[:error],
            'error_code'              => d[:error_code],
            'error_category'          => error_category,
            'error_retry'             => (SessionErrors.retryable(error_code) if error_code),
            'transfer_id'             => d[:xfer_id],
            'multi_session'           => ("#{d[:cluster_node].to_i + 1}/#{d[:cluster_nodes]}" if num(:cluster_nodes) > 1),
            'retry_of'                => d[:retry_of],
            'retried_by'              => d[:retried_by],
            'start'                   => iso(d[:start]),
            'stop'                    => iso(d[:stop]),
            'local'                   => d[:local],
            'local_port'              => d[:l_port],
            'version'                 => d[:ver],
            'os'                      => d[:os],
            **context_columns,
            'peer'                    => d[:peer],
            'peer_port'               => d[:p_port],
            'peer_version'            => d[:peerver],
            'peer_os'                 => d[:peeros],
            'peer_product'            => d[:peer_product],
            'destination'             => d[:dest],
            'policy'                  => d[:policy],
            'encryption'              => d[:secure],
            'resume'                  => RESUME.fetch(d[:resume], d[:resume]),
            'overwrite'               => OVERWRITE.fetch(d[:overwrite], d[:overwrite]),
            'block_size'              => d[{'send' => :read_block_size, 'receive' => :write_block_size}[sample_dir]],
            'mtu'                     => d[:mtu],
            'payload'                 => d[:payload],
            'target_rate'             => d[:target_rate],
            'min_rate'                => d[:min_rate],
            'average_rate'            => avg,
            'average_calculated_rate' => self.class.average(@series[:calc]).to_i,
            'max_rate'                => {'send' => d[:send_max], 'receive' => d[:recv_max].to_i.nonzero? || avg}[sample_dir],
            'transmitted_bytes'       => num(:tx_bytes),
            'transfer_time'           => tx_time.round(2),
            'files'                   => d[:transfer_stop_count],
            'files_transferred'       => d[:files_success],
            'files_skipped'           => d[:files_skipped],
            'files_failed'            => d[:files_failed],
            'file_size_mean'          => (self.class.average(@sizes).to_i if d[:transfer_stop_count]),
            'file_size_median'        => (self.class.median(@sizes).to_i if d[:transfer_stop_count]),
            'concurrent_min'          => (d[:sess_min].to_i.nonzero? || 1 if d[:sess_max]),
            'concurrent_max'          => d[:sess_max],
            'concurrent_max_time'     => iso(d[:sess_max_time]),
            'start_rtt'               => d[:start_brtt],
            'base_rtt'                => d[:brtt],
            'rtt_average'             => rtt&.first,
            'rtt_median'              => rtt&.last,
            'srtt_average'            => srtt&.first,
            'srtt_median'             => srtt&.last,
            'loss_rate'               => (loss.positive? ? (loss * 100).round(2) : (0.0 if num(:tx_bytes).nonzero?)),
            'out_of_order_rate'       => (num(:ooo) * 100).round(2).nonzero?,
            'efficiency'              => d[:efficiency],
            'retransmitted_rate'      => d[:retransmitted],
            'duplicate_rate'          => d[:duplicates],
            'disk_read_rate'          => d[:disk_read_rate],
            'constraints'             => @constraints.to_a,
            'constraint'              => constraints,
            'diagnostics'             => @diagnostics.map { |diagnostic| diagnostic['message'] }
          }.compact
        end

        private

        FASP_PORTS = (33_000..33_099)
        private_constant :FASP_PORTS

        # Columns that tell in which context the session ran, to filter sessions
        # @return [Hash] product, transport (`ssh` or `wss`), authentication type (`token` or `node`), proxy address, FIPS mode
        def context_columns
          {
            'product'        => @data[:product],
            'product_name'   => @data[:product_name],
            'transport'      => @data[:transport],
            'authentication' => @data[:auth],
            'proxy'          => @data[:proxy],
            'fips'           => @data[:fips]
          }
        end

        def iso(time)
          Time.at(time).getlocal(@timezone).iso8601 if time
        end

        # @return [Array, nil] average and median of series, as integers
        def series_stats(name)
          series = @series[name]
          [self.class.average(series).to_i, self.class.median(series).to_i] unless series.empty?
        end

        # @return [Integer] average of values of a constraint
        def constraint_average(name)
          self.class.average(@series[CONSTRAINT_SERIES[name]]).to_i
        end

        # @return [String, nil] client or server, deduced from UDP ports
        def role_from_ports
          local, peer = @data.values_at(:l_port, :p_port)
          return unless local && peer
          return 'server' if local == 33_001 || (FASP_PORTS.cover?(local) && !FASP_PORTS.cover?(peer))
          'client'
        end

        def change_param(key, value)
          @params ||= {}
          @params[:"#{key}_old"] = @data[key]
          @params[key] = value
          @data[key] = value
        end

        # Sender side: NACKs stuck while no progress
        def check_sender_nacks(s)
          if @send_nack.nil?
            @send_nack = {}
            return
          end
          sn = @send_nack
          no_progress = s[:blocks].to_i >= sn[:blocks].to_i && s[:tx_bytes] == sn[:tx_bytes].to_i && s[:written] == sn[:written].to_i &&
            s[:tx_bytes].nonzero? && s[:written].nonzero?
          if no_progress && s[:rex_count].to_i == sn[:rex_count].to_i && s[:rex_received].to_i == sn[:rex_received].to_i
            sn[:count] = sn[:count].to_i + 1
            set(:send_nack_stuck) if sn[:count] > 10
          elsif no_progress && sn[:rex_received].to_i < s[:rex_received].to_i
            increment(:sender_stuck_nack_count)
          else
            @send_nack = s.slice(:rex_count, :blocks, :rex_received, :tx_bytes, :written)
            @data[:sender_stuck_nack_count] = 0
          end
        end

        # NACKs stuck at same value while no progress
        def check_stuck_nack(s)
          nack = s[:rex_count]
          return if nack.nil? || num(:tx_bytes).zero?
          if num(:stuck_nack).zero?
            @data.merge!(stuck_nack: nack, stuck_nack_count: 1) if num(:tx_bytes) == s[:tx_bytes]
          elsif nack.zero?
            @data.merge!(stuck_nack: 0, stuck_nack_count: 0)
          elsif nack == @data[:stuck_nack] && num(:tx_bytes) == s[:tx_bytes] && s[:calc_rate].to_i.nonzero?
            increment(:stuck_nack_count)
          else
            @data.merge!(stuck_nack: nack, stuck_nack_count: 0)
          end
        end

        # Retransmissions not progressing while NACKs pending: NACK requests are being lost
        def check_stuck_rex(s)
          rex = s[:rex]
          nack = s[:rex_count].to_i
          return if rex.nil?
          if @data[:stuck_rex].nil? || (nack.nonzero? && rex > @data[:stuck_rex]) then @data[:stuck_rex] = rex
          elsif nack.zero? then @data[:stuck_rex_count] = 0
          elsif rex == @data[:stuck_rex] then increment(:stuck_rex_count)
          end
        end

        # Base RTT: detect VM (clock problem) and reverse path congestion skew
        def log_brtt(s, elapsed, first:, smart_reset:)
          b_rtt = s[:brtt].to_i
          brtt = num(:brtt)
          if brtt.nonzero? && elapsed > 22
            if brtt - b_rtt >= 20 && b_rtt.fdiv(brtt) <= 0.5
              set(:vm) unless smart_reset
              @data[:c_rate] = s[:calc_rate]
            elsif b_rtt < brtt
              increment(:reverse_path)
              if (num(:start_brtt).zero? || b_rtt.fdiv(@data[:start_brtt]) <= 0.7) && @data[:reverse_path] >= 5
                set(:disable_reverse)
                @data[:n_rate] = s[:net_rate].to_i if num(:n_rate).zero? || num(:n_rate) > s[:net_rate].to_i
              end
            end
            @data[:brtt] = b_rtt if b_rtt < brtt
          elsif first && s[:rtt_high].to_i.positive? && elapsed > 21
            @data[:brtt] = b_rtt
          end
        end

        def check_high_rtt(s)
          rtt = s[:rtt_high].to_i
          srtt = s[:srtt].to_i
          @data[:big_rtt] = [rtt, srtt].max if (rtt > 3000 || srtt > 3000) && rtt != srtt && [rtt, srtt].max > num(:big_rtt)
          @data[:big_rex_srtt] = s[:rex_srtt] if s[:rex_srtt].to_i > 3000 && s[:rex_srtt] > num(:big_rex_srtt)
        end

        # Values at end of snapshot period
        def update_slot(s, slot, t_bits, elapsed, receiver)
          slot[:diff] = s[:time] - slot[:date1] if slot[:elapsed2] && elapsed - slot[:elapsed2] < 20 && s[:written] == slot[:written2]
          slot.merge!(written2: s[:written], tx_bytes: s[:tx_bytes], elapsed2: elapsed, total2: t_bits, blocks2: s[:blocks], loss2: s[:lost], orig2: s[:orig], rex2: s[:rex])
          duration = slot[:diff].to_i.nonzero? || (elapsed - slot[:elapsed1].to_f)
          slot[:net_rate] = (t_bits - slot[:total1].to_i).fdiv(duration).to_i if duration.nonzero?
          session_time = (num(:elapsed_us) - num(:elapsed_start)) / 1_000_000.0
          @data[:avg] = (s[:blocks].to_i - num(:start_block)).fdiv(session_time).to_i * @data[:mtu] * 8 if session_time.nonzero?
          lost, total =
            if receiver
              lost = slot[:loss2].to_i - slot[:loss1].to_i
              [lost, lost + slot[:orig2].to_i - slot[:orig1].to_i]
            else
              [slot[:rex2].to_i - slot[:rex1].to_i, slot[:blocks2].to_i - slot[:blocks1].to_i]
            end
          return if total.zero?
          slot[:loss_rate] = 100.0 * lost / total
          slot[:loss_speed] = (slot[:net_rate].to_i * lost.fdiv(total)).to_i
        end

        # Determine which constraint limits the rate: Receiver (for sender), or network, disk, vlink (for receiver)
        def rate_constraint(s, slot, elapsed, receiver, first)
          t_rate = s[:target_rate].to_i
          c_rate = s[:calc_rate].to_i
          return if t_rate == c_rate
          rates =
            if receiver
              RECEIVER_CONSTRAINTS.transform_values { |key| s[key].to_i }.select { |_, rate| rate < t_rate }
            else
              {'Receiver' => c_rate}
            end
          limit = rates.min_by(&:last)&.first
          @constraints.add(limit) if receiver && limit && !first
          return if elapsed <= 20
          @data[:policy] = 'fair'
          count_receiver_cause(s, t_rate) unless receiver
          (slot[:calc_1] ||= []).push(limit) unless limit.nil? || slot[:calc_1]&.include?(limit)
          @constraints.add('disk') if receiver && s[:disk_rate].to_i < t_rate
          @constraints.add(limit) if limit && (first || !receiver)
          rates.each do |name, rate|
            current = (@constraint[name] ||= {})
            next if current[:min_rate].to_i.nonzero? && current[:min_rate] <= rate
            current[:min_rate] = rate
            next unless name == 'network'
            current[:base_rtt] = s[:brtt]
            current[:smooth_rtt] = s[:srtt] if s[:net_rate].to_i == c_rate
          end
        end

        # Sender (ascp 4): count which rate of the receiver limits the calculated rate
        def count_receiver_cause(s, t_rate)
          rates = RECEIVER_CAUSES.transform_values { |keys| keys.map { |key| s[key].to_i }.select(&:positive?).min }
          cause = rates.compact.select { |_, rate| rate < t_rate }.min_by(&:last)&.first
          @receiver_causes[cause] += 1 if cause
        end

        # First and latest points, to compute average rate
        def update_calc_points(c_rate, t_bits, elapsed)
          point = num(:calc0).zero? ? 0 : 1
          @data.merge!("calc#{point}": c_rate, "total#{point}": t_bits, "elapsed#{point}": elapsed)
        end

        def calc_speed
          duration = @data[:elapsed1].to_f - @data[:elapsed0].to_f
          duration.zero? ? 0 : (@data[:total1].to_i - @data[:total0].to_i).fdiv(duration).to_i
        end

        # Detect peer clock problems/VM from sender side
        def detect_peer_vm(s)
          c_rate = s[:calc_rate].to_i
          t_rate = s[:target_rate].to_i
          vm = (@vm ||= {})
          if vm[:elapsed1].nil?
            vm[vm[:elapsed0].nil? ? :elapsed0 : :elapsed1] = s[:elapsed]
          else
            vm[:elapsed0] = vm[:elapsed1]
            vm[:elapsed1] = s[:elapsed]
          end
          vm[:calc0] = num(:calc0)
          return if vm[:elapsed0].to_f == vm[:elapsed1].to_f
          if t_rate < vm[:calc0]
            vm.merge!(calc0: t_rate, low: 0, high: 0)
            clear(:vm_peer)
            @data[:vm_c_rate] = 0
          end
          vm[:high] = vm[:high].to_i + 1 if c_rate >= 0.8 * vm[:calc0]
          if c_rate < 0.5 * vm[:calc0] && vm[:high].to_i > 2
            if vm[:low].to_i > 2
              set(:vm_peer)
              @data[:vm_c_rate] = c_rate
            elsif vm[:calc0] - c_rate > 20_000_000 && !DISK_THROTTLE_RATES.include?(c_rate)
              vm[:low] = vm[:low].to_i + 1
            end
          end
          return if c_rate <= 0.6 * vm[:calc0]
          clear(:vm_peer)
          vm[:low] = 0
        end

        # Detect ATM/tail-drop rate limiting
        def check_atm(s, t_bits, elapsed)
          atm = (@atm ||= {})
          c_rate = s[:calc_rate].to_i
          t_rate = s[:target_rate].to_i
          lost = s[:lost].to_i - atm[:loss0].to_i
          sent = lost + s[:orig].to_i - atm[:orig0].to_i
          atm[:atm_loss] = atm[:atm_loss].to_i + 1 if sent.nonzero? && lost.fdiv(sent) > 0.2
          duration = elapsed - atm[:elapsed0].to_f
          rate = duration.zero? ? 0 : (t_bits - atm[:total0].to_i) / duration
          return if rate.zero?
          atm[:atm_ratio] = atm[:atm_ratio].to_i + 1 if c_rate / rate > 1.3
          queue = if t_rate <= 5_000_000 then 5
          elsif t_rate <= 200_000_000 then 10
          else 40
          end
          atm[:atm_queue] = atm[:atm_queue].to_i + 1 if num(:max_queue) < 1000 && t_rate * queue / rate > 0.75 * num(:max_queue)
        end
      end
    end
  end
end
