require 'asperalm/fasp/listener'
require 'ruby-progressbar'

module Asperalm
  module Cli
    module Listener
      # a listener to FASP event that displays a progress bar
      class ProgressMulti < Fasp::Listener
        def initialize
          @progress_bar=nil
          @sessions={}
        end

        BYTE_PER_MEGABIT=1024*1024/8

        def update_total
          @progress_bar.total=@sessions.values.inject(0){|m,s|m+=s[:job_size] if !s[:job_size].nil?;m;}
        end

        def update_progress
          @progress_bar.progress=@sessions.values.inject(0){|m,s|m+=s[:current] if !s[:current].nil?;m;}
        end

        def event_enhanced(data)
          if @progress_bar.nil?
            @progress_bar=ProgressBar.create(
            :format     => '%t %a %B %p%% %r Mbps %e',
            :rate_scale => lambda{|rate|rate/BYTE_PER_MEGABIT},
            :title      => '',
            :total      => nil)
          end
          if !data['session_id'].is_a?(String)
            Log.log.error("no session id in event: #{data}")
            return
          end
          newtitle=@sessions.length < 2 ? '' : "multi=#{@sessions.length}"
          @progress_bar.title=newtitle unless @progress_bar.title.eql?(newtitle)
          session=@sessions[data['session_id']]||={
            cumulative: 0
          }
          case data['type']
          when 'INIT' # connection to ascp (get id)
          when 'SESSION' # session information
          when 'NOTIFICATION' # sent from remote
            if data.has_key?('pre_transfer_bytes') then
              session[:job_size]=data['pre_transfer_bytes']
              update_total
            end
          when 'STATS' # during transfer
            if !@progress_bar.total.nil? then
              if data.has_key?('bytescont')
                session[:current]=session[:cumulative]+data['bytescont'].to_i
                update_progress
              else
                session[:current]=data['transfer_bytes'].to_i
                update_progress
              end
            else
              @progress_bar.increment
            end
          when 'STOP'
            # stop event when one file is completed
            session[:cumulative]=session[:cumulative]+data['size'].to_i
          when 'DONE' # end of session
            @sessions.delete(data['session_id'])
            update_progress
            update_total
            #if @progress_bar.total.nil? then
            #@progress_bar.total=100
            #end
            #@progress_bar.progress=@progress_bar.total
            #@progress_bar=nil
          end
        end
      end
    end
  end
end
