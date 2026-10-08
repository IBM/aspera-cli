# frozen_string_literal: true

require 'aspera/command_line_builder'
require 'aspera/assert'

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
      # all fields for transport
      TRANSPORT_FIELDS = (%w[remote_host] + AK_TSPEC_BASE.keys + WSS_FIELDS).freeze
      # reserved tag for Aspera
      TAG_RESERVED = 'aspera'
      # Specific fields to not display
      SPECIFIC = %w{token paths direction source_root destination_root}.freeze
      class << self
        # wrong def in transferd
        POLICY_FIX = {
          'none'        => 'none',
          'attrs'       => 'attributes',
          'sparse_csum' => 'sparse_checksum',
          'full_csum'   => 'full_checksum'
        }
        # Multipliers for rate suffix (result is in bps)
        RATE_SUFFIX_BPS = {
          'k' => 1_000,
          'm' => 1_000_000,
          'g' => 1_000_000_000
        }.freeze
        private_constant :POLICY_FIX, :RATE_SUFFIX_BPS
        # translate upload/download to send/receive
        def transfer_type_to_direction(transfer_type)
          XFER_TYPE_TO_DIR.fetch(transfer_type)
        end

        # translate send/receive to upload/download
        def direction_to_transfer_type(direction)
          XFER_DIR_TO_TYPE.fetch(direction)
        end

        # Parse a human-readable rate (as accepted by async -l) into an integer bps value.
        # Accepted: plain integer (bps), or integer + suffix k/K (x1000), m/M (x1000000), g/G (x1000000000).
        # @param value [String, Integer] e.g. "100m", "500000", "1g", 500000
        # @return [Integer] value in bps
        def rate_string_to_bps(value)
          m = value.to_s.strip.match(/\A(\d+)([kKmMgG])?\z/)
          Aspera.assert(m) { "Invalid rate value: #{value.inspect}. Expected integer with optional suffix k/K, m/M or g/G." }
          multiplier = m[2] ? RATE_SUFFIX_BPS.fetch(m[2].downcase) : 1
          return m[1].to_i * multiplier
        end

        # Resolve pseudo-parameter `target_rate` (bps) into `target_rate_kbps` (rounded down), overriding it if both are present.
        # @param transfer_spec [Hash] Transfer spec, modified in place
        def resolve_target_rate(transfer_spec)
          return unless transfer_spec.key?('target_rate')
          rate = transfer_spec.delete('target_rate')
          transfer_spec['target_rate_kbps'] = rate_string_to_bps(rate) / 1000 unless rate.nil?
        end

        def fix_transferd_resume_policy(transfer_spec)
          # Fix discrepancy in transfer spec
          transfer_spec['resume_policy'] = POLICY_FIX[transfer_spec['resume_policy']] if transfer_spec.key?('resume_policy')
        end
      end
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
