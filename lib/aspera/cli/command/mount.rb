# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Loaded by `command.rb` (once `Command` is defined), which this file reopens: no require of it here (circular)

module Aspera
  module Cli
    class Command
      # Declares that a command node exposes a sub-tree of another plugin class.
      # The mounted children appear in the host registry (dispatch, --help, completion)
      # as if they were declared by the host; host children with the same id take precedence.
      #
      # @!attribute plugin   [Class]                Target plugin class (subclass of Plugins::Base)
      # @!attribute at       [Array<Symbol>]        Path in the target registry whose children are mounted ([] = root)
      # @!attribute instance [Symbol]               Host instance method called with **ctx, returning the target plugin
      #                                             instance, or [instance, ctx] where ctx seeds the target dispatch
      #                                             (it replaces what the setups of `at` and its ancestors would provide)
      # @!attribute only     [Array<Symbol>, nil]   Restrict mounted children to these ids
      # @!attribute except   [Array<Symbol>, nil]   Exclude these ids from mounted children
      # @!attribute arguments [Array<Argument>] Arguments read by the host after the mounted command, before its own
      #                                             arguments; resolved values are passed to `instance`
      #                                             (e.g. `packages ls <package_id> <path>`)
      Mount = Struct.new(
        :plugin,
        :at,
        :instance,
        :only,
        :except,
        :arguments,
        keyword_init: true
      ) do
        def initialize(**kwargs)
          kwargs[:at] = Array(kwargs[:at]).freeze
          kwargs[:arguments] = Array(kwargs[:arguments]).map { |a| a.is_a?(Hash) ? Argument.new(**a) : a }.freeze
          super
        end

        # @return [Command::Registry] registry of the target plugin class
        def registry
          plugin.command_registry
        end

        # @param id [Symbol] id of a child of `at` in the target registry
        # @return [Boolean] true if this child is exposed by the mount
        def accepts?(id)
          (only.nil? || only.include?(id)) && !except&.include?(id)
        end
      end
    end
  end
end
