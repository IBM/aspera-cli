# frozen_string_literal: true

require 'monitor'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'ruby-progressbar'

module Aspera
  module Cli
    # Progress bar for transfers.
    # Supports multi-session: events may come from several threads.
    # Note that we can have this case:
    # 2 sessions (-C x:2), but one session fails and restarts (resume): it restarts with the same session id.
    # Errors are logged, never raised: the progress bar shall not fail a transfer.
    class TransferProgress
      # Rate is computed on this sliding window
      RATE_WINDOW_SEC = 5.0
      # Rate is not displayed on a shorter period
      RATE_MIN_SEC = 1.0
      # Decimal units, like `ascp`
      KILO = 1000
      BITS_PER_MEGABIT = KILO * KILO
      BYTE_UNITS = %w[B KB MB GB TB PB].freeze
      private_constant :RATE_WINDOW_SEC, :RATE_MIN_SEC, :KILO, :BITS_PER_MEGABIT, :BYTE_UNITS

      class << self
        # @param bytes [Integer] Size in bytes
        # @return [String] Size with decimal unit, e.g. `12.3 MB`
        def format_bytes(bytes)
          value = bytes.to_f
          index = 0
          while value >= KILO && index < BYTE_UNITS.length - 1
            value /= KILO
            index += 1
          end
          return "#{bytes} B" if index.zero?
          format('%.1f %s', value, BYTE_UNITS[index])
        end

        # @param bytes_per_second [Float, nil] Rate, `nil` if unknown
        # @return [String] Rate in megabits per second (decimal, like `ascp`)
        def format_rate(bytes_per_second)
          return '-- Mbps' if bytes_per_second.nil?
          mbps = bytes_per_second * Environment::BITS_PER_BYTE / BITS_PER_MEGABIT
          mbps < 10 ? format('%.2f Mbps', mbps) : format('%.0f Mbps', mbps)
        end

        # @param seconds [Numeric, nil] Duration, `nil` if unknown
        # @return [String] Duration as `hh:mm:ss`
        def format_duration(seconds)
          return '--:--:--' if seconds.nil?
          seconds = seconds.round
          format('%02d:%02d:%02d', seconds / 3600, (seconds / 60) % 60, seconds % 60)
        end
      end

      # @param output [IO] Where the progress bar is displayed: not on `$stdout`, which may be redirected for command output
      def initialize(output: $stderr)
        @output = output
        # Re-entrant, see `suspend`
        @mutex = Monitor.new
        reset_state
      end

      # Reset progress bar, to re-use it.
      def reset
        @mutex.synchronize { reset_state }
      end

      # Called by user of progress bar with a status on a transfer session.
      # Event types:
      # - `sessions_init` : `info` is a status message, displayed until a session starts
      # - `session_start` : a session starts, or restarts (same `session_id`)
      # - `session_size`  : `info` is the total size of the session
      # - `transfer`      : `info` is the number of bytes transferred by the session
      # - `skip`          : `info` is the number of bytes of the session already at destination (not transferred)
      # - `session_end`   : a session ends
      # - `end`           : all sessions are finished, `info` is `false` if the transfer failed
      # @param type       [Symbol]      Event type
      # @param session_id [String, nil] Unique identifier of a transfer session, same when the session is restarted
      # @param info       [Object, nil] Optional specific additional info for the given event type
      def event(type, session_id: nil, info: nil)
        Log.log.trace1 { "progress: #{type} #{session_id} #{info}" }
        @mutex.synchronize { process_event(type, session_id, info) }
      rescue StandardError => e
        Log.log.warn { "Progress bar: #{e.class}: #{e.message}" } unless @error_logged
        @error_logged = true
      end

      # Execute the block with the progress bar cleared, and then display it again.
      # Used to write log lines on the terminal.
      # Does not wait if the progress bar is being updated by another thread (no deadlock with a logger lock).
      def suspend
        return yield unless @mutex.try_enter
        begin
          return yield if @progress_bar.nil? || !@output.tty?
          @progress_bar.clear
          @output.flush
          begin
            yield
          ensure
            @progress_bar.refresh(force: true)
          end
        ensure
          @mutex.exit
        end
      end

      private

      def reset_state
        @progress_bar = nil
        # Key is session id
        @sessions = {}
        # Status displayed before session start
        @title = nil
        # Format currently set on the progress bar
        @format = nil
        # [Integer] Bytes actually transferred, by all sessions, including previous runs of restarted sessions
        @transferred = 0
        # [Array<Array(Float, Integer)>] (time, transferred bytes) on the rate window
        @samples = []
        # [Array(Float, Integer), nil] First sample (data starts to flow, not session start), for average rate
        @start = nil
        @error_logged = false
      end

      # @param type       [Symbol]      Event type
      # @param session_id [String, nil] Session identifier
      # @param info       [Object, nil] Event information
      def process_event(type, session_id, info)
        case type
        when :sessions_init
          # Give opportunity to show progress of initialization with multiple status
          Aspera.assert(session_id.nil?, 'session_id must be nil for :sessions_init event')
          Aspera.assert_type(info, String)
          @title = info
        when :session_start
          Aspera.assert(info.nil?, 'info must be nil for :session_start event')
          start_session(session_id)
          # Remove last pre-start message if any
          @title = nil
        when :session_size
          session(session_id)[:size] = info.to_i unless info.nil?
        when :transfer
          unless info.nil?
            current_session = session(session_id)
            transferred = info.to_i
            @transferred += transferred - current_session[:transferred] if transferred > current_session[:transferred]
            current_session[:transferred] = transferred
            add_sample
          end
        when :skip
          session(session_id)[:skipped] = info.to_i unless info.nil?
        when :session_end
          Aspera.assert(info.nil?, 'info must be nil for :session_end event')
          # A session may be too short and finish before it has been started
          @sessions[session_id][:running] = false if @sessions.key?(session_id)
        when :end
          Aspera.assert(session_id.nil?, 'session_id must be nil for :end event')
          Aspera.assert_values(info, [nil, true, false]) { ':end event info' }
          begin
            finish(success: !info.eql?(false))
          ensure
            reset_state
          end
          return
        else Aspera.error_unexpected_value(type) { 'event type' }
        end
        display
      end

      # @param session_id [String] Session identifier
      # @return [Hash] Session information, created if not already started
      def session(session_id)
        Aspera.assert_type(session_id, String)
        @sessions[session_id] ||= {
          size:        nil, # Total size of session, `nil` if unknown
          transferred: 0,   # Bytes transferred
          skipped:     0,   # Bytes already at destination
          floor:       0,   # Progress reached before restart of session
          running:     true
        }
      end

      # Start a session, or restart it: a restarted session notifies again its progress from zero
      # @param session_id [String] Session identifier
      def start_session(session_id)
        restarted = @sessions.key?(session_id)
        current_session = session(session_id)
        if restarted
          current_session[:floor] = done_bytes(current_session)
          current_session[:transferred] = 0
          current_session[:skipped] = 0
        end
        current_session[:running] = true
      end

      # @param session [Hash] Session information
      # @return [Integer] Bytes processed by the session (transferred or skipped), not more than its size
      def done_bytes(session)
        done = [session[:floor], session[:transferred] + session[:skipped]].max
        session[:size].nil? ? done : [done, session[:size]].min
      end

      # @return [Integer] Bytes processed by all sessions
      def current_bytes
        @sessions.each_value.sum { |s| done_bytes(s) }
      end

      # @return [Integer, nil] Total size of all sessions, `nil` if unknown for one of them
      def total_bytes
        return if @sessions.empty? || @sessions.each_value.any? { |s| s[:size].nil? }
        @sessions.each_value.sum { |s| s[:size] }
      end

      # @return [Float] Monotonic time in seconds
      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Record transferred bytes for rate computation
      # @return [Array(Float, Integer)] The new sample
      def add_sample
        sample = [now, @transferred]
        @start ||= sample
        @samples.push(sample)
        # Keep one sample older than the window
        @samples.shift while @samples.length > 2 && @samples[1].first <= sample.first - RATE_WINDOW_SEC
        sample
      end

      # @return [Float, nil] Rate on the sliding window, in bytes per second, `nil` if unknown
      def rate
        return if @samples.length < 2
        elapsed = @samples.last.first - @samples.first.first
        return if elapsed < RATE_MIN_SEC
        (@samples.last.last - @samples.first.last) / elapsed
      end

      # @return [Float, nil] Average rate between first and last sample, in bytes per second, `nil` if unknown
      def average_rate
        return if @start.nil?
        last = @samples.last
        elapsed = last.first - @start.first
        return unless elapsed.positive?
        (last.last - @start.last) / elapsed
      end

      # Update the progress bar with current state
      def display
        if @progress_bar.nil?
          @progress_bar = ProgressBar.create(output: @output, format: '%a %B', total: nil, autofinish: false, throttle_rate: 0)
          @format = '%a %B'
        end
        current = current_bytes
        total = total_bytes
        update_bar(total, current)
        fields = ['%a', '%B']
        unless @sessions.empty?
          bytes_per_second = rate
          # Fixed width, so that bar does not change size
          rate_text = self.class.format_rate(bytes_per_second).rjust(11)
          if total.nil?
            fields.push(self.class.format_bytes(current).rjust(8), rate_text)
          else
            eta = bytes_per_second&.positive? ? (total - current) / bytes_per_second : nil
            fields.push('%j%%', rate_text, "ETA: #{self.class.format_duration(eta)}")
          end
        end
        update_format(title_text(final: false), fields)
      end

      # Display final state of the progress bar
      # @param success [Boolean] `false` if the transfer failed: progress is not completed
      def finish(success:)
        return if @progress_bar.nil?
        current = current_bytes
        total = total_bytes
        if success
          total ||= current
          current = total
        end
        fields = ['%a']
        unless total.nil?
          update_bar(total, current)
          fields.push('%B', '%j%%')
        end
        fields.push(self.class.format_bytes(current), self.class.format_rate(average_rate)) unless @sessions.empty?
        # Last status (e.g. `running`) is no more relevant
        @title = success ? nil : 'failed'
        # Final line may be shorter (no bar)
        @progress_bar.clear
        update_format(title_text(final: true), fields)
        success ? @progress_bar.finish : @progress_bar.stop
      end

      # Set total and progress of the bar, in an order accepted by `ruby-progressbar`
      # @param total   [Integer, nil] Total size, `nil` if unknown
      # @param current [Integer]      Processed bytes
      def update_bar(total, current)
        if total.nil?
          # Unknown total: progress of the bar is used for animation only
          @progress_bar.total = nil unless @progress_bar.total.nil?
          @progress_bar.increment
        elsif total >= @progress_bar.progress
          @progress_bar.total = total unless @progress_bar.total.eql?(total)
          @progress_bar.progress = current unless @progress_bar.progress.eql?(current)
        else
          @progress_bar.progress = current
          @progress_bar.total = total
        end
      end

      # @param final [Boolean] `true` for the final display
      # @return [String] Title of the progress bar, with number of running sessions if several sessions
      def title_text(final:)
        parts = []
        running = @sessions.count { |_, s| s[:running] }
        parts.push("[#{running}]") if !final && running.positive? && @sessions.length > 1
        parts.push(@title) unless @title.to_s.empty?
        parts.join(' ')
      end

      # Change format of the bar, if changed
      # @param title  [String]        Literal text
      # @param fields [Array<String>] `ruby-progressbar` format elements
      def update_format(title, fields)
        new_format = (title.empty? ? fields : [title.gsub('%', '%%'), *fields]).join(' ')
        return if new_format.eql?(@format)
        @progress_bar.format = new_format
        @format = new_format
      end
    end
  end
end
