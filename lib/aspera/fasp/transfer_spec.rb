# frozen_string_literal: true
require 'aspera/fasp/parameters'

module Aspera
  module Fasp
    # parameters for Transfer Spec
    class TransferSpec
      # default transfer username for access key based transfers
      ACCESS_KEY_TRANSFER_USER='xfer'
      SSH_PORT=33_001
      UDP_PORT=33_001
      AK_TSPEC_BASE={
        'remote_user' => ACCESS_KEY_TRANSFER_USER,
        'ssh_port'    => SSH_PORT,
        'fasp_port'   => UDP_PORT
      }
      # define constants for enums of parameters: <paramater>_<enum>, e.g. CIPHER_AES_128
      Aspera::Fasp::Parameters.description.each do |k,v|
        next unless v[:enum].is_a?(Array)
        v[:enum].each do |enum|
          TransferSpec.const_set("#{k.to_s.upcase}_#{enum.upcase.gsub(/[^A-Z0-9]/,'_')}", enum.freeze)
        end
      end
    end
  end
end
