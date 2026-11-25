# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../standard_input'

module Aspera
  module Cli
    # Declares a positional argument consumed by a command.
    # Declaration order in a command's `arguments:` array defines parsing order.
    # Mandatory arguments must come before optional ones.
    #
    # @!attribute name        [Symbol]                    Name used in help and error messages
    # @!attribute description [String]                    User-facing description
    # @!attribute type        [Class, Array<Class>, :identifier, nil] Validated type; :identifier triggers instance_identifier.
    #                                                     Default: String (unless allowed:); explicit nil accepts any value
    # @!attribute mandatory   [Boolean]                   Default true; optional args must come after all mandatory ones
    # @!attribute multiple    [Boolean, String]           true: consume all remaining; String: consume until named marker
    # @!attribute default     [Object, nil]               Default value when mandatory: false and no argument provided
    # @!attribute schema      [String, nil]               JSON schema name for validation and --help introspection
    # @!attribute bulk        [Boolean]                   When true, wraps read+loop for bulk mode (Array if --bulk yes)
    # @!attribute lookup      [Symbol, Proc, nil]         Percent-selector resolver (only used when type: :identifier).
    #                                                     Symbol → resolved via send(lookup, field, value, **ctx).
    #                                                     Proc/lambda → called via instance_exec(field, value, **ctx, &lookup).
    #                                                     Style: use Symbol for named methods; ->(){} for 1-liners; lambda do…end for 2–3 statements.
    # @!attribute allowed     [Array<Symbol>, #call, nil] Allowed Symbol values; when set, type is forced to Symbol and accept_list is applied.
    #   A callable returns the values when read: the list of values that bundles add after the command is declared (e.g. agents)
    # @!attribute interactive [Boolean]                   When true, prompts for this argument (only) when no CLI args are provided
    # @!attribute evaluate    [Symbol]                    How the value is read, one of `EVALUATIONS`. Default `:extended`.
    #                                                     `:extended`: extended value (`@json:`, `@file:`, `@val:`...); a value without prefix stays a string.
    #                                                     `:smart`: `true`/`yes`/`false`/`no` and numbers are converted, else extended value (as dotted options).
    #                                                     `:none`: the string as typed, not evaluated (e.g. `@env:`).
    # @!attribute complete    [Symbol, nil]               Values proposed by shell completion, one of `Complete::KINDS` (e.g. `:file`)
    # @!attribute omit_absent [Boolean]                   For an optional argument: when not given, it is not passed to the action,
    #                                                     so that the action (with its own default) can tell it from a value `nil` (`@none:`)
    # @!attribute access      [Symbol, nil]               For a local path chosen by the client (`complete: :file` or `:folder`): how the command uses it,
    #                                                     one of `ACCESSES`. The value is checked against the security level when the argument is read (`Cli::Security`),
    #                                                     and replaced by the real path: `:read` (content read or displayed, even to send it to a remote service),
    #                                                     `:write` (file created or modified). A path only sent by a transfer agent (not read by `ascli`) has no `access`.
    # @!attribute stdin       [Boolean]                   With `access: :read`: the command reads the standard input as a file, given as `-` or `@stdin:stream`:
    #                                                     the value is then a `StandardInput` (type `String` or `StandardInput`), not checked as a path.
    #                                                     Refused where `@stdin:` is disabled (MCP server mode). Without it, `-` is a path like any other.
    Argument = Struct.new(
      :name,
      :description,
      :type,
      :mandatory,
      :multiple,
      :default,
      :schema,
      :bulk,
      :lookup,
      :allowed,
      :interactive,
      :evaluate,
      :complete,
      :omit_absent,
      :access,
      :stdin,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        kwargs[:mandatory]    = true  if kwargs[:mandatory].nil?
        kwargs[:multiple]     = false if kwargs[:multiple].nil?
        kwargs[:bulk]         = false if kwargs[:bulk].nil?
        kwargs[:interactive]  = false if kwargs[:interactive].nil?
        kwargs[:evaluate]     = :extended if kwargs[:evaluate].nil?
        kwargs[:omit_absent]  = false if kwargs[:omit_absent].nil?
        kwargs[:stdin]        = false if kwargs[:stdin].nil?
        raise ArgumentError, "omit_absent: only for an optional argument: #{kwargs[:name]}" if kwargs[:omit_absent] && kwargs[:mandatory]
        raise ArgumentError, "stdin: sets the type: #{kwargs[:name]}" if kwargs[:stdin] && (kwargs.key?(:type) || kwargs[:allowed])
        kwargs[:type] = [String, StandardInput] if kwargs[:stdin]
        kwargs[:type] = String unless kwargs.key?(:type) || kwargs[:allowed]
        raise ArgumentError, "evaluate: #{kwargs[:evaluate].inspect}, expecting one of: #{Argument::EVALUATIONS.join(', ')}" unless Argument::EVALUATIONS.include?(kwargs[:evaluate])
        raise ArgumentError, "access: #{kwargs[:access].inspect}, expecting one of: #{Argument::ACCESSES.join(', ')}" unless kwargs[:access].nil? || Argument::ACCESSES.include?(kwargs[:access])
        raise ArgumentError, "stdin: only with access: :read: #{kwargs[:name]}" if kwargs[:stdin] && !kwargs[:access].eql?(:read)
        super
      end

      # The accessor of the Struct is removed first: redefining it would give a Ruby warning
      remove_method :allowed

      # @return [Array<Symbol>, nil] Allowed values: the result of the callable given to `allowed:`, evaluated at each read
      def allowed
        values = self[:allowed]
        values.respond_to?(:call) ? values.call : values
      end

      # Syntax of argument for help, e.g. `<name>`, `[<name>]`, `<paths...>`, `<account:Hash>`.
      # Type is shown only when the argument is not free text.
      # @return [String]
      def syntax
        token = allowed ? allowed.join('|') : name.to_s
        token += '...' if multiple
        types = Array(type).grep(Class)
        token += ":#{types.map(&:name).join('|')}" unless allowed || types.empty? || types.include?(String)
        mandatory ? "<#{token}>" : "[<#{token}>]"
      end
    end

    class Argument
      # Ways to evaluate the value of an argument, see `Argument#evaluate`
      EVALUATIONS = %i[extended smart none].freeze
      # How a command uses a path given as an argument, see `Argument#access`.
      # `:none`: not a local path read or written by `ascli` (a remote path, or a path checked elsewhere, e.g. a sync folder given to the local `async`).
      ACCESSES = %i[read write none].freeze
    end
  end
end
