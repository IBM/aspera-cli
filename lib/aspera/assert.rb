# frozen_string_literal: true

class Object
  def assert(assertion, info = nil)
    raise 'INTERNAL ERROR: bad assert: both info and block given' unless info.nil? || !block_given?
    return if assertion
    message = 'INTERNAL ERROR: assertion failed'
    info = yield if block_given?
    message = "#{message}: #{info}" if info
    message = "#{message}: #{caller(1..1).first}"
    raise message
  end

  def assert_type(value, type)
    assert(value.is_a?(type)){"expecting #{type}, but have #{value.class}: #{value.inspect}"}
  end
end
