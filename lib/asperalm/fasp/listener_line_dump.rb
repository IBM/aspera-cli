require 'asperalm/fasp/listener'
require 'json'

module Asperalm
  module Fasp
    # listener for FASP transfers (debug)
    # FASP event listener display management events as JSON
    class ListenerLineDump < Listener
      def event(data)
        STDOUT.puts(JSON.generate(data))
        STDOUT.flush
      end
    end
  end
end
