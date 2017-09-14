module Asperalm
  class Ssh
    def initialize(host,username,password)
      @host=host
      @username=username
      @password=password
    end
    def exec_session(cmd,input)
      response = ''
      Net::SSH.start(@host, @username, @password) do |ssh|
        ssh_channel=ssh.open_channel do |channel|
          # prepare stdout processing
          channel.on_data do |chan, data|
            response << data
          end
          # stderr if type = 1
          channel.on_extended_data do |chan, type, data|
            # Happens when windows user hasn't logged in and created home account.
            unless data.include?("Could not chdir to home directory")
              raise "got error running ascmd: #{data}\nHint: home not created in Windows?"
            end
          end
          channel.exec(cmd) do |ch, success|
            # concatenate arguments, enclose in double quotes, protect backslash and double quotes
            channel.send_data(input)
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
