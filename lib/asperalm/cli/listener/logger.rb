require 'asperalm/fasp/listener'
require 'asperalm/log'

module Asperalm
  module Cli
    module Listener
      # listener for FASP transfers (debug)
      class Logger < Fasp::Listener
        def event_struct(data)
          Log.log.debug(data.to_s)
          Log.log.error("#{data['Description']}") if data['Type'].eql?('FILEERROR')
        end

        def event_enhanced(data)
          Log.log.debug(JSON.generate(data))
        end
      end
    end
  end
end
