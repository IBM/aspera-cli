# frozen_string_literal: true

module Aspera
  class InternalError < StandardError
  end

  class AssertError < StandardError
  end
  class << self
    # the block is executed in the context of the Aspera module
    def assert(assertion, info = nil, level: 2, exception_class: AssertError)
      raise InternalError, 'bad assert: both info and block given' unless info.nil? || !block_given?
      return if assertion
      message = 'assertion failed'
      info = yield if block_given?
      message = "#{message}: #{info}" if info
      message = "#{message}: #{caller(level..level).first}"
      raise exception_class, message
    end

    # assert that value has the given type
    # @param value [Object] the value to check
    # @param type [Class] the expected type
    def assert_type(value, type, exception_class: AssertError)
      assert(value.is_a?(type), level: 3, exception_class: exception_class){"#{block_given? ? "#{yield}: " : nil}expecting #{type}, but have #{value.inspect}"}
    end

    # assert that value is one of the given values
    def assert_values(value, values, exception_class: AssertError)
      assert(values.include?(value), level: 3, exception_class: exception_class) do
        "#{block_given? ? "#{yield}: " : nil}expecting one of #{values.inspect}, but have #{value.inspect}"
      end
    end

    # the line with this shall never be reached
    def error_unreachable_line
      raise InternalError, "unreachable line reached: #{caller(2..2).first}"
    end

    # the value is not one of the expected values
    def error_unexpected_value(value, exception_class: InternalError)
      raise exception_class, "#{block_given? ? "#{yield}: " : nil}unexpected value: #{value.inspect}"
    end
  end
end
