require 'asperalm/log'
require 'asperalm/fasp/listener/base'

module Asperalm
  module Fasp
    module Listener
      # listener for FASP transfers (debug)
      class Logger < Base
        def event_struct(data)
          Log.log.debug(data.to_s)
        end
      end
    end
  end
end
