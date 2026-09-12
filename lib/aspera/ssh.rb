# frozen_string_literal: true

require 'net/ssh'
require 'aspera/assert'
require 'aspera/log'

module Aspera
  # A simple wrapper around Net::SSH
  # executes one command and get its result from stdout
  class Ssh
    # Raised when the remote command fails or cannot be started
    class Error < Aspera::Error
    end
    # Regexp matching ecdsa/ecdh-sha2 algorithm names (JRuby workaround)
    EXCLUDE_ECDSHA2 = /^ecd(sa|h)-sha2/

    class << self
      # Removes ed25519 keys from the default identity list used by Net::SSH.
      # Called when the `ed25519` gem is absent or explicitly disabled via
      # `ASCLI_ENABLE_ED25519=false`.
      # @return [void]
      def disable_ed25519_keys
        Log.log.debug('Disabling SSH ed25519 user keys')
        old_verbose = $VERBOSE
        $VERBOSE = nil
        Net::SSH::Authentication::Session.class_eval do
          define_method(:default_keys) do
            %w[.ssh .ssh2].product(%w[rsa dsa ecdsa]).map{"~/#{_1}/id_#{_2}"}.freeze
          end
          private(:default_keys)
        end
        $VERBOSE = old_verbose
      end

      # Returns Net::SSH option overrides that exclude all ecdsa/ecdh-sha2 algorithms.
      # Merge the result into `ssh_options` passed to {Ssh#initialize} to avoid
      # mutating Net::SSH internal constants.
      # @return [Hash{Symbol => Array<String>}] `:host_key` and `:kex` filtered lists
      def no_ecd_sha2_options
        Log.log.debug('Building SSH options without ecdsa/ecdh-sha2')
        {
          host_key: Net::SSH::Transport::Algorithms::ALGORITHMS[:host_key].reject{ |a| a.match?(EXCLUDE_ECDSHA2)},
          kex:      Net::SSH::Transport::Algorithms::ALGORITHMS[:kex].reject{      |a| a.match?(EXCLUDE_ECDSHA2)}
        }
      end

      # Mutates Net::SSH internal algorithm lists to remove ecdsa/ecdh-sha2 entries globally.
      # Kept for backwards compatibility and JRuby usage; prefer {no_ecd_sha2_options} for new code.
      # @return [void]
      def disable_ecd_sha2_algorithms
        Log.log.debug('Disabling SSH ecdsa (global)')
        Net::SSH::Transport::Algorithms::ALGORITHMS.each_value{ |a| a.reject!{ |a| a.match?(EXCLUDE_ECDSHA2)}}
        Net::SSH::KnownHosts::SUPPORTED_TYPE.reject!{ |t| t.match?(EXCLUDE_ECDSHA2)}
      end
    end
    # @param host        [String]            remote server address
    # @param username    [String]            SSH user name
    # @param ssh_options [Hash{Symbol => Object}] options forwarded to `Net::SSH.start`
    #   (see {https://net-ssh.github.io/net-ssh/classes/Net/SSH.html#method-c-start Net::SSH.start}).
    #   Defaults are injected for `:logger`, `:verbose`, and `:use_agent` if absent.
    def initialize(host, username, ssh_options)
      Aspera.assert_type(host, String)
      Aspera.assert_type(username, String)
      Aspera.assert_type(ssh_options, Hash)
      Aspera.assert_hash_all(ssh_options, Symbol, nil)
      @host = host
      @username = username
      @ssh_options = ssh_options.dup
      @ssh_options[:logger] = Log.log unless @ssh_options.key?(:logger)
      @ssh_options[:verbose] = :warn unless @ssh_options.key?(:verbose)
      # @ssh_options[:verbose] = :debug
      @ssh_options[:use_agent] = false unless @ssh_options.key?(:use_agent)
      Log.log.debug{"ssh:#{@username}@#{@host}"}
      Log.dump(:ssh_options, @ssh_options)
    end

    # Executes a single command on the remote host over a new SSH session.
    # @param cmd   [String]      shell command to execute remotely
    # @param input [String, nil] data written to the command's stdin, or `nil`
    # @return [String] concatenated stdout of the remote command
    # @raise [Error] if the channel cannot be opened or the remote command exits with a non-zero status
    def execute(cmd, input: nil)
      Aspera.assert_type(cmd, String)
      Log.log.debug{"cmd=#{cmd}"}
      # @type response [Array<String>]
      response = []
      # @type error [Array<String>]
      error = []
      exit_code = nil
      # @param session [Net::SSH::Connection::Session]
      Net::SSH.start(@host, @username, @ssh_options) do |session|
        # @param channel [Net::SSH::Connection::Channel]
        session.open_channel do |channel|
          # Register stdout/stderr before exec so no data is missed (e.g. ForceCommand errors)
          channel.on_data{ |_ch, data| response.push(data)}
          channel.on_extended_data{ |_ch, type, data| error.push(data) if type.eql?(1)}
          # @param data [Net::SSH::Buffer]
          channel.on_request('exit-status') do |_channel, data|
            Log.dump(:data, data, level: :trace1)
            exit_code = data.read_long
          end
          # send command to SSH channel (execute) cspell: disable-next-line
          channel.send('cexe'.reverse, cmd) do |_ch, success|
            raise Error, "could not execute command: #{cmd}" unless success
            channel.send_data(input) unless input.nil?
          end
        end
        # wait for channel to finish and flush the session
        session.loop
      end
      error_text = error.join
      hint = error_text.include?('Could not chdir to home directory') ? "\nHint: home not created in Windows?" : ''
      if exit_code&.nonzero?
        raise Error, "#{cmd}: exit #{exit_code}, #{error_text.chomp}#{hint}"
      end
      Log.log.error{"#{error_text}#{hint}"} unless error_text.empty?
      # response as single string
      return response.join
    end
  end
end

# Deactivate ed25519 and ecdsa private keys from SSH identities, as it usually causes problems
Aspera::Ssh.disable_ed25519_keys if Gem::Specification.find_all_by_name('ed25519').none? || ENV.fetch('ASCLI_ENABLE_ED25519', 'true').eql?('false')
Aspera::Ssh.disable_ecd_sha2_algorithms if defined?(JRUBY_VERSION) && ENV.fetch('ASCLI_ENABLE_ECDSHA2', 'false').eql?('false')
