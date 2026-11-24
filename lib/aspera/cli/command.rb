# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'security'
require_relative 'argument'

module Aspera
  module Cli
    # Declares a single command node in the flat registry.
    #
    # @!attribute id               [Symbol]                      Unique identifier within its parent's namespace
    # @!attribute parent           [Symbol, Array<Symbol>, nil]  Full path to parent; nil for root commands
    # @!attribute description      [String]                      User-facing help text
    # @!attribute arguments        [Array<Argument>]         Positional arguments, in order.
    #                                                            The first Argument with type: :identifier is treated as the instance
    #                                                            identifier for intermediate nodes (consumed in Phase A) and leaf nodes.
    # @!attribute action           [Symbol, Proc, nil]           Instance method (Symbol) or inline block (Proc) called when this is a leaf command
    # @!attribute setup            [Symbol, nil]                 Instance method called before dispatching to children; returns Hash merged into ctx
    # @!attribute aliases          [Array<Symbol>, nil] Alternative names accepted for this command (each resolves to this command's id)
    # @!attribute transfer_paths   [:send, :receive, nil]        File-list resolution delegated to TransferAgent; mutually exclusive with arguments
    # @!attribute condition        [Symbol, nil]                 Instance method returning Boolean; if false command is hidden from dispatch
    # @!attribute query_schema     [String, nil]                 Schema path for --query help; when set, the runner hints `--query=help`
    # @!attribute mount            [Command::Mount, Hash, nil]        Expose children of another plugin's registry under this node
    # @!attribute security         [Symbol, nil]                 Most restrictive security level at which the command is available (`:low`: executes code), see `Security`
    # @!attribute read_only        [Boolean, :default]           Leaf only: the command changes nothing (on the server or locally), so it can be repeated (option `poll`).
    #                                                            `:default` (default): read-only if the id is one of READ_ONLY_IDS (`list`, `show`, ...)
    Command = Struct.new(
      :id,
      :parent,
      :description,
      :arguments,
      :action,
      :setup,
      :aliases,
      :transfer_paths,
      :condition,
      :query_schema,
      :mount,
      :security,
      :read_only,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        Aspera.assert_values(kwargs[:security], Security::LEVELS + [nil]) { "#{kwargs[:id]}: security" }
        kwargs[:read_only] = :default if kwargs[:read_only].nil?
        Aspera.assert_values(kwargs[:read_only], [true, false, :default]) { "#{kwargs[:id]}: read_only" }
        # Coerce each element of arguments: from Hash to Argument if needed
        if kwargs[:arguments]
          kwargs[:arguments] = kwargs[:arguments].map do |a|
            a.is_a?(Hash) ? Argument.new(**a) : a
          end
        end
        kwargs[:mount] = Command::Mount.new(**kwargs[:mount]) if kwargs[:mount].is_a?(Hash)
        super
      end

      class << self
        # Derive the implicit action method name from a path array.
        # e.g. [:admin, :user, :list] -> :action_admin_user_list
        # @param path [Array<Symbol>]
        # @return [Symbol]
        def action_method(path)
          :"action_#{path.join('_')}"
        end
      end

      # @return [Boolean] `true` if the command changes nothing: explicit `read_only`, or from its id (READ_ONLY_IDS)
      def read_only?
        read_only.eql?(:default) ? Command::READ_ONLY_IDS.include?(id) : read_only
      end

      # Compute the full path as Array<Symbol> from parent + id.
      # @return [Array<Symbol>]
      def full_path
        Array(parent) + [id]
      end

      # Derive the implicit action method name from the full path.
      # @return [Symbol]
      def action_method_name
        self.class.action_method(full_path)
      end
    end

    class Command
      # Ids of the commands read-only by default (`read_only: :default`): they change nothing
      READ_ONLY_IDS = %i[list show status info health ls browse find].freeze
    end
  end
end

# `Command::Mount` reopens the struct: loaded once it is defined
require_relative 'command/mount'
