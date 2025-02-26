# frozen_string_literal: true

require 'net/ssh'
require 'aspera/assert'

if ENV.fetch('ASCLI_ENABLE_ED25519', 'false').eql?('false')
  # HACK: deactivate ed25519 and ecdsa private keys from SSH identities, as it usually causes problems
  old_verbose = $VERBOSE
  $VERBOSE = nil
  begin
    module Net; module SSH; module Authentication; class Session; private; def default_keys; %w[~/.ssh/id_dsa ~/.ssh/id_rsa ~/.ssh2/id_dsa ~/.ssh2/id_rsa]; end; end; end; end; end # rubocop:disable Layout/AccessModifierIndentation, Layout/EmptyLinesAroundAccessModifier, Layout/LineLength, Style/Semicolon
  rescue StandardError
    # ignore errors
  end
  $VERBOSE = old_verbose
end

if defined?(JRUBY_VERSION) && ENV.fetch('ASCLI_ENABLE_ECDSHA2', 'false').eql?('false')
  Net::SSH::Transport::Algorithms::ALGORITHMS.each_value { |a| a.reject! { |a| a =~ /^ecd(sa|h)-sha2/ } }
  Net::SSH::KnownHosts::SUPPORTED_TYPE.reject! { |t| t =~ /^ecd(sa|h)-sha2/ }
end

module Aspera
  # A simple wrapper around Net::SSH
  # executes one command and get its result from stdout
  class Ssh
    # ssh_options: same as Net::SSH.start
    # see: https://net-ssh.github.io/net-ssh/classes/Net/SSH.html#method-c-start
    def initialize(host, username, ssh_options)
      Log.log.debug{"ssh:#{username}@#{host}"}
      Log.log.debug{"ssh_options:#{ssh_options}"}
      Aspera.assert_type(host, String)
      Aspera.assert_type(username, String)
      Aspera.assert_type(ssh_options, Hash)
      @host = host
      @username = username
      @ssh_options = ssh_options
      @ssh_options[:logger] = Log.log
    end

    def execute(cmd, input=nil)
      Aspera.assert_type(cmd, String)
      Log.log.debug{"cmd=#{cmd}"}
      response = []
      Net::SSH.start(@host, @username, @ssh_options) do |session|
        ssh_channel = session.open_channel do |channel|
          # prepare stdout processing
          channel.on_data{|_chan, data|response.push(data)}
          # prepare stderr processing, stderr if type = 1
          channel.on_extended_data do |_chan, _type, data|
            error_message = "#{cmd}: [#{data.chomp}]"
            # Happens when windows user hasn't logged in and created home account.
            error_message += "\nHint: home not created in Windows?" if data.include?('Could not chdir to home directory')
            raise error_message
          end
          # send command to SSH channel (execute) cspell: disable-next-line
          channel.send('cexe'.reverse, cmd){|_ch, _success|channel.send_data(input) unless input.nil?}
        end
        # wait for channel to finish (command exit)
        ssh_channel.wait
        # main ssh session loop
        session.loop
      end
      # response as single string
      return response.join
    end
  end
end
