# frozen_string_literal: true

module Aspera
  # Generic error in gem
  class Error < StandardError
  end

  # Error that shall not happen, else it's a bug
  class InternalError < Error
  end

  # An expected condition was not met
  class AssertError < Error
  end
  class << self
    # Assert that a condition is true, else raise exception
    # @param assertion [Bool]       Must be true
    # @param info      [String,nil] Fixed message in case assert fails
    # @param type      [Exception]  Exception to raise
    # @param block     [Proc]       Like info, a string that desribes the problem
    # The block is executed in the context of the Aspera module
    def assert(assertion, info = nil, type: AssertError)
      raise InternalError, 'bad assert: both info and block given' unless info.nil? || !block_given?
      return if assertion
      message = 'assertion failed'
      info = yield if block_given?
      message = "#{message}: #{info}" if info
      message = "#{message}: #{caller.find{ |call| !call.start_with?(__FILE__)}}"
      raise type, message
    end

    # Assert that value has the given type
    # @param value [Object] the value to check
    # @param classes [Class, Array] the expected type(s)
    def assert_type(value, *classes, type: AssertError)
      assert(classes.any?{ |k| value.is_a?(k)}, type: type){"#{"#{yield}: " if block_given?}expecting #{classes.join(', ')}, but have #{value.inspect}"}
    end

    # Assert that value is one of the given values
    # @param value value to check
    # @param values accepted values
    # @param type exception in case of no match
    def assert_values(value, values, type: AssertError)
      assert(values.include?(value), type: type) do
        val_list = values.inspect
        val_list = "one of #{val_list}" if values.is_a?(Array)
        "#{"#{yield}: " if block_given?}expecting #{val_list}, but have #{value.inspect}"
      end
    end

    # The line with this shall never be reached
    def error_unreachable_line
      raise InternalError, "unreachable line reached: #{caller(2..2).first}"
    end

    # The value is not one of the expected values
    # @param value the wrong value
    # @param type exception to raise
    # @param block additional description in front
    def error_unexpected_value(value, type: InternalError)
      raise type, "#{"#{yield}: " if block_given?}unexpected value: #{value.inspect}"
    end

    # Not implemented error
    def error_not_implemented
      raise Error, 'Feature not yet implemented'
    end

    # Use in superclass to require the given method in subclass.
    def require_method!(name)
      define_method(name) do |*_args|
        raise NotImplementedError, "#{self.class} must implement the #{name} method"
      end
    end
  end
end
