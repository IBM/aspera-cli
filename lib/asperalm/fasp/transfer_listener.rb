module Asperalm
  module Fasp
    # imlement this class to get transfer events
    class TransferListener
      def event(data)
        raise 'must be defined'
      end
    end
  end
end
