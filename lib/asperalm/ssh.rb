require 'net/ssh'

module Asperalm
  class Ssh
    def initialize(host,username,options)
      @host=host
      @username=username
      @options=options
    end

    def exec_session(cmd,input=nil)
      Log.log.debug("cmd=#{cmd}")
      response = ''
      Net::SSH.start(@host, @username, @options) do |ssh|
        ssh_channel=ssh.open_channel do |channel|
          # prepare stdout processing
          channel.on_data do |chan, data|
            response << data
          end
          # stderr if type = 1
          channel.on_extended_data do |chan, type, data|
            errormsg="got error running #{cmd}:\n[#{data}]"
            # Happens when windows user hasn't logged in and created home account.
            if data.include?("Could not chdir to home directory")
              errormsg=errormsg+"\nHint: home not created in Windows?"
            end
            raise errormsg
          end
          channel.exec(cmd) do |ch, success|
            # concatenate arguments, enclose in double quotes, protect backslash and double quotes
            channel.send_data(input) if !input.nil?
          end
        end
        # wait for channel to finish
        ssh_channel.wait
        ssh.loop
      end
      return response
    end
  end
end
