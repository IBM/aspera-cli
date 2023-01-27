# frozen_string_literal: true

module Aspera
  module Fasp
    # implement this class to get transfer events
    class Listener # rubocop:disable Lint/EmptyClass
      # define one of the following methods:
      # event_text(text_data)
      # event_struct(legacy_names)
      # event_enhanced(snake_names)
    end
  end
end
