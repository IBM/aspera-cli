# frozen_string_literal: true

module Aspera
  module Keychain
    class Base
      CONTENT_KEYS = %i[label username password url description].freeze
      def validate_set(options)
        Aspera.assert_type(options, Hash){'options'}
        unsupported = options.keys - CONTENT_KEYS
        Aspera.assert(unsupported.empty?){"unsupported options: #{unsupported}, use #{CONTENT_KEYS.join(', ')}"}
        options.each_pair do |k, v|
          Aspera.assert_type(v, String){k.to_s}
        end
        Aspera.assert(options.key?(:label)){'label is required'}
      end
    end
  end
end
