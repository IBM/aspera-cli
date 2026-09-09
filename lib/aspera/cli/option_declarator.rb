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
      # @param name        [Symbol]          Option name
      # @param description [String, nil]     User-facing description
      # @param short       [String, nil]     Single-character short form
      # @param allowed     [Object, nil]     Allowed values
      # @param default     [Object, nil]     Default value
      # @param handler     [Symbol, Hash, nil] Handler (Symbol or Hash)
      # @param deprecation [String, nil]     Deprecation message
      # @param schema      [String, nil]     Schema reference
      def option(name, description: nil,
        short: nil, allowed: nil, default: nil,
        handler: nil, deprecation: nil, schema: nil)
        raise ArgumentError, "Duplicate option: #{name.inspect}" if option_specs.key?(name)
        option_specs[name] = OptionSpec.new(
          name:        name,
          description: description,
          short:       short,
          allowed:     allowed,
          default:     default,
          handler:     handler,
          deprecation: deprecation,
          schema:      schema
        )
      end

      # Declare all options registered on this class onto a Parser instance.
      # Skips options already declared on the parser.
      #
      # @param parser [Aspera::Cli::Parser]
      # @param target [Object, nil] default target object for Symbol handlers (defaults to self)
      # @return [void]
      def declare_options(parser, target: self)
        option_specs.each_value do |spec|
          next if parser.option_declared?(spec.name)
          resolved_handler =
            case spec.handler
            when Symbol then {o: target, m: spec.handler}
            when Hash   then spec.handler
            end
          parser.declare(
            spec.name,
            description: spec.description,
            short:       spec.short,
            allowed:     spec.allowed,
            default:     spec.default,
            handler:     resolved_handler,
            deprecation: spec.deprecation,
            schema:      schema_for_spec(spec)
          )
        end
      end

      private

      def schema_for_spec(spec)
        spec.schema
      end
    end
  end
end
