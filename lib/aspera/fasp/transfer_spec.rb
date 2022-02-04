# IMPORTANT: This file is generated from transfer_spec.erb.rb
module Aspera
  module Fasp
    # parameters for Transfer Spec
    class TransferSpec
      # default transfer username for access key based transfers
      ACCESS_KEY_TRANSFER_USER='xfer'.freeze
      SSH_PORT=33001
      UDP_PORT=33001
      AK_TSPEC_BASE={
        'remote_user'.freeze => ACCESS_KEY_TRANSFER_USER,
        'ssh_port'.freeze    => SSH_PORT,
        'fasp_port'.freeze   => UDP_PORT
      }

      # allowed values for cipher
      CIPHER_AES128='aes128'.freeze
      CIPHER_AES192='aes192'.freeze
      CIPHER_AES256='aes256'.freeze
      CIPHER_AES128CFB='aes128cfb'.freeze
      CIPHER_AES192CFB='aes192cfb'.freeze
      CIPHER_AES256CFB='aes256cfb'.freeze
      CIPHER_AES128GCM='aes128gcm'.freeze
      CIPHER_AES192GCM='aes192gcm'.freeze
      CIPHER_AES256GCM='aes256gcm'.freeze

      # allowed values for content_protection
      CONTENT_PROTECTION_ENCRYPT='encrypt'.freeze
      CONTENT_PROTECTION_DECRYPT='decrypt'.freeze

      # allowed values for direction
      DIRECTION_SEND='send'.freeze
      DIRECTION_RECEIVE='receive'.freeze

      # allowed values for overwrite
      OVERWRITE_NEVER='never'.freeze
      OVERWRITE_ALWAYS='always'.freeze
      OVERWRITE_DIFF='diff'.freeze
      OVERWRITE_OLDER='older'.freeze
      OVERWRITE_DIFF_OLDER='diff+older'.freeze

      # allowed values for rate_policy
      RATE_POLICY_LOW='low'.freeze
      RATE_POLICY_FAIR='fair'.freeze
      RATE_POLICY_HIGH='high'.freeze
      RATE_POLICY_FIXED='fixed'.freeze

      # allowed values for resume_policy
      RESUME_POLICY_NONE='none'.freeze
      RESUME_POLICY_ATTRS='attrs'.freeze
      RESUME_POLICY_SPARSE_CSUM='sparse_csum'.freeze
      RESUME_POLICY_FULL_CSUM='full_csum'.freeze

      # allowed values for symlink_policy
      SYMLINK_POLICY_FOLLOW='follow'.freeze
      SYMLINK_POLICY_COPY='copy'.freeze
      SYMLINK_POLICY_COPY_FORCE='copy+force'.freeze
      SYMLINK_POLICY_SKIP='skip'.freeze

      # allowed values for rate_policy_allowed
      RATE_POLICY_ALLOWED_LOW='low'.freeze
      RATE_POLICY_ALLOWED_FAIR='fair'.freeze
      RATE_POLICY_ALLOWED_HIGH='high'.freeze
      RATE_POLICY_ALLOWED_FIXED='fixed'.freeze
    end
  end
end
