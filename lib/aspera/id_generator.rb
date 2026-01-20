# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/environment'
require 'uri'

module Aspera
  class IdGenerator
    class << self
      # Generate an ID from a list of object IDs
      # The generated ID is safe as file name
      # @param ids [Array] the object IDs (can be nested, will be flattened, and nils removed)
      # @return [String] the generated ID
      def from_list(*ids)
        safe_char = Environment.instance.safe_filename_character
        # compact: remove nils
        id = ids.flatten.compact.map do |i|
          i.is_a?(String) && i.start_with?('https://') ? URI.parse(i).host : i.to_s
        end.join(safe_char)
        # keep dot for extension only (nicer)
        return Environment.instance.sanitized_filename(id.gsub('.', safe_char)).downcase
      end
    end
  end
end
