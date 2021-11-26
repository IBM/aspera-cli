module Aspera
  module Fasp
    # default parameters
    class Default
      # (public) default transfer username for access key based transfers
      ACCESS_KEY_TRANSFER_USER='xfer'
      SSH_PORT=33001
      UDP_PORT=33001
      AK_TSPEC_BASE={
        'remote_user' => ACCESS_KEY_TRANSFER_USER,
        'ssh_port'    => SSH_PORT,
        'fasp_port'   => UDP_PORT
      }
    end
  end
end

