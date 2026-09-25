# frozen_string_literal: true

require 'aspera/cli/option_types'
require 'aspera/cli/extended_value'
require 'aspera/cli/deprecation'
require 'aspera/secret_hider'
require 'aspera/schema/registry'
require 'aspera/schema/validator'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/rainbow'
using Rainbow

module Aspera
  module Cli
    # Declared option: type, value, and where the value is stored.
    class OptionValue
      # [Symbol] Name of option
      attr_reader :option
      # [Array<Class>, nil] List of allowed types, `nil` for no validation
      attr_reader :types
      # [Symbol] How values are converted: :flag, :boolean, :integer, :enum, :enum_list, :string_list, :other
      attr_reader :kind
      # [Symbol, nil] `OptionSource` of current value, `nil` if never set
      attr_reader :source
      attr_reader :sensitive, :schema, :deprecation
      # [Array] List of allowed values (Symbols and specific values)
      attr_accessor :values
      # [String] Help section group name (set by OptionRegistry)
      attr_accessor :group
      # [String, nil] Short option char (set by OptionRegistry)
      attr_accessor :short
      # [Proc, nil] Block to call for flag options
      attr_accessor :block

      # @param option [Symbol] Name of option
      # @param description [String, nil] Description for help; if nil, derived from schema
      # @param allowed [nil,Class,Array<Class>,Array<Symbol>] Allowed values
      # @param on_set [#call, nil] Called with the new value each time the value is set
      # @param shorthand [String, nil] For a `Hash` option: a `String` value is stored as `{shorthand => value}`
      # @param deprecation [Hash, Deprecation, nil] Deprecation: `{last:, message:}`, see `Deprecation`
      # @param schema [String] Declaration of schema
      # `allowed`:
      # - `nil` No validation, so just a string
      # - `Class` The single allowed Class
      # - `Array<Class>` Multiple allowed classes
      # - `Array<Symbol>` List of allowed values
      def initialize(option:, description: nil, allowed: Type::STRING, on_set: nil, shorthand: nil, deprecation: nil, schema: nil)
        Log.log.trace1 { "option: #{option}, allowed: #{allowed}" }
        @option = option
        @description = description
        @group = nil
        @short = nil
        @block = nil
        # by default passwords and secrets are sensitive, else specify when declaring the option
        @sensitive = SecretHider.instance.secret?(@option, '')
        @deprecation = Deprecation.create(deprecation)
        @schema = schema
        @shorthand = shorthand
        @source = nil
        @value = nil
        @on_set = nil
        bind_on_set(on_set) unless on_set.nil?
        @types = nil
        @values = nil
        @kind = :other
        allowed = infer_allowed_from_schema(schema, allowed) if schema
        apply_allowed(allowed) unless allowed.nil?
      end

      # Set the `on_set` callback, called with the new value each time the value is set.
      # Safe to call after construction: used by `Parser#on_set` for a target object created after declaration.
      # The callback is called with the current value, if any.
      # @param callback [#call] e.g. a `Method` or a lambda
      # @return [nil]
      def bind_on_set(callback)
        Aspera.assert(callback.respond_to?(:call)) { "#{@option}: on_set callback must respond to call" }
        @on_set = callback
        Log.log.trace1 { "bind_on_set: #{@option}".green }
        @on_set.call(@value) unless @value.nil?
        nil
      end

      # @return [String] description of the option: explicit one, or first line of schema description
      def description
        return @description unless @description.nil?
        return if @schema.nil?
        schema_node = Schema::Registry.instance.reader(@schema).current
        first_line = (schema_node['title'] || schema_node['description'].to_s).lines.first.to_s.strip
        first_line.end_with?('.') ? first_line[0..-2] : first_line
      end

      # @return [Boolean] `true` if option takes no value
      def flag? = @kind.eql?(:flag)

      # @param value [Object] value given to option
      # @return [Boolean] `true` if value asks for the schema of option
      def schema_request?(value) = value.eql?(SchemaRequest::KEYWORD) && @types&.include?(Hash)

      # Reset stored value to nil
      # @return [nil]
      def clear
        store(nil, nil)
      end

      # Get current option value
      # @param log [Boolean] whether to log the value retrieval
      # @return [Object] current value
      def value(log: true)
        Log.log.trace1 { "#{@option} -> (#{@value.class})#{@value}" } if log
        @value
      end

      # Assign value to option.
      # Value can be a `String`, then evaluated with `ExtendedValue`, or directly a value.
      # `Hash` and `Array` values are merged with current value.
      # @param value [String, Object] Value to assign to option
      # @param source [Symbol] `OptionSource` of value
      # @param warn_deprecation [Boolean] Emit deprecation warning (false for internal transfers)
      # @param merge [Boolean] Merge `Hash` and `Array` with current value (false: value is already complete)
      # @return [nil]
      # @raise [SchemaRequest] if value is `help` and schema is known
      def assign_value(value, source:, warn_deprecation: true, merge: true)
        # Value from a source with lower priority than current value: only fills containers
        lower = !@source.nil? && OptionSource.priority(source) < OptionSource.priority(@source)
        if lower && ![Hash, Array].include?(@types&.first)
          Log.log.debug { "#{source}: #{@option}: ignored, already set from #{@source}" }
          return
        end
        Aspera.assert(!@deprecation, type: :warn) { "Option #{@option} is #{@deprecation}" } if warn_deprecation
        if schema_request?(value)
          return if lower
          raise SchemaRequest.new(:option, @option, @schema) unless @schema.nil?
          # Schema depends on command: kept as-is, raised by Parser#get_option(schema:)
          store(value, source)
          return
        end
        new_value = coerce(ExtendedValue.instance.evaluate(value, context: "option: #{@option}", allowed: @types))
        new_value = {@shorthand => new_value} if @shorthand && new_value.is_a?(String)
        Log.log.trace1 { "#{source}: #{@option} <- (#{new_value.class})#{new_value}" }
        Aspera.assert_type(new_value, *@types, type: BadArgument) { "Option #{@option}" } if @types
        if merge && (new_value.is_a?(Hash) || new_value.is_a?(Array))
          current_value = @value
          mergeable = current_value.is_a?(new_value.is_a?(Hash) ? Hash : Array) && !current_value.empty?
          if lower
            # Current value has priority: merge new value under it, unless explicitly emptied
            return unless mergeable
            new_value, current_value = current_value, new_value
            source = @source
          end
          new_value = new_value.is_a?(Hash) ? current_value.deep_merge(new_value) : current_value + new_value if mergeable
        end
        validate_schema(new_value) unless %i[code default].include?(source)
        store(new_value, source)
        nil
      end

      private

      # Validate a structured value against the schema of the option.
      # Value may be partial: completed by other sources or defaults, so `required` is not enforced.
      # @param value [Object] value to validate
      # @raise [BadArgument] if value does not match schema
      def validate_schema(value)
        return unless @schema && (value.is_a?(Hash) || value.is_a?(Array))
        errors = Schema::Validator.instance.errors(value, @schema, partial: true)
        raise BadArgument, "Option #{@option}: #{errors.join('; ')} (use --#{@option.to_s.tr('_', '-')}=#{SchemaRequest::KEYWORD} for schema)" unless errors.empty?
      end

      # Derive the `allowed:` value from the schema when not explicitly provided.
      # Returns `allowed` unchanged when the schema provides no usable type information.
      # @param schema  [String] schema identifier
      # @param allowed [Object] caller-supplied allowed value (may be nil or Type::STRING)
      # @return [Object] resolved allowed (Hash, Array, or the original value)
      def infer_allowed_from_schema(schema, allowed)
        return allowed unless allowed.nil? || allowed.eql?(Type::STRING)

        schema_reader = Schema::Registry.instance.reader(schema) rescue nil
        schema_node   = schema_reader&.current
        return allowed unless schema_node

        case schema_node['type']
        when 'object' then return Hash
        when 'array'  then return Array
        end
        # No top-level type: inspect oneOf/anyOf branches; if all resolve to 'object', infer Hash
        composite_key = (%w[oneOf anyOf] & schema_node.keys).first
        return allowed unless composite_key

        branch_types = schema_node[composite_key].map do |branch|
          resolved = branch['$ref'] ? schema_reader.resolve_ref(branch['$ref']).current : branch
          resolved['type']
        end
        if branch_types.all?('object')
          Hash
        else
          Aspera.assert(
            !allowed.nil? && !allowed.eql?(Type::STRING),
            "option :#{@option}: schema '#{schema}' has mixed-type oneOf branches #{branch_types.uniq}: specify allowed: explicitly"
          )
          allowed
        end
      end

      # Initialize @types, @values and @kind from the resolved `allowed` specifier.
      # @param allowed [Class, Array<Class>, Array<Symbol>] resolved allowed value (never nil)
      def apply_allowed(allowed)
        allowed = [allowed] if allowed.is_a?(Class)
        Aspera.assert_type(allowed, Array)
        if allowed.eql?(Type::NONE)
          @kind = :flag
          @types = Type::NONE
        elsif allowed.take(Type::SYMBOL_ARRAY.length) == Type::SYMBOL_ARRAY
          # Array of defined symbol values
          @kind = :enum_list
          @types = Type::SYMBOL_ARRAY
          @values = allowed[Type::SYMBOL_ARRAY.length..]
        elsif allowed.all?(Symbol)
          @kind = :enum
          @types = Type::ENUM
          @values = allowed
        elsif allowed.all?(Class)
          @types = allowed
          @kind =
            if allowed.sort_by(&:name).eql?(Type::BOOLEAN) then :boolean
            elsif allowed.eql?(Type::INTEGER) then :integer
            elsif allowed.eql?(Type::STRING_ARRAY) then :string_list
            else :other
            end
          @values = BoolValue::ALL if @kind.eql?(:boolean)
        else
          Aspera.error_unexpected_value(allowed)
        end
        # Containers start empty, unless nil is allowed
        default = {Array => [], Hash => {}}[@types.first]
        store(default, :default) if !default.nil? && !@types.include?(NilClass) && @value.nil?
      end

      # Convert value from command line, env or preset (String) to the type of option
      # @param value [Object] evaluated value
      # @return [Object] converted value
      def coerce(value)
        case @kind
        when :enum
          # Boolean from dot-path value, e.g. `no` for `%i[no header read]`
          value = (value ? BoolValue::YES_SYM : BoolValue::NO_SYM).to_s if BoolValue::TYPES.include?(value.class)
          value.is_a?(String) ? Parser.get_from_list(value, @option, @values) : value
        when :boolean
          BoolValue.true?(value.is_a?(String) ? Parser.get_from_list(value, @option, BoolValue::ALL) : value)
        when :integer
          value.nil? ? value : Integer(value)
        when :string_list
          value.is_a?(String) ? [value] : value
        when :enum_list
          value = [value] if value.is_a?(String)
          Aspera.assert_array_all(value, String, type: BadArgument)
          value.map { |v| Parser.get_from_list(v, @option, @values) }
        else
          # nil on a Hash/Array option resets to empty container
          value.nil? && [Hash, Array].include?(@types&.first) ? @types.first.new : value
        end
      end

      # @param new_value [Object] value to store
      # @param source [Symbol, nil] `OptionSource` of value
      def store(new_value, source)
        @value = new_value
        @source = source
        @on_set&.call(new_value)
      end
    end
  end
end
