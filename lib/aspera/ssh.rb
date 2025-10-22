# frozen_string_literal: true

require 'net/ssh'
require 'aspera/assert'
require 'aspera/log'

module Aspera
  # A simple wrapper around Net::SSH
  # executes one command and get its result from stdout
  class Ssh
    class Error < Aspera::Error
    end
    class << self
      def disable_ed25519_keys
        Log.log.debug('Disabling SSH ed25519 user keys')
        old_verbose = $VERBOSE
        $VERBOSE = nil
        Net::SSH::Authentication::Session.class_eval do
          define_method(:default_keys) do
            %w[.ssh .ssh2].product(%w[rsa dsa ecdsa]).map{"~/#{_1}/id_#{_2}"}.freeze
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

    # Anything on stderr raises an exception
    def execute(cmd, input: nil, exception: false)
      Aspera.assert_type(cmd, String)
      Log.log.debug{"cmd=#{cmd}"}
      response = []
      error = []
      Net::SSH.start(@host, @username, @ssh_options) do |session|
        ssh_channel = session.open_channel do |channel|
          # prepare stdout processing
          channel.on_data{ |_chan, data| response.push(data)}
          # prepare stderr processing, stderr if type = 1
          channel.on_extended_data do |_chan, _type, data|
            error.push(data)
          end
          channel.on_request('exit-status') do |_ch, data|
            exit_code = data.read_long
            next if exit_code.zero?
            error_message = "#{cmd}: exit #{exit_code}, #{error.join.chomp}"
            raise Error, error_message if  exception
            # Happens when windows user hasn't logged in and created home account.
            error_message += "\nHint: home not created in Windows?" if data.include?('Could not chdir to home directory')
            Log.log.debug(error_message)
          end
          # send command to SSH channel (execute) cspell: disable-next-line
          channel.send('cexe'.reverse, cmd){ |_ch, _success| channel.send_data(input) unless input.nil?}
        end
        # wait for channel to finish (command exit)
        ssh_channel.wait
        # main SSH session loop
        session.loop
      end
      # response as single string
      return response.join
    end
  end
end

# Deactivate ed25519 and ecdsa private keys from SSH identities, as it usually causes problems
Aspera::Ssh.disable_ed25519_keys if Gem::Specification.find_all_by_name('ed25519').none?
Aspera::Ssh.disable_ecd_sha2_algorithms if defined?(JRUBY_VERSION) && ENV.fetch('ASCLI_ENABLE_ECDSHA2', 'false').eql?('false')
