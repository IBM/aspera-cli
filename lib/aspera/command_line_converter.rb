# frozen_string_literal: true

require 'aspera/assert'
module Aspera
  # conversion class for transfer spec values to CLI values (ascp)
  class CommandLineConverter
    class << self
      # special encoding methods used in YAML (key: convert)
      def remove_hyphen(value); value.tr('-', ''); end

      # special encoding methods used in YAML (key: convert)
      def json64(value); Base64.strict_encode64(JSON.generate(value)); end

      # special encoding methods used in YAML (key: convert)
      def base64(value); Base64.strict_encode64(value); end

      # transform yes/no to true/false
      def yes_to_true(value)
        case value
        when 'yes' then return true
        when 'no' then return false
        else Aspera.error_unexpected_value(value){'only: yes or no: '}
        end
      end

      def kbps_to_bps(value)
        1000 * value
      end
    end
  end
end
