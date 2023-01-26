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
          @progress_bar = nil
          @sessions = {}
        end

        def reset
          @progress_bar = nil
          @sessions = {}
        end

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

        def event_enhanced(data)
          if @progress_bar.nil?
            @progress_bar = ProgressBar.create(
              format:      '%t %a %B %p%% %r Mbps %e',
              rate_scale:  lambda{|rate|rate / Environment::BYTES_PER_MEBIBIT},
              title:       '',
              total:       nil)
          end
          if !data.key?(Fasp::AgentBase::LISTENER_SESSION_ID_S)
            Log.log.error{"Internal error: no #{Fasp::AgentBase::LISTENER_SESSION_ID_S} in event: #{data}"}
            return
          end
          newtitle = @sessions.length < 2 ? '' : "multi=#{@sessions.length}"
          @progress_bar.title = newtitle unless @progress_bar.title.eql?(newtitle)
          session = @sessions[data[Fasp::AgentBase::LISTENER_SESSION_ID_S]] ||= {
            cumulative: 0,
            job_size:   0,
            current:    0
          }
          case data['type']
          when 'INIT' # connection to ascp (get id)
          when 'SESSION' # session information
          when 'NOTIFICATION' # sent from remote
            if data.key?('pre_transfer_bytes')
              session[:job_size] = data['pre_transfer_bytes']
              update_total
            end
          when 'STATS' # during transfer
            if @progress_bar.total.nil?
              @progress_bar.increment
            else
              session[:current] = data.key?('bytescont') ? session[:cumulative] + data['bytescont'].to_i : data['transfer_bytes'].to_i
              update_progress
            end
          when 'STOP'
            # stop event when one file is completed
            session[:cumulative] = session[:cumulative] + data['size'].to_i
          when 'DONE' # end of session
            @sessions.delete(data[Fasp::AgentBase::LISTENER_SESSION_ID_S])
            update_progress
            update_total
          else
            Log.log.debug{"ignore: #{data['type']}"}
          end
        end
      end
    end
  end
end
