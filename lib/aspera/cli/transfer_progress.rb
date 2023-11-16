# frozen_string_literal: true

require 'ruby-progressbar'

module Aspera
  module Cli
    # progress bar for transfers, supports multi-session
    class TransferProgress
      def initialize
        reset
      end

      def reset
        @progress_bar = nil
        # key is session id
        @sessions = {}
        @completed = false
        @title = ''
      end

      def total(key)
        @sessions.values.inject(0){|m, s|m + s[key]}
      end

      def event(session_id:, type:, info: nil)
        Log.log.debug{"progress: #{type} #{session_id} #{info}"}
        if session_id.nil? && !type.eql?(:pre_start)
          raise 'Internal error: session_id is nil'
        end
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
          @title = info
        when :session_start
          raise "Session #{session_id} already started" if @sessions[session_id]
          @sessions[session_id] = {
            job_size: 0, # total size of transfer (pre-calc)
            current:  0
          }
          @title = ''
        when :session_size
          @sessions[session_id][:job_size] = info.to_i
          current_total = total(:job_size)
          @progress_bar.total = current_total unless current_total.eql?(@progress_bar.total) || current_total < @progress_bar.progress
        when :transfer
          if !@progress_bar.total.nil?
            need_increment = false
            @sessions[session_id][:current] = info.to_i
            current_total = total(:current)
            @progress_bar.progress = current_total unless @progress_bar.progress.eql?(current_total)
          end
        when :end
          @title = ''
          @completed = true
          @progress_bar.finish
        else
          raise "Unknown event type #{type}"
        end
        new_title = @sessions.length < 2 ? @title : "[#{@sessions.length}] #{@title}"
        @progress_bar.title = new_title unless @progress_bar.title.eql?(new_title)
        @progress_bar.increment if need_increment && !@completed
      end
    end
  end
end
