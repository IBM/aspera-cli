# frozen_string_literal: true

require 'aspera/fasp/parameters'

module Aspera
  module Fasp
    # parameters for Transfer Spec
    class TransferSpec
      # default transfer username for access key based transfers
      ACCESS_KEY_TRANSFER_USER = 'xfer'
      SSH_PORT = 33_001
      UDP_PORT = 33_001
      AK_TSPEC_BASE = {
        'remote_user' => ACCESS_KEY_TRANSFER_USER,
        'ssh_port'    => SSH_PORT,
        'fasp_port'   => UDP_PORT
      }.freeze
      # define constants for enums of parameters: <paramater>_<enum>, e.g. CIPHER_AES_128
      Aspera::Fasp::Parameters.description.each do |k, v|
        next unless v[:enum].is_a?(Array)
        v[:enum].each do |enum|
          TransferSpec.const_set("#{k.to_s.upcase}_#{enum.upcase.gsub(/[^A-Z0-9]/, '_')}", enum.freeze)
        end
      end
      class<<self
        def ascp_opts_to_ts(tspec,opts)
          return if opts.nil?
          raise "ascp options must be an Array" unless opts.is_a?(Array)
          raise "transfer spec must be a Hash" unless tspec.is_a?(Hash)
          raise "ascp options must be an Array or Strings" if opts.any?{|o|!o.is_a?(String)}
          tspec['EX_ascp_args']||=[]
          raise "EX_ascp_args must be an Array" unless tspec['EX_ascp_args'].is_a?(Array)
          # TODO: translate command line args into transfer spec
          # non translatable args are left in special ts parameter
          tspec['EX_ascp_args']=tspec['EX_ascp_args'].concat(opts)
        end
      end
    end
  end
end
