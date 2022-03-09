# frozen_string_literal: true
require 'aspera/fasp/listener'
require 'ruby-progressbar'

module Aspera
  module Cli
    module Listener
      # a listener to FASP event that displays a progress bar
      class Progress < Fasp::Listener
        def initialize
          super
          @progress=nil
          @cumulative=0
        end

        BYTE_PER_MEGABIT=(1024*1024)/8

        def event_struct(data)
          case data['Type']
          when 'NOTIFICATION'
            if data.has_key?('PreTransferBytes')
              @progress=ProgressBar.create(
              format:      '%a %B %p%% %r Mbps %e',
              rate_scale:  lambda{|rate|rate/BYTE_PER_MEGABIT},
              title:       'progress',
              total:       data['PreTransferBytes'].to_i)
            end
          when 'STOP'
            # stop event when one file is completed
            @cumulative+=data['Size'].to_i
          when 'STATS'
            if @progress.nil?
              puts '.'
            else
              @progress.progress=data.has_key?('Bytescont') ? @cumulative+data['Bytescont'].to_i : data['TransferBytes'].to_i
            end
          when 'DONE'
            if @progress.nil?
              # terminate progress by going to next line
              puts "\n"
            else
              @progress.progress=@progress.total
              @progress=nil
            end
          end
        end
      end
    end
  end
end
