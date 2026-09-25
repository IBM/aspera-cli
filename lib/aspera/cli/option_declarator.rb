# frozen_string_literal: true

require 'aspera/cli/parser'
require 'aspera/cli/command_spec'

module Aspera
  module Cli
    # Mixin providing declarative CLI option definitions (`option :name, ...`)
    # and batch declaration onto a Parser instance (`declare_options(parser)`).
    module OptionDeclarator
      # Registry of OptionSpec objects defined on this class/module.
      # @return [Hash{Symbol => OptionSpec}]
      def option_specs
        @option_specs ||= {}
      end

      # Declare an option in this class's registry.
      #
      # @param name        [Symbol]                  Option name
      # @param description [String, nil]             User-facing description; if nil, derived from schema: title/description
      # @param short       [String, nil]             Single-character short form (without leading '-')
      # @param allowed     [Object, nil]             Allowed values (see OptionValue)
      # @param default     [Object, nil]             Default value
      # @param on_set     [Symbol, Proc, #call, nil] `on_set` callback (see OptionSpec)
      # @param shorthand   [String, nil]             For a `Hash` option: a `String` value is stored as `{shorthand => value}`
      # @param deprecation [Hash, nil]               Deprecation `{last:, message:}` forwarded to options.declare (see `Deprecation`)
      # @param schema      [String, nil]             Schema reference (e.g. "opts:components.schemas.Foo");
      #                                              when description: is nil, the schema title or first description line is used
      def option(name, description: nil,
        short: nil, allowed: nil, default: nil,
        on_set: nil, shorthand: nil, deprecation: nil, schema: nil)
        register_option_spec(
          OptionSpec.new(
            name:        name,
            description: description,
            short:       short,
            allowed:     allowed,
            default:     default,
            on_set:      on_set,
            shorthand:   shorthand,
            deprecation: deprecation,
            schema:      schema
          )
        )
      end

      # Store an OptionSpec in this class's registry.
      # @param spec [OptionSpec]
      # @raise [ArgumentError] on duplicate option name
      def register_option_spec(spec)
        raise ArgumentError, "Duplicate option: #{spec.name.inspect}" if option_specs.key?(spec.name)
        option_specs[spec.name] = spec
      end

      # Declare all options registered on this class onto a Parser instance.
      # Skips options already declared on the parser.
      #
      # @param parser [Aspera::Cli::Parser]
      # @param target [Object, nil] default target object for Symbol and Proc `on_set` callbacks (defaults to self)
      # @return [void]
      def declare_options(parser, target: self)
        option_specs.each_value do |spec|
          spec.declare_on(parser, target: target) unless parser.option_declared?(spec.name)
        end
      end
    end
  end
end
