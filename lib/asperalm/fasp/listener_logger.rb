require 'asperalm/log'
require 'asperalm/fasp/listener'
module Asperalm
  module Fasp
    # listener for FASP transfers (debug)
    class ListenerLogger < Listener
      def event(data)
        Log.log.debug(data.to_s)
      end
    end
  end
end
