require 'asperalm/fasp/listener'
require 'ruby-progressbar'

module Asperalm
  module Cli
    module Listener
      # a listener to FASP event that displays a progress bar
      class ProgressMulti < Fasp::Listener
        def initialize
          @progress=nil
          @cumulative=0
        end

        BYTE_PER_MEGABIT=1024*1024/8

        def event_enhanced(data)
          if @progress.nil?
            @progress=ProgressBar.create(
            :format     => '%a %B %p%% %r Mbps %e',
            :rate_scale => lambda{|rate|rate/BYTE_PER_MEGABIT},
            :title      => 'progress',
            :total      => nil)
          end
          case data['type']
          when 'INIT' # connection to ascp (get id)
          when 'SESSION' # session information
          when 'NOTIFICATION' # sent from remote
            if data.has_key?('pre_transfer_bytes') then
              @progress.total=data['pre_transfer_bytes']
            end
          when 'STATS' # during transfer
            if @progress.total.nil? then
              if data.has_key?('bytescont')
                @progress.progress=@cumulative+data['bytescont'].to_i
              else
                @progress.progress=data['transfer_bytes'].to_i
              end
            else
              @progress.increment
            end
          when 'STOP'
            # stop event when one file is completed
            @cumulative=@cumulative+data['size'].to_i
          when 'DONE' # end of session
            if @progress.total.nil? then
              @progress.total=100
            end
            @progress.progress=@progress.total
            #@progress=nil
          end
        end
      end
    end
  end
end
