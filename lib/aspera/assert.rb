# frozen_string_literal: true

module Aspera
  class InternalError < StandardError
  end

  class AssertError < InternalError
  end
end

class Object
  def assert(assertion, info = nil)
    raise Aspera::InternalError, 'bad assert: both info and block given' unless info.nil? || !block_given?
    return if assertion
    message = 'assertion failed'
    info = yield if block_given?
    message = "#{message}: #{info}" if info
    message = "#{message}: #{caller(2..2).first}"
    raise Aspera::AssertError, message
  end

  # assert that value has the given type
  # @param value [Object] the value to check
  # @param type [Class] the expected type
  def assert_type(value, type)
    assert(value.is_a?(type)){"expecting #{type}, but have #{value.inspect}"}
  end

  # the line with this shall never be reached
  def error_unreachable_line
    raise Aspera::InternalError, "unreachable line reached: #{caller(2..2).first}"
  end

  # assert that value is one of the given values
  def assert_values(value, values)
    assert(values.include?(value)){"expecting one of #{values.inspect}, but have #{value.inspect}"}
  end

  # the value is not one of the expected values
  def error_unexpected_value(value)
    raise Aspera::InternalError, "unexpected value: #{value.inspect}"
  end
end
