# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative '../transfer/result'
module Aspera
  module Agent
    # Base class for transfer agents
    # Transfer agents provide methods:
    # - `start_transfer`                 : take a transfer spec and start a transfer asynchronously
    # - `wait_for_transfers_completion`  : waits for all transfer sessions to finish
    # - `notify_progress`                : called back by transfer agent to notify transfer progress
    # - `self.transfer_status`           : (optional) re-query a previously started transfer by id
    # - `self.transfer_cancel`           : (optional) stop a previously started transfer by id
    # Every agent receives the same base options (see `initialize`): plain values and callable objects (Proc), never objects of the CLI.
    # Each agent uses those it needs.
    class Base
      class << self
        # Re-query the status of a transfer that was started asynchronously.
        # Override in agents that support live status queries (desktop, node, connect, transferd).
        # @param transfer_id  [String] opaque id returned by start_transfer
        # @param agent_params [Hash]   connection parameters stored at submission time
        # @return [Hash, nil] status hash with at least 'status' key, or nil if not supported
        def transfer_status(_transfer_id, _agent_params)
          nil
        end

        # Stop a transfer that was started asynchronously.
        # Override in agents that support it (transferd).
        # @param transfer_id  [String] opaque id returned by start_transfer
        # @param agent_params [Hash]   connection parameters stored at submission time
        # @return [Boolean, nil] `true` if stopped, `nil` if not supported
        # @raise [Transfer::Error] The agent refused to stop the transfer
        def transfer_cancel(_transfer_id, _agent_params)
          nil
        end
      end

      # Where received files are written (direction `receive`).
      # Override in agents that write on a remote system (node): the destination is then not a local path.
      # @return [Boolean] `true` if the destination folder is on the local system: restrictions on local writes apply (see `Cli::Security`)
      def local_destination?
        true
      end

      # Wait for all sessions to terminate and return a typed Transfer::Result.
      # Notifies the end of transfer to the progress bar (agents do not).
      # @return [Transfer::Result::Success, Transfer::Result::Error]
      def wait_for_completion
        success = false
        statuses = wait_for_transfers_completion
        Aspera.assert_type(statuses, Array)
        Aspera.assert(statuses.none? { |i| !i.eql?(:success) && !i.is_a?(StandardError) }) { "bad statuses content: #{statuses}" }
        errors = statuses.reject { |i| i.eql?(:success) }
        success = errors.empty?
        return success ? Transfer::Result.success : Transfer::Result.error(errors.first)
      ensure
        # Also when the agent raises an exception
        notify_progress(:end, info: success)
      end

      # Return the job_id of the last transfer submitted by this agent.
      # In-process agents (direct, httpgw) override this to expose their internal job id.
      # Remote-daemon agents do not need to override it: TransferAgent generates a UUID itself.
      # @return [String, nil]
      def last_job_id
        nil
      end

      # Identifier of the last transfer started, for class methods `transfer_status` and `transfer_cancel`.
      # In-process agents (direct, httpgw): the job id (`last_job_id`).
      # @return [String, nil] `nil` if no transfer was started
      attr_reader :transfer_id

      # Connection details resolved when the agent runs (e.g. the port of a daemon started by the agent),
      # added to the agent parameters given to `transfer_status` and `transfer_cancel`.
      # @return [Hash] JSON-compatible values, String keys
      def async_params
        {}
      end

      # @return [Boolean] `true` if transfers run in this process (threads): their status is known only while it runs
      def in_process?
        false
      end

      private

      Aspera.require_method!(:start_transfer)
      Aspera.require_method!(:wait_for_transfers_completion)
      # method `shutdown` is optional
      def shutdown
        nil
      end

      attr_reader :config_dir, :check_ignore_cb, :trusted_certs, :url_provider

      # Base transfer agent object.
      # Base options: given to every agent by the application, each agent uses those it needs.
      # @param progress         [#event, nil]          Receives progress events: `event(type, session_id:, info:)`
      # @param progress_default [Boolean]              `true` if `progress` is a default choice, not requested by the user: an agent that displays its own progress does not use it
      # @param config_dir       [String, nil]          Configuration folder of the application
      # @param check_ignore_cb  [Proc, nil]            Called with host and port: `true` if the certificate of that server is not checked
      # @param trusted_certs    [Array<String>, nil]   Files of trusted certificates
      # @param preset_lookup    [Proc, nil]            Called with a plugin name (Symbol): values of the default preset of that plugin (Hash)
      # @param url_provider     [Proc, nil]            Returns the URL of the server of the agent given by the application (e.g. HTTP Gateway of AoC)
      def initialize(
        progress:         nil,
        progress_default: false,
        config_dir:       nil,
        check_ignore_cb:  nil,
        trusted_certs:    nil,
        preset_lookup:    nil,
        url_provider:     nil
      )
        @progress = progress
        @progress_default = progress_default
        @config_dir = config_dir
        @check_ignore_cb = check_ignore_cb
        @trusted_certs = trusted_certs
        @preset_lookup = preset_lookup
        @url_provider = url_provider
      end

      def notify_progress(*pos_args, **kw_args)
        @progress&.event(*pos_args, **kw_args)
      end

      # The agent displays its own progress: no notification to `progress` if it is a default choice
      def own_progress_display
        @progress = nil if @progress_default
      end

      # @param plugin [Symbol] Plugin name
      # @return [Hash, nil] Values of the default preset of the plugin (String keys), `nil` if no preset lookup was given
      def preset_values(plugin)
        @preset_lookup&.call(plugin)
      end
    end
  end
end
