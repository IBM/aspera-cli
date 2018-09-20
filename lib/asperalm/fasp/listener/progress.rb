require 'asperalm/fasp/listener/base'

module Asperalm
  module Fasp
    module Listener
      # a listener to FASP event that displays a progress bar
      class Progress < Base
        def initialize
          @progress=nil
          @cumulative=0
        end

        BYTE_PER_MEGABIT=1024*1024/8

        def event_struct(data)
          case data['Type']
          when 'NOTIFICATION'
            if data.has_key?('PreTransferBytes') then
              require 'ruby-progressbar'
              @progress=ProgressBar.create(
              :format     => '%a %B %p%% %r Mbps %e',
              :rate_scale => lambda{|rate|rate/BYTE_PER_MEGABIT},
              :title      => 'progress',
              :total      => data['PreTransferBytes'].to_i)
            end
          when 'STOP'
            # stop event when one file is completed
            @cumulative=@cumulative+data['Size'].to_i
          when 'STATS'
            if !@progress.nil? then
              if data.has_key?('Bytescont')
                @progress.progress=@cumulative+data['Bytescont'].to_i
              else
                @progress.progress=data['TransferBytes'].to_i
              end
            else
              puts '.'
            end
          when 'DONE'
            if !@progress.nil? then
              @progress.progress=@progress.total
              @progress=nil
            else
              # terminate progress by going to next line
              puts "\n"
            end
          end
        end
      end
    end
  end
end
