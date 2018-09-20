require 'asperalm/cli/listener/base'
require 'json'

module Asperalm
  module Cli
    module Listener
      # listener for FASP transfers (debug)
      # FASP event listener display management events as JSON
      class LineDump < Base
        def event_enhanced(data)
          STDOUT.puts(JSON.generate(data))
          STDOUT.flush
        end
      end
    end
  end
end
