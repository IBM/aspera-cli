# frozen_string_literal: true

require 'net/ssh'
require 'aspera/assert'
require 'aspera/log'

module Aspera
  # A simple wrapper around Net::SSH
  # executes one command and get its result from stdout
  class Ssh
    class << self
      def disable_ed25519_keys
        Log.log.debug('Disabling SSH ed25519 user keys')
        old_verbose = $VERBOSE
        $VERBOSE = nil
        Net::SSH::Authentication::Session.class_eval do
          define_method(:default_keys) do
            %w[~/.ssh/id_dsa ~/.ssh/id_rsa ~/.ssh2/id_dsa ~/.ssh2/id_rsa].freeze
          end
          private(:default_keys)
        end rescue nil
        $VERBOSE = old_verbose
      end

      def disable_ecd_sha2_algorithms
        Log.log.debug('Disabling SSH ecdsa')
        Net::SSH::Transport::Algorithms::ALGORITHMS.each_value{ |a| a.reject!{ |a| a =~ /^ecd(sa|h)-sha2/}}
        Net::SSH::KnownHosts::SUPPORTED_TYPE.reject!{ |t| t =~ /^ecd(sa|h)-sha2/}
      end
    end
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
          channel.on_data{ |_chan, data| response.push(data)}
          # prepare stderr processing, stderr if type = 1
          channel.on_extended_data do |_chan, _type, data|
            error_message = "#{cmd}: [#{data.chomp}]"
            # Happens when windows user hasn't logged in and created home account.
            error_message += "\nHint: home not created in Windows?" if data.include?('Could not chdir to home directory')
            raise error_message
          end
          # send command to SSH channel (execute) cspell: disable-next-line
          channel.send('cexe'.reverse, cmd){ |_ch, _success| channel.send_data(input) unless input.nil?}
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

# HACK: deactivate ed25519 and ecdsa private keys from SSH identities, as it usually causes problems
Aspera::Ssh.disable_ed25519_keys if ENV.fetch('ASCLI_ENABLE_ED25519', 'false').eql?('false')
Aspera::Ssh.disable_ecd_sha2_algorithms if defined?(JRUBY_VERSION) && ENV.fetch('ASCLI_ENABLE_ECDSHA2', 'false').eql?('false')
