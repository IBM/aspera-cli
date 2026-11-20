# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'environment'
require 'uri'

module Aspera
  class IdGenerator
    class << self
      # Generate an ID from a list of object IDs
      # The generated ID is safe as file name
      # In URLs keep only the host name, we assume only one instance on a given host.
      # @param ids [Array] the object IDs (can be nested, will be flattened, and nils removed)
      # @return [String] the generated ID
      def from_list(*ids)
        safe_char = Environment.instance.safe_filename_character
        # compact: remove nils
        id = ids.flatten.compact.map { |i| host_or_text(i) }.join(safe_char)
        # keep dot for extension only (nicer)
        return Environment.instance.sanitized_filename(id.gsub('.', safe_char)).downcase
      end

      private

      # A valid HTTP(S) URL with a host: its host name.
      # Any other value is kept as text, e.g. an OAuth scope of several URLs separated by spaces, or an invalid URL.
      # @param value [Object] one object ID
      # @return [String] the host name, or the value as text
      def host_or_text(value)
        return value.to_s unless value.is_a?(String)
        # A plain identifier also parses (as URI::Generic, without host): check the class (URI::HTTPS is a URI::HTTP) and the host
        uri = URI.parse(value)
        uri.is_a?(URI::HTTP) && !uri.host.to_s.empty? ? uri.host : value
      rescue URI::InvalidURIError
        value
      end
    end
  end
end
