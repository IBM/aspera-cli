# frozen_string_literal: true

require 'aspera/command_line_builder'
require 'aspera/assert'
require 'yaml'

module Aspera
  module Transfer
    # parameters for Transfer Spec
    class Spec
      # default transfer username for access key based transfers
      ACCESS_KEY_TRANSFER_USER = 'xfer'
      SSH_PORT = 33_001
      UDP_PORT = 33_001
      AK_TSPEC_BASE = {
        'remote_user' => ACCESS_KEY_TRANSFER_USER,
        'ssh_port'    => SSH_PORT,
        'fasp_port'   => UDP_PORT
      }.freeze
      # fields for transport
      TRANSPORT_FIELDS = %w[remote_host remote_user ssh_port fasp_port wss_enabled wss_port].freeze
      # reserved tag for Aspera
      TAG_RESERVED = 'aspera'
      class << self
        # translate upload/download to send/receive
        def transfer_type_to_direction(transfer_type)
          case transfer_type.to_sym
          when :upload then DIRECTION_SEND
          when :download then DIRECTION_RECEIVE
          else Aspera.error_unexpected_value(transfer_type.to_sym)
          end
        end

        # translate send/receive to upload/download
        def direction_to_transfer_type(direction)
          case direction
          when DIRECTION_SEND then :upload
          when DIRECTION_RECEIVE then :download
          else Aspera.error_unexpected_value(direction)
          end
        end
      end
      DESCRIPTION = CommandLineBuilder.normalize_description(YAML.load_file("#{__FILE__[0..-3]}yaml"))
      # define constants for enums of parameters: <parameter>_<enum>, e.g. CIPHER_AES_128, DIRECTION_SEND, ...
      DESCRIPTION.each do |name, description|
        next unless description[:enum].is_a?(Array)
        const_set(:"#{name.to_s.upcase}_ENUM_VALUES", description[:enum])
        description[:enum].each do |enum|
          const_set("#{name.to_s.upcase}_#{enum.upcase.gsub(/[^A-Z0-9]/, '_')}", enum.freeze)
        end
      end
    end
  end
end
