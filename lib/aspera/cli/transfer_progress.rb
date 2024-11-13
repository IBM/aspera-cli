# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'ruby-progressbar'

module Aspera
  module Cli
    # Progress bar for transfers.
    # Supports multi-session.
    class TransferProgress
      def initialize
        reset
      end

      # Reset progress bar, to re-use it.
      def reset
        @progress_bar = nil
        # key is session id
        @sessions = {}
        @completed = false
        @title = nil
      end

      # Called by user of progress bar with a status on a transfer session
      # @param session_id the unique identifier of a transfer session
      # @param type one of: pre_start, session_start, session_size, transfer, end
      # @param info optional specific additional info for the given event type
      def event(type, session_id:, info: nil)
        Log.log.trace1{"progress: #{type} #{session_id} #{info}"}
        return if @completed
        if @progress_bar.nil?
          @progress_bar = ProgressBar.create(
            format:      '%t %a %B %p%% %r Mbps %E',
            rate_scale:  lambda{|rate|rate / Environment::BYTES_PER_MEBIBIT},
            title:       '',
            total:       nil)
        end
        need_increment = true
        case type
        when :pre_start
          # give opportunity to show progress of initialisation with multiple status
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
            current:  0
          }
          # remove last pre-start message if any
          @title = nil
        when :session_size
          Aspera.assert_type(session_id, String)
          Aspera.assert(!info.nil?)
          @sessions[session_id][:job_size] = info.to_i
          current_total = total(:job_size)
          @progress_bar.total = current_total unless current_total.eql?(@progress_bar.total) || current_total < @progress_bar.progress
        when :transfer
          Aspera.assert_type(session_id, String)
          Aspera.assert(!info.nil?)
          if !@progress_bar.total.nil?
            need_increment = false
            @sessions[session_id][:current] = info.to_i
            current_total = total(:current)
            @progress_bar.progress = current_total unless @progress_bar.progress.eql?(current_total)
          end
        when :end
          Aspera.assert(session_id, String)
          Aspera.assert(info.nil?)
          @title = nil
          @completed = true
          @progress_bar.finish
        else
          raise "Unknown event type #{type}"
        end
        new_title = @sessions.length < 2 ? @title.to_s : "[#{@sessions.length}] #{@title}"
        @progress_bar.title = new_title unless @progress_bar.title.eql?(new_title)
        @progress_bar.increment if need_increment && !@completed
      end

      private

      def total(key)
        @sessions.values.inject(0){|m, s|m + s[key]}
      end
    end
  end
end
