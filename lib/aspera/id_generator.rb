# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/environment'
require 'uri'

module Aspera
  class IdGenerator
    class << self
      # Generate an ID from a list of object IDs
      # The generated ID is safe as file name
      # @param object_id [Array<String>, String] the object IDs
      # @return [String] the generated ID
      def from_list(object_id)
        safe_char = Environment.instance.safe_filename_character
        if object_id.is_a?(Array)
          # compact: remove nils
          object_id = object_id.flatten.compact.map do |i|
            i.is_a?(String) && i.start_with?('https://') ? URI.parse(i).host : i.to_s
          end.join(safe_char)
        end
        Aspera.assert_type(object_id, String)
        # keep dot for extension only (nicer)
        return Environment.instance.sanitized_filename(object_id.gsub('.', safe_char)).downcase
      end
    end
  end
end
