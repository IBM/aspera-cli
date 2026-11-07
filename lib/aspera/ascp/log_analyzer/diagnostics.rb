# frozen_string_literal: true

# cspell:words commify Isilon nohear onefs overdriven
require 'time'
require 'aspera/ascp/session_errors'

module Aspera
  module Ascp
    class LogAnalyzer
      # Diagnostics evaluated on a transfer session
      class Diagnostics
        UDP_TIMEOUT = 'check firewalls for UDP flood protection or UDP session timeouts'
        # Control messages in `Session Statistics`: direction => description
        CONTROL_DIRECTIONS = {'sndr' => 'from sender to receiver', 'rcvr' => 'from receiver to sender', 'rex' => 'requesting retransmission'}.freeze

        # Flag => severity and message of diagnostic (identifier: name of flag)
        FLAG_DIAGNOSTICS = {
          device_not_connected:                [:error,   'The device (mapped drive) is not connected.'],
          timeout_establishing_udp_connection: [:error,   'Timeout establishing the UDP connection: check the UDP port and firewalls.'],
          token_expired:                       [:error,   'The token has expired.'],
          net_error:                           [:error,   'An unexpected network error occurred when writing to network storage.'],
          net_path_not_found:                  [:error,   'The network path was not found.'],
          net_name_gone:                       [:error,   'The network name is no longer available.'],
          sharing_violation:                   [:error,   'Windows sharing violation: a file is used by another process.'],
          insufficient_permissions:            [:error,   'Insufficient permissions to read or write a file.'],
          out_of_disk:                         [:error,   'The storage is out of space.'],
          disk_write_failed:                   [:error,   'Unable to write to the storage.'],
          out_of_resources:                    [:error,   'The Windows system is out of resources.'],
          ssh_timeout:                         [:warning, 'The SSH session timed out, which may abort the transfer.'],
          remote_reset:                        [:warning, 'A TCP connection was reset by the remote host, which may have ended the session.'],
          local_reset:                         [:warning, 'A TCP connection was reset by the local host, which may have ended the session.'],
          read:                                [:error,   'Unable to read from the storage.'],
          write:                               [:error,   'Unable to write to the storage.'],
          server_nohear_client:                [:error,   'Session setup failed: the server received no UDP from the client: check the UDP port and firewalls.'],
          bind_udp_socket_failed:              [:error,   'The server could not bind its UDP port to start the session.'],
          no_buffer_mem:                       [:error,   'The Windows system ran out of buffer memory: check the event log and memory.'],
          client_nohear_server:                [:error,   'Session setup failed: the client could not reach the server over UDP: check the UDP port and firewalls.'],
          receiver_data_transfer_timeout:      [:error,   "The receiver received no UDP packets for 60 seconds, which ended the session: #{UDP_TIMEOUT}."],
          inactivity_timer_fired:              [:error,   "The sender received no UDP feedback from the receiver for 60 seconds, which ended the session: #{UDP_TIMEOUT}."],
          content_protection:                  [:error,   'The server requires content protection (encryption at rest), but the client did not provide it.'],
          user_abort:                          [:info,    'The user cancelled the session.'],
          http_fallback:                       [:info,    'The session fell back to HTTP.'],
          table_died:                          [:warning, 'ascp exited at the end of the session, without logging the statistics table.'],
          ssh_startup_failed:                  [:error,   'The SSH connection to the server could not be established.'],
          ssh_key_authentication:              [:error,   'SSH public key authentication failed.'],
          ssh_session_failed:                  [:error,   'The SSH session to the server could not be opened.'],
          ssh_command_failed:                  [:error,   'The remote command could not be started on the server through SSH.'],
          ssh_forward_failed:                  [:error,   'The server refused TCP/IP forwarding through SSH.']
        }.freeze

        # @return [Array<Hash>] diagnostics collected so far
        attr_reader :list

        # @param session     [Session] transfer session to diagnose
        # @param windows_log [Boolean] log file is on Windows
        def initialize(session, windows_log: false)
          @session = session
          @windows_log = windows_log
          @thresholds = session.thresholds
          @list = []
        end

        # Evaluate all diagnostics for the session
        # @return [Array<Hash>] list of diagnostics: {id, severity, message}
        def evaluate(loss: nil, slowdown: nil, sample_dir: nil, avg: nil, min_rate_high: nil, rtt: nil, srtt: nil)
          d = @session.data
          sample_dir ||= d[:dir]
          loss ||= @session.num(:loss_rate)
          diag(:old_version, :warning, "ascp version #{d[:ver]} is older than #{MIN_VERSION}: analysis may be inaccurate.") if Session.version_older?(d[:ver], MIN_VERSION)
          diagnose_context
          diagnose_path_mtu
          diagnose_params
          diag(:min_rate_high, :warning, "The minimum rate is too high: #{c(min_rate_high)} bps.") if min_rate_high
          case @session.overdrive
          when :storage then diag(:storage_overdrive, :warning, 'Probable cause of loss: overdriving of the storage of the receiver: check the receiver logs.')
          when :network then diag(:network_overdrive, :warning, 'Probable cause of loss: shallow queues in the network, or UDP rate-limiting: check the receiver logs.')
          end
          diag(:brtt_reset, :info, "The base RTT was reset by ascp #{d[:brtt_reset]} times.") if d[:brtt_reset]
          FLAG_DIAGNOSTICS.each { |flag, (severity, message)| diag(flag, severity, message) if @session.flag?(flag) }
          diagnose_errors(loss, slowdown)
          diagnose_performance(loss, sample_dir, rtt, srtt)
          diagnose_loss(loss, sample_dir, avg, min_rate_high)
          diagnose_stuck_nack(loss)
          diagnose_quality
          diagnose_rate_decline
          diagnose_file_pipeline
          diagnose_sender if sample_dir == 'send'
          @list
        end

        # Error category, retries, and parameters set by the server
        def diagnose_context
          d = @session.data
          hint = SessionErrors.hint(@session.error_category)
          diag(:"error_#{@session.error_category}", :error, hint) if hint && d[:status] == 'failed'
          diag(:retry, :info, "Retry of failed session #{d[:retry_of]}.") if d[:retry_of]
          diag(:retried, :info, "Retried by session #{d[:retried_by]}.") if d[:retried_by]
          diag(:cipher_set_by_server, :info, "Encryption cipher set by server configuration: #{d[:cipher_override].first} (requested: #{d[:cipher_override].last}).") if d[:cipher_override]
          case d[:resume_downgrade]
          when nil
          when 'RESUME_POLICY_ATTRS' then diag(:resume_lowered, :info, 'Resume policy lowered to file attributes: checksum-based resume is not supported by the storage.')
          else diag(:resume_lowered, :info, "Resume policy lowered to \"#{Session::RESUME.fetch(d[:resume_downgrade].to_i, d[:resume_downgrade])}\" as requested by the peer.")
          end
          diag(:job_size_changed, :info, "Job size changed from #{d[:job_size].first} to #{d[:job_size].last} to match server configuration.") if d[:job_size]
          d[:vlinks]&.each { |id, vlink| diag(:vlink, :info, "Virtual link #{id} (#{vlink['type']}) limits bandwidth to #{c(vlink['capacity'])} bps.") }
          diagnose_license
        end

        # Maximum rate of the license below the target rate, and expiry date of the license close to the session
        def diagnose_license
          d = @session.data
          diag(:license_rate_limit, :warning, "The license limits the rate to #{c(d[:license_rate])} bps, below the target rate of #{c(@session.num(:target_rate))} bps.") if d[:license_rate] && @session.num(:target_rate) > d[:license_rate]
          return unless d[:license_expires] && (started = d[:start] || d[:stop])
          days = ((Time.parse(d[:license_expires]).to_i - started) / 86_400.0).floor
          return if days > @thresholds[:license_expiry_days]
          diag(:license_expiry, :warning, days.negative? ? "The license expired on #{d[:license_expires]}." : "The license expires on #{d[:license_expires]}, #{days} days after the start of this session.")
        end

        # Path MTU measured by ascp well below Ethernet (ascp probes 1492, 1006, 508 and 296 bytes)
        def diagnose_path_mtu
          path_mtu = @session.data[:path_mtu]
          return unless path_mtu&.positive? && path_mtu < @thresholds[:small_mtu_max]
          diag(
            :small_mtu, :info,
            "The path MTU measured by ascp is #{path_mtu} bytes, well below the 1500 bytes of Ethernet (datagram size: #{@session.data[:mtu]} bytes): a VPN, a tunnel or a device that blocks large packets may be on the path."
          )
        end

        # Efficiency and loss of control messages, from `Session Statistics`
        def diagnose_quality
          d = @session.data
          if d[:efficiency] && @session.num(:tx_bytes).positive? && d[:efficiency] < @thresholds[:efficiency]
            diag(:low_efficiency, :warning, "Only #{d[:efficiency]}% of the data blocks sent were useful: retransmissions reduce the effective rate." \
              "#{' In fixed policy, lower the target rate, or use fair policy.' if d[:policy] == 'fixed'}")
          end
          d[:control_loss]&.each do |direction, (sent, lost)|
            next if sent < @thresholds[:control_loss_sent] || lost < @thresholds[:control_loss_percent]
            diag(:control_message_loss, :warning, "#{lost}% of control messages #{CONTROL_DIRECTIONS[direction]} were lost.")
          end
          return unless @session.num(:rex_overflow).positive?
          diag(
            :rex_timer_overflow, :warning,
            "The retransmission timer overflowed at least #{@session.num(:rex_overflow)} times (logged every 5 seconds at most): the retransmission RTT was very large, which delays the retransmission of lost blocks."
          )
        end

        # Rate of the second half of the samples is lower than the first half.
        # Not evaluated if the session failed, if the rate parameters changed, or if another session started and may share the link.
        # The last samples are dropped: end of session, file queue drained.
        def diagnose_rate_decline
          return if @session.data[:status] == 'failed' || @session.params || @session.data[:shared_link]
          rates = @session.rate_samples.sort_by(&:first).map(&:last)
          rates = rates.first((rates.size * (1 - @thresholds[:rate_decline_end_fraction])).floor)
          return if rates.size < @thresholds[:rate_decline_min_samples]
          half = rates.size / 2
          first = Session.average(rates.first(half))
          second = Session.average(rates.last(rates.size - half))
          return unless first.positive? && second < @thresholds[:rate_decline_ratio] * first
          diag(:rate_decline, :warning, "The rate declined during the transfer: #{c(second)} bps on average in the second half, #{c(first)} bps in the first half (#{(100.0 * second / first).round}%).")
        end

        # Sender (ascp 4): limit set by the receiver, and storage read rate
        def diagnose_sender
          d = @session.data
          if @session.receiver_causes.any?
            total = @session.receiver_causes.values.sum
            causes = @session.receiver_causes.sort_by { |_, count| -count }.map { |cause, count| "#{cause} (#{(100.0 * count / total).round}% of samples)" }
            diag(:receiver_limit, :info, "Rate limited by the receiver: #{causes.join(', ')}.")
          end
          calculated = Session.average(@session.series[:calc]).to_i
          return unless d[:disk_read_rate] && calculated.positive? && d[:disk_read_rate] < calculated
          diag(
            :slow_storage_read, :warning,
            "Reading from storage (#{c(d[:disk_read_rate])} bps) is slower than the calculated rate (#{c(calculated)} bps): sender storage limits the transfer."
          )
        end

        def diagnose_params
          return unless @session.params
          p = @session.params
          changes = []
          changes.push("Policy changed from #{p[:policy_old]} to #{p[:policy]}.") if p.key?(:policy)
          changes.push("Target rate changed from #{c(p[:target_rate_old])} bps to #{c(p[:target_rate])} bps.") if p.key?(:target_rate)
          changes.push("Minimum rate changed from #{c(p[:min_rate_old])} bps to #{c(p[:min_rate])} bps.") if p.key?(:min_rate)
          diag(:rate_change, :info, "#{p[:multiple] ? 'Last of multiple parameter changes' : 'Parameter change'}#{' by peer' if p[:peer]}: #{changes.join(' ')}")
        end

        def diagnose_errors(loss, slowdown)
          d = @session.data
          if @session.flag?(:out_of_memory)
            diag(:out_of_memory, :error, "The system is running out of memory#{' (on Isilon, possibly because of asperacentral)' if d[:os].to_s.match?(/onefs/i)}.")
          end
          if @session.flag?(:as_buf_io)
            cause = "probably because of the high packet loss#{', due to fixed policy' if d[:policy] == 'fixed'}" if loss > 0.9
            diag(:ssh_session_died, :warning, "The SSH session died, which may abort the transfer#{": #{cause}" if cause}.")
          end
          if @session.num(:no_data).positive?
            causes = "#{'disk or network constraints on the rate, ' if slowdown}rate-limiting, a firewall block, or a network outage"
            diag(:reception_interruption, :warning, "Data reception was interrupted for up to #{d[:no_data]} seconds (#{d[:no_data_total]} seconds in total): possibly caused by #{causes}.")
          end
          if @session.num(:no_feedback).positive?
            diag(
              :feedback_interruption, :warning,
              "The sender received no packet from the receiver for up to #{d[:no_feedback]} seconds (#{d[:no_feedback_total]} seconds in total): possibly caused by rate-limiting, a firewall block, or a network outage."
            )
          end
          diag(:filename_too_long, :error, "#{d[:filename_too_long]} files failed because their Windows path is longer than 260 characters.") if d[:filename_too_long] && (@windows_log || @session.windows?)
          diag(:configuration_error, :error, "Error in aspera.conf: #{d[:conf_parse]}") if d[:conf_parse]
          # Session ended without `Session Stop`: show the error logged just before, if any
          diag(:last_error, :error, "Last error before ascp stopped logging: #{d[:last_error]}") if d[:exit] && d[:stop].nil? && d[:last_error] && d[:last_error_time].to_i >= @session.num(:last) - @thresholds[:last_error_window]
          if d[:ssh_disconnect]
            # libssh2 error -9: timeout
            diag(
              :ssh_not_closed, :warning,
              "The SSH connection to the server was not closed properly: #{d[:ssh_disconnect]}#{' (timeout: no answer from server)' if d[:ssh_disconnect].end_with?('rc=-9')}"
            )
          end
          if @session.num(:gap).positive?
            diag(:io_wait, :warning, "ascp was blocked (IO wait) for #{d[:gap]} seconds, until #{Time.at(d[:gap_last], in: @session.timezone).ctime}#{', with an SSH timeout' if @session.flag?(:ssh_timeout)}.")
          end
          diag(:udp_flood_protection, :warning, 'No route to host during the transfer: possibly caused by UDP flood protection of a firewall: check the logs.') if @session.flag?(:send_no_route) && @session.num(:tx_bytes).nonzero? && !@session.flag?(:as_buf_io)
          diag(:local_port_changed, :info, "Local port changed from #{d[:start_l_port]} to #{d[:l_port]} during the session.") if d[:start_l_port]
        end

        def diagnose_performance(loss, sample_dir, rtt, srtt)
          d = @session.data
          fair_only = (' Storage rate control requires fair policy.' if d[:policy] == 'fixed')
          diag(:disk_write_speed_exceeded, :warning, "The disk write speed was exceeded.#{fair_only}") if @session.flag?(:exceeded)
          if @session.flag?(:vm) && !d[:brtt_reset]
            rate = " The calculated rate dropped to #{c(d[:c_rate])} bps, with a base RTT of #{d[:brtt]} ms." if sample_dir == 'receive'
            diag(:clock_problem, :warning, "This system (ascp #{d[:ver]}) may run on a VM, or have another clock problem, which affected the transfer.#{rate}")
          elsif @session.flag?(:vm_peer)
            others = [
              (' Reverse path congestion inference could also cause it: check the peer logs.' if @session.flag?(:disable_reverse)),
              (' Slow storage could also lower the rate.' if d[:disk_max]),
              (" The calculated rate dropped to #{c(d[:vm_c_rate])} bps." if sample_dir == 'send')
            ].join
            diag(:peer_clock_problem, :warning, "The peer may run on a VM, or have another clock problem, which affected the transfer.#{others}")
          end
          diag(:reverse_path_inference_disabled, :info, 'Reverse path congestion inference is disabled for this transfer.') if @session.flag?(:no_reverse_infer)
          if @session.flag?(:disable_reverse) && !@session.flag?(:no_reverse_infer) && !d[:brtt_reset]
            rate = " The calculated rate dropped to #{c(d[:n_rate])} bps, with a base RTT of #{d[:brtt]} ms." if sample_dir == 'receive'
            diag(:reverse_path_skew, :warning, "Reverse path congestion skew lowered the rate: check the logs, and disable reverse path congestion inference if appropriate.#{rate}")
          end
          diag(:slow_disk_write, :warning, "The disk write speed of the receiver was too slow #{d[:disk_max]} times.") if d[:disk_max]
          diag(:disk_buffers, :warning, "The disk write buffer depth reached #{d[:buffers]}.#{fair_only}") if d[:buffers]
          if @session.flag?(:rex_buffer_full)
            diag(
              :retransmission_buffer_full, :warning,
              "The retransmission buffer was full: possibly severe packet loss caused by rate-limiting or policing#{', or by fixed policy' unless d[:policy] == 'fair'}."
            )
          end
          if @session.num(:big_rtt).positive?
            cause =
              if @session.flag?(:rex_buffer_full) then 'probably because of a full retransmission buffer'
              elsif @session.flag?(:exceeded) then 'probably because of slow disk write'
              elsif loss > 0.3 then 'probably because of the high packet loss'
              else 'cause not apparent: investigate'
              end
            diag(:high_rtt, :warning, "The round trip time is excessive (#{d[:big_rtt]} ms): #{cause}.")
          end
          if d[:big_rex_srtt]
            rex = @session.series[:rex_srtt]
            median = Session.median(rex)
            diag(
              :high_retransmission_rtt, :warning,
              "The retransmission round trip time is excessive: maximum #{d[:big_rex_srtt]} ms, average #{Session.average(rex).to_i} ms, median #{median == median.to_i ? median.to_i : median} ms."
            )
          end
          return unless d[:atm] && rtt&.first.to_i.nonzero? && loss * 100 > 20
          path = ' The path may contain a rate-limiting firewall or router, or an ATM switch, causing excessive packet loss.' if srtt&.first.to_i.nonzero? && @session.num(:brtt).fdiv(srtt.first) >= 0.95
          diag(:network_overdriven, :warning, "The network capacity is severely overdriven: lower the target rate#{' or use fair policy' if d[:policy] == 'fixed'}.#{path}")
        end

        def diagnose_loss(loss, sample_dir, avg, min_rate_high)
          d = @session.data
          loss_pct = loss * 100
          if loss_pct >= 10 && (d[:disk_max] || d[:buffers] == 12)
            if min_rate_high
              diag(:min_rate_overdrive, :warning, 'Loss and disk overdrive possibly caused by a minimum rate too high.')
            else
              diag(:slow_storage_loss, :warning, "Loss possibly caused by slow storage write on the receiver#{" (maximum disk constraint reached #{d[:disk_max]} times)" if d[:disk_max]}.")
            end
          end
          return unless sample_dir == 'send'
          receiver_min = @session.constraint.dig('Receiver', :min_rate)
          if receiver_min && @session.num(:target_rate).positive? && receiver_min.fdiv(d[:target_rate]) > 0.9 && loss_pct > 30
            diag(
              :network_overdriven, :warning,
              'The network capacity is severely overdriven: the path may contain a rate-limiting firewall or router, or an ATM switch, causing excessive packet loss: check the logs of the receiver.'
            )
          end
          return unless min_rate_high && min_rate_high > avg && loss_pct > 20
          diag(:min_rate_overdrive, :warning, 'The network capacity is severely overdriven, possibly because of a minimum rate too high: in fair policy, set it low (e.g. 20 Kbps).')
        end

        def diagnose_stuck_nack(loss)
          return if @session.data[:status] == 'success'
          stuck = 'Retransmission requests (NACKs) are stuck'
          message =
            if @session.num(:stuck_nack_count) >= 5
              if loss >= 0.4 then "#{stuck}, probably because of the packet loss."
              elsif @session.num(:stuck_rex_count).zero? then "#{stuck}: #{@session.data[:stuck_nack_count]} samples with #{@session.data[:stuck_nack]} pending requests."
              elsif @session.data[:stuck_rex_count] > 5 then "#{stuck}."
              end
            elsif @session.num(:sender_stuck_nack_count) >= 5 && loss.nonzero? then "#{stuck} on the sender, and data packets were lost."
            elsif @session.flag?(:send_nack_stuck) && loss < 0.9 then "#{stuck} on the sender#{', probably lost because of the packet loss' if loss > 0.4}."
            end
          diag(:stuck_nack, :warning, message) if message
        end

        # Small files and file-queue diagnostics, from `DS Qs` lines
        def diagnose_file_pipeline
          count = @session.data[:transfer_stop_count].to_i
          return if count < @thresholds[:small_files_min_count]
          mean = Session.average(@session.sizes).to_i
          return if mean.zero? || mean >= @thresholds[:small_files_max_mean]
          diag(
            :small_files, :warning,
            "#{c(count)} files with a mean size of #{c(mean)} bytes: " \
              'the per-file overhead (open, attributes, close) dominates and limits throughput.'
          )
        end

        private

        # Add a diagnostic
        # @param id       [Symbol] identifier
        # @param severity [Symbol] `error`, `warning` or `info`
        # @param message  [String] description
        def diag(id, severity, message)
          @list.push({'id' => id.to_s, 'severity' => severity.to_s, 'message' => message})
        end

        def c(value)
          Session.commify(value)
        end
      end
    end
  end
end
