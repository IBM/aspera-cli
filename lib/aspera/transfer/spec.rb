# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../agent/factory'
require_relative '../schema/registry'
require_relative 'command_line_builder'
require_relative '../assert'
require_relative '../units/decimal'

module Aspera
  module Transfer
    # Parameters for Transfer Spec
    # Parameters are generated from JSON Schema.
    class Spec
      # default transfer username for access key based transfers
      ACCESS_KEY_TRANSFER_USER = 'xfer'
      # default ports for SSH and UDP
      SSH_PORT = 33_001
      UDP_PORT = 33_001
      # base transfer spec for access keys
      AK_TSPEC_BASE = {
        'remote_user' => ACCESS_KEY_TRANSFER_USER,
        'ssh_port'    => SSH_PORT,
        'fasp_port'   => UDP_PORT
      }.freeze
      # fields for WSS
      WSS_FIELDS = %w[wss_enabled wss_port].freeze
      # Modification times of the source files: `Integer` or `String`, see `stringify_exclude_times`
      EXCLUDE_TIMES = %w[exclude_newer_than exclude_older_than].freeze
      # all fields for transport
      TRANSPORT_FIELDS = (%w[remote_host] + AK_TSPEC_BASE.keys + WSS_FIELDS).freeze
      # reserved tag for Aspera
      TAG_RESERVED = 'aspera'
      # Specific fields to not display
      SPECIFIC = %w{token paths direction source_root destination_root}.freeze
      # Value of agent for documentation with one column per agent
      DOC_OVERVIEW = :overview
      class << self
        # wrong def in transferd
        POLICY_FIX = {
          'none'        => 'none',
          'attrs'       => 'attributes',
          'sparse_csum' => 'sparse_checksum',
          'full_csum'   => 'full_checksum'
        }.freeze
        private_constant :POLICY_FIX
        # translate upload/download to send/receive
        def transfer_type_to_direction(transfer_type)
          XFER_TYPE_TO_DIR.fetch(transfer_type)
        end

        # translate send/receive to upload/download
        def direction_to_transfer_type(direction)
          XFER_DIR_TO_TYPE.fetch(direction)
        end

        # Resolve pseudo-parameter `target_rate` (bps) into `target_rate_kbps` (rounded down), overriding it if both are present.
        # @param transfer_spec [Hash] Transfer spec, modified in place
        def resolve_target_rate(transfer_spec)
          return unless transfer_spec.key?('target_rate')
          rate = transfer_spec.delete('target_rate')
          transfer_spec['target_rate_kbps'] = Units::Decimal.rate_string_to_bps(rate) / 1000 unless rate.nil?
        end

        # Parameters `exclude_newer_than` and `exclude_older_than` given as an `Integer` are sent as a `String`:
        # the Node API ignores a number, `transferd` refuses it, and `ascp` reads a text anyway.
        # @param transfer_spec [Hash] Transfer spec, modified in place
        def stringify_exclude_times(transfer_spec)
          EXCLUDE_TIMES.each { |key| transfer_spec[key] = transfer_spec[key].to_s if transfer_spec[key].is_a?(Integer) }
        end

        # Parameters `exclude_newer_than` and `exclude_older_than` as an `Integer`: Connect ignores a string, or a negative number
        # @param transfer_spec [Hash] Transfer spec, modified in place
        # @raise [ParameterError] if a value is not an integer, or is negative
        def integer_exclude_times(transfer_spec)
          EXCLUDE_TIMES.each do |key|
            next unless transfer_spec.key?(key)
            value = transfer_spec[key]
            value = Integer(value, 10, exception: false) if value.is_a?(String)
            Aspera.assert(value.is_a?(Integer) && !value.negative?, type: ParameterError) do
              "agent connect: #{key} must be a time after the epoch (positive integer), not #{transfer_spec[key].inspect}"
            end
            transfer_spec[key] = value
          end
        end

        def fix_transferd_resume_policy(transfer_spec)
          # Fix discrepancy in transfer spec
          transfer_spec['resume_policy'] = POLICY_FIX[transfer_spec['resume_policy']] if transfer_spec.key?('resume_policy')
        end

        # Options of `Schema::Documentation` for the transfer spec: supported agents and `ascp` options
        # @param agent [Symbol, nil] `nil`: all parameters, name of agent: parameters it supports, `DOC_OVERVIEW`: one column per agent
        # @return [Hash] Keyword arguments of `Schema::Documentation.new`
        def doc_options(agent = nil)
          return {annotate: ->(node, formatter) { doc_lines(node, formatter, agent: agent) }} unless agent.eql?(DOC_OVERVIEW)
          {
            annotate:      ->(node, formatter) { doc_lines(node, formatter, agents_line: false) },
            extra_columns: Agent::Factory::ALL.sort_by { |_, names| names[:short] }.to_h do |sym, names|
              [names[:short].to_s, ->(node, formatter) { formatter.tick(CommandLineBuilder.supported_by_agent(sym, node)) }]
            end
          }
        end

        private

        # Documentation of supported agents and command line option of a parameter: `annotate` of `Schema::Documentation`
        # @param node        [Hash]               Schema of the parameter
        # @param formatter   [FormatterInterface] Formatter of the documentation
        # @param agent       [Symbol, nil]        Show only parameters supported by this agent, or all if `nil`
        # @param agents_line [Boolean]            `true`: add a line with supported agents, if not all
        # @return [Array<String>, nil] Lines added to the description, `nil` to hide the parameter
        def doc_lines(node, formatter, agent: nil, agents_line: true)
          agents = Agent::Factory::ALL.keys.select { |sym| CommandLineBuilder.supported_by_agent(sym, node) }
          return if agents.empty? || (agent && !agents.include?(agent))
          lines = []
          lines.push("(#{agents.map { |i| Agent::Factory::ALL[i][:short].to_s.upcase }.sort.join(', ')})") if agents_line && !agents.length.eql?(Agent::Factory::ALL.length)
          lines.concat(CommandLineBuilder.doc_lines(node, formatter))
        end
      end
      # Schema of the parameters, documented with the agents that support them and their option of the command line of `ascp`
      Schema::Registry.register(Schema::Registry::TRANSFER_SPEC, File.join(__dir__, 'spec.schema.yaml'), doc_options: -> { doc_options })
      SCHEMA = CommandLineBuilder.read_schema(Schema::Registry::TRANSFER_SPEC, ascp: true)
      # Define constants for enums of parameters: <parameter>_<enum>, e.g. CIPHER_AES_128, DIRECTION_SEND, ...
      SCHEMA.current['properties'].each do |name, description|
        next unless description['enum'].is_a?(Array)
        const_set(:"#{name.to_s.upcase}_ENUM_VALUES", description['enum'])
        description['enum'].each do |enum|
          const_set("#{name.to_s.upcase}_#{enum.upcase.gsub(/[^A-Z0-9]/, '_')}", enum.freeze)
        end
      end
      # DIRECTION_* are read from yaml
      XFER_TYPE_TO_DIR = {upload: DIRECTION_SEND, download: DIRECTION_RECEIVE}.freeze
      XFER_DIR_TO_TYPE = XFER_TYPE_TO_DIR.invert.freeze
      private_constant :XFER_TYPE_TO_DIR, :XFER_DIR_TO_TYPE
    end
  end
end
