require 'net/ssh'

# Hack: deactivate ed25519 and ecdsa private keys from ssh identities, as it usually hurts
begin
module Net; module SSH; module Authentication; class Session; private def default_keys; %w(~/.ssh/id_dsa ~/.ssh/id_rsa ~/.ssh2/id_dsa ~/.ssh2/id_rsa);end;end;end;end;end
rescue
end

module Asperalm
  # A simple wrapper around Net::SSH
  # executes one command and get its result from stdout
  class Ssh
    # ssh_options: same as Net::SSH.start
    # see: https://net-ssh.github.io/net-ssh/classes/Net/SSH.html#method-c-start
    def initialize(host,username,ssh_options)
      Log.log.debug("ssh:#{username}@#{host}")
      @host=host
      @username=username
      @ssh_options=ssh_options
      @ssh_options[:logger]=Log.log
    end

    def execute(cmd,input=nil)
      if cmd.is_a?(Array)
        # concatenate arguments, enclose in double quotes
        cmd=cmd.map{|v|'"'+v+'"'}.join(" ")
      end
      Log.log.debug("cmd=#{cmd}")
      response = ''
      Net::SSH.start(@host, @username, @ssh_options) do |session|
        ssh_channel=session.open_channel do |channel|
          # prepare stdout processing
          channel.on_data{|chan,data|response << data}
          # prepare stderr processing, stderr if type = 1
          channel.on_extended_data do |chan, type, data|
            errormsg="#{cmd}: [#{data.chomp}]"
            # Happens when windows user hasn't logged in and created home account.
            if data.include?("Could not chdir to home directory")
              errormsg=errormsg+"\nHint: home not created in Windows?"
            end
            raise errormsg
          end
          channel.exec(cmd){|ch,success|channel.send_data(input) unless input.nil?}
        end
        # wait for channel to finish (command exit)
        ssh_channel.wait
        # main ssh session loop
        session.loop
      end # session
      return response
    end
  end
end
