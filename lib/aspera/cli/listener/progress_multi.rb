# frozen_string_literal: true

require 'aspera/fasp/listener'
require 'aspera/fasp/agent_base'
require 'aspera/environment'
require 'ruby-progressbar'

module Aspera
  module Cli
    module Listener
      # a listener to FASP event that displays a progress bar
      class ProgressMulti < Aspera::Fasp::Listener
        def initialize
          super
          reset
        end

        def reset
          @progress_bar = nil
          # key is session id
          @sessions = {}
        end

        def event_enhanced(data)
          return if @progress_bar.eql?(:transfer_complete)
          if @progress_bar.nil?
            @progress_bar = ProgressBar.create(
              format:      '%t %a %B %p%% %r Mbps %E',
              rate_scale:  lambda{|rate|rate / Environment::BYTES_PER_MEBIBIT},
              title:       '',
              total:       nil)
          end
          # check that we have a session id
          session_id = data[Fasp::AgentBase::LISTENER_SESSION_ID_S]
          if session_id.nil?
            Log.log.error{"Internal error: no #{Fasp::AgentBase::LISTENER_SESSION_ID_S} in event: #{data}"}
            return
          end
          new_title = @sessions.length < 2 ? '' : "multi=#{@sessions.length}"
          @progress_bar.title = new_title unless @progress_bar.title.eql?(new_title)
          # get or init the session
          session_info = @sessions[session_id] ||= {
            job_size:   0, # total size of transfer (pre-calc)
            cumulative: 0,
            current:    0
          }
          case data['type']
          when 'INIT' # connection to ascp (get id)
          when 'SESSION' # session information
          when 'NOTIFICATION' # sent from remote
            if data.key?('pre_transfer_bytes')
              session_info[:job_size] = data['pre_transfer_bytes']
              update_total
            end
          when 'STATS' # during transfer
            if @progress_bar.total.nil?
              @progress_bar.increment
            else
              session_info[:current] = data.key?('bytescont') ? session_info[:cumulative] + data['bytescont'].to_i : data['transfer_bytes'].to_i
              update_progress
            end
          when 'STOP'
            # stop event when one file is completed
            session_info[:cumulative] = session_info[:cumulative] + data['size'].to_i
          when 'DONE' # end of session
            # @sessions.delete(session_id)
            update_progress
            update_total
          else
            Log.log.debug{"ignore: #{data['type']}"}
          end
          if @progress_bar.total.eql?(@progress_bar.progress)
            @progress_bar.finish
            @progress_bar = :transfer_complete
          end
        end

        private

        def update_total
          @progress_bar.total = @sessions.values.inject(0){|m, s|m + s[:job_size].to_i}
        rescue StandardError
          nil
        end

        def update_progress
          @progress_bar.progress = @sessions.values.inject(0){|m, s|m + s[:current].to_i}
        rescue StandardError
          nil
        end
      end
    end
  end
end
