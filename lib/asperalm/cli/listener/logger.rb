require 'asperalm/fasp/listener'
require 'asperalm/log'

module Asperalm
  module Cli
    module Listener
      # listener for FASP transfers (debug)
      class Logger < Fasp::Listener
        def event_struct(data)
          Log.log.debug(data.to_s)
        end
      end
    end
  end
end
