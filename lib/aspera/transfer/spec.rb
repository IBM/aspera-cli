# frozen_string_literal: true

require 'aspera/transfer/parameters'
require 'aspera/assert'

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
      # reserved tag for Aspera
      TAG_RESERVED = 'aspera'
      # define constants for enums of parameters: <parameter>_<enum>, e.g. CIPHER_AES_128, DIRECTION_SEND, ...
      Aspera::Transfer::Parameters.description.each do |name, description|
        next unless description[:enum].is_a?(Array)
        const_set(:"#{name.to_s.upcase}_ENUM_VALUES", description[:enum])
        description[:enum].each do |enum|
          const_set("#{name.to_s.upcase}_#{enum.upcase.gsub(/[^A-Z0-9]/, '_')}", enum.freeze)
        end
      end
      class << self
        def action_to_direction(tspec, command)
          Aspera.assert_type(tspec, Hash){'transfer spec'}
          tspec['direction'] = case command.to_sym
          when :upload then DIRECTION_SEND
          when :download then DIRECTION_RECEIVE
          else Aspera.error_unexpected_value(command.to_sym)
          end
          return tspec
        end

        def action(tspec)
          Aspera.assert_type(tspec, Hash){'transfer spec'}
          Aspera.assert_values(tspec['direction'], [DIRECTION_SEND, DIRECTION_RECEIVE]){'direction'}
          case tspec['direction']
          when DIRECTION_SEND then :upload
          when DIRECTION_RECEIVE then :download
          else Aspera.error_unexpected_value(tspec['direction'])
          end
        end
      end
    end
  end
end