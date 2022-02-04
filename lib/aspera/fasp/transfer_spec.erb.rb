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
<%    Aspera::Fasp::Parameters.description.each do |k,v|-%>
<%      if v[:enum].is_a?(Array)-%>

      # allowed values for <%=k%>
<%        v[:enum].each do |name|-%>
      <%=k.to_s.upcase%>_<%=name.gsub('+','_').upcase%>='<%=name.to_s%>'.freeze
<%        end-%>
<%      end-%>
<%    end-%>
    end
  end
end
