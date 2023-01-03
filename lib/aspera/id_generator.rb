# frozen_string_literal: true

require 'uri'

module Aspera
  class IdGenerator
    ID_SEPARATOR = '_'
    WINDOWS_PROTECTED_CHAR = %r{[/:"<>\\*?]}.freeze
    PROTECTED_CHAR_REPLACE = '_'
    private_constant :ID_SEPARATOR, :PROTECTED_CHAR_REPLACE, :WINDOWS_PROTECTED_CHAR
    class << self
      def from_list(object_id)
        if object_id.is_a?(Array)
          object_id = object_id.compact.map do |i|
            i.is_a?(String) && i.start_with?('https://') ? URI.parse(i).host : i.to_s
          end.join(ID_SEPARATOR)
        end
        raise 'id must be a String' unless object_id.is_a?(String)
        return object_id.
            gsub(WINDOWS_PROTECTED_CHAR, PROTECTED_CHAR_REPLACE). # remove windows forbidden chars
            gsub('.', PROTECTED_CHAR_REPLACE).  # keep dot for extension only (nicer)
            downcase
      end
    end
  end
end
