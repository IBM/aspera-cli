# frozen_string_literal: true

require 'aspera/fasp/listener'
require 'json'

module Aspera
  module Cli
    module Listener
      # listener for FASP transfers (debug)
      # FASP event listener display management events as JSON
      class LineDump < Fasp::Listener
        def event_enhanced(data)
          $stdout.puts(JSON.generate(data))
          $stdout.flush
        end
      end
    end
  end
end
