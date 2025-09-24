# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'ruby-progressbar'

module Aspera
  module Cli
    # Progress bar for transfers.
    # Supports multi-session.
    # Note that we can have this case:
    # 2 sessions (-C x:2), but one session fails and restarts...
    class TransferProgress
      def initialize
        @progress_bar = nil
        # key is session id
        @sessions = {}
        @completed = false
        @title = nil
      end

      # Reset progress bar, to re-use it.
      def reset
        send(:initialize)
      end

      # Called by user of progress bar with a status on a transfer session
      # @param session_id the unique identifier of a transfer session
      # @param type [Symbol] one of: sessions_init, session_start, session_size, transfer, session_end and end
      # @param info optional specific additional info for the given event type
      def event(type, session_id: nil, info: nil)
        Log.log.trace1{"progress: #{type} #{session_id} #{info}"}
        return if @completed
        if @progress_bar.nil?
          @progress_bar = ProgressBar.create(
            format:      '%t %a %B %p%% %r Mbps %E',
            rate_scale:  lambda{ |rate| rate / Environment::BYTES_PER_MEBIBIT},
            title:       '',
            total:       nil
          )
        end
        progress_provided = false
        case type
        when :sessions_init
          # give opportunity to show progress of initialization with multiple status
          Aspera.assert(session_id.nil?)
          Aspera.assert_type(info, String)
          # initialization of progress bar
          @title = info
        when :session_start
          Aspera.assert_type(session_id, String)
          Aspera.assert(info.nil?)
          raise "Session #{session_id} already started" if @sessions[session_id]
          @sessions[session_id] = {
            job_size: 0, # total size of transfer (pre-calc)
            current:  0,
            running:  true
          }
          # remove last pre-start message if any
          @title = nil
        when :session_size
          Aspera.assert_type(session_id, String)
          Aspera.assert(!info.nil?)
          Aspera.assert_type(@sessions[session_id], Hash)
          @sessions[session_id][:job_size] = info.to_i
          sessions_total = total(:job_size)
          @progress_bar.total = sessions_total unless sessions_total.eql?(@progress_bar.total) || sessions_total < @progress_bar.progress
        when :transfer
          Aspera.assert_type(session_id, String)
          Aspera.assert_type(@sessions[session_id], Hash)
          if !@progress_bar.total.nil? && !info.nil?
            progress_provided = true
            @sessions[session_id][:current] = info.to_i
            sessions_current = total(:current)
            @progress_bar.progress = sessions_current unless @progress_bar.progress.eql?(sessions_current) || sessions_current > total(:job_size)
          end
        when :session_end
          Aspera.assert_type(session_id, String)
          Aspera.assert(info.nil?)
          # a session may be too short and finish before it has been started
          @sessions[session_id][:running] = false if @sessions[session_id].is_a?(Hash)
        when :end
          Aspera.assert(session_id.nil?)
          Aspera.assert(info.nil?)
          @progress_bar.finish
        else Aspera.error_unexpected_value(type){'event type'}
        end
        new_title = @sessions.length < 2 ? @title.to_s : "[#{@sessions.count{ |_i, d| d[:running]}}] #{@title}"
        @progress_bar&.title = new_title unless @progress_bar&.title.eql?(new_title)
        @progress_bar&.increment if !progress_provided && @progress_bar.progress.nil?
      rescue ProgressBar::InvalidProgressError => e
        Log.log.error{"Progress error: #{e}"}
      end

      private

      def total(key)
        @sessions.values.inject(0){ |m, s| m + s[key]}
      end
    end
  end
end
