module Asperalm
  module Cli
    module Listener
      # imlement this class to get transfer events
      class Base
        # define one of the following methods:
        # event_text(text_data)
        # event_struct(legacy_names)
        # event_enhanced(snake_names)
      end
    end
  end
end
