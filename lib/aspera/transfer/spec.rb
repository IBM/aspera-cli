# frozen_string_literal: true

require 'aspera/command_line_builder'
require 'aspera/assert'

module Aspera
  module Transfer
    # parameters for Transfer Spec
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
      TRANSPORT_FIELDS = %w[remote_host remote_user ssh_port fasp_port].concat(WSS_FIELDS).freeze
      # reserved tag for Aspera
      TAG_RESERVED = 'aspera'
      class << self
        # translate upload/download to send/receive
        def transfer_type_to_direction(transfer_type)
          XFER_TYPE_TO_DIR.fetch(transfer_type)
        end

        # translate send/receive to upload/download
        def direction_to_transfer_type(direction)
          XFER_DIR_TO_TYPE.fetch(direction)
        end
      end
      SCHEMA = CommandLineBuilder.read_schema(__FILE__)
      # define constants for enums of parameters: <parameter>_<enum>, e.g. CIPHER_AES_128, DIRECTION_SEND, ...
      SCHEMA['properties'].each do |name, description|
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
