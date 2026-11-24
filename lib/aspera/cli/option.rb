# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

module Aspera
  module Cli
    # Declares an option referenced by name from command declarations.
    # Mirrors the existing `options.declare` call but associates the option with
    # the command(s) that use it.
    #
    # @!attribute name        [Symbol]               Option name (same symbol used in options.declare)
    # @!attribute description [String, nil]          User-facing description; nil derives it from schema:
    # @!attribute allowed     [Array, nil]           Allowed values (forwarded to options.declare)
    # @!attribute default     [Object, nil]          Default value
    # @!attribute short       [String, nil]          Single-character short form (e.g. 'x')
    # @!attribute on_set     [Symbol, Proc, #call, nil] Called with the new value each time the value is set
    #   (for a flag: called without argument when the flag is found)
    #   - Symbol: method of the plugin instance
    #   - Proc:   executed with instance_exec on the plugin instance
    #   - other:  object responding to `call`, e.g. `Log.instance.method(:level=)`
    #   - nil:    no callback, the value is read with `get_option`
    # @!attribute shorthand   [String, nil]          For a `Hash` option: a `String` value is stored as `{shorthand => value}`
    # @!attribute deprecation [Hash, nil]            Forwarded to options.declare as deprecation: `{last:, message:}`
    # @!attribute schema      [String, nil]          JSON schema name; also derives description when nil
    # @!attribute complete    [Symbol, nil]          Values proposed by shell completion, one of `Complete::KINDS` (e.g. `:file`)
    # @!attribute security    [Symbol, nil]          Most restrictive security level at which the option is available (`:low`: executes code), see `Security`
    Option = Struct.new(
      :name,
      :description,
      :allowed,
      :default,
      :short,
      :on_set,
      :shorthand,
      :deprecation,
      :schema,
      :complete,
      :security,
      keyword_init: true
    ) do
      # Declare this option on a parser, resolving the `on_set` callback.
      # @param parser [Parser] Parser to declare the option on
      # @param target [Object, nil] Object for Symbol and Proc `on_set` callbacks (plugin instance); nil: such callbacks are not bound
      # @return [void]
      def declare_on(parser, target: nil)
        parser.declare(
          name,
          description: description,
          short:       short,
          allowed:     allowed,
          default:     default,
          on_set:      resolved_on_set(target),
          shorthand:   shorthand,
          deprecation: deprecation,
          schema:      schema,
          complete:    complete,
          security:    security
        )
      end

      private

      # @param target [Object, nil] Object for Symbol and Proc `on_set` callbacks
      # @return [#call, nil] `on_set` callback for `Parser#declare`
      def resolved_on_set(target)
        case on_set
        when Symbol then target&.method(on_set)
        when Proc
          return if target.nil?
          proc_on_set = on_set
          ->(*value) { target.instance_exec(*value, &proc_on_set) }
        else on_set
        end
      end
    end
  end
end
