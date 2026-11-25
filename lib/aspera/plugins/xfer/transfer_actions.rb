# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'async_transfer_store'
require_relative '../../agent/factory'
require_relative '../../log'
require_relative '../../assert'

module Aspera
  module Plugins
    module Xfer
      # Mounted on plugin config (manifest `mounts`): async transfer management actions.
      # Exposes three sub-commands under `config agents jobs` (`config transfer` is a deprecated alias):
      #   status  <job_id>        Re-query a running/completed transfer
      #   list                    List all persisted async transfer entries (jobs not ended are re-queried)
      #   cleanup                 Remove completed/failed/cancelled entries
      #
      # Architecture:
      #   - remote-daemon agents (desktop, node, connect, transferd): transfer_id + agent_params
      #     are persisted in AsyncTransferStore (without secrets, taken from current options);
      #     status is re-queried via Agent::Xxx.transfer_status
      #   - direct agent: transfers live in Ruby threads - store is the agent's @sessions;
      #     status is not persistable across process restarts (returns an informational message)
      # A status `unknown` (agent not reachable, missing secret, agent of another process...) does not replace the saved status.
      module TransferActions
        # Statuses after which a job does not change: its agent is not queried again
        TERMINAL_STATUSES = %w[completed failed cancelled].freeze
        # Fields of the result of a previous query that a new status replaces, also when it does not have them
        QUERY_FIELDS = %w[error error_code note].freeze
        # Columns of `list`
        LIST_FIELDS = %w[job_id agent_type status started_at ended_at bytes_transferred transfer_id].freeze
        private_constant :TERMINAL_STATUSES, :QUERY_FIELDS, :LIST_FIELDS

        # Re-query the status of a single async transfer job.
        # When its agent gives no status, the saved state is shown, with the reason (`error` or `note`).
        # @param job_id [String] UUID returned at submission time
        def action_agents_jobs_status(job_id:, **)
          store = async_transfer_store
          entry = store.read(job_id)
          Aspera.assert(!entry.nil?, type: Cli::BadArgument) { "Unknown job_id: #{job_id}" }
          entry, not_refreshed = refresh_job(store, entry)
          Cli::Result::SingleObject.new(entry.merge(not_refreshed || {}))
        end

        # List async transfer jobs: the jobs not ended are re-queried as with `status`, else their saved state is shown, with a warning.
        def action_agents_jobs_list(**)
          store = async_transfer_store
          # Job identifiers by reason of a status not refreshed: one warning for each reason
          not_refreshed_jobs = Hash.new { |hash, reason| hash[reason] = [] }
          rows = store.list.map do |entry|
            entry, not_refreshed = refresh_job(store, entry)
            not_refreshed_jobs[not_refreshed['error']].push(entry['job_id']) if not_refreshed&.key?('error')
            entry
          end
          not_refreshed_jobs.each { |reason, job_ids| Log.log.warn { "Status not refreshed for job #{job_ids.join(', ')}: #{reason}" } }
          Cli::Result::ObjectList.new(rows, fields: LIST_FIELDS)
        end

        # Delete completed, failed, and cancelled entries from the store.
        def action_agents_jobs_cleanup(**)
          store = async_transfer_store
          deleted = store.list
            .select { |e| TERMINAL_STATUSES.include?(e['status']) }
            .map do |e|
            store.delete(e['job_id'])
            e['job_id']
          end
          Cli::Result::Status.new("Deleted #{deleted.size} completed transfer(s)#{": #{deleted.join(', ')}" unless deleted.empty?}")
        end

        private

        # Status of a job from its agent, if not ended: saved when the agent gives it
        # @param store [AsyncTransferStore] Store of the jobs
        # @param entry [Hash]               Saved entry of the job
        # @return [Array(Hash, Hash)] The entry, refreshed if the agent gave a status; and if it did not: the reason (`error` or `note` of the agent, can be empty), else `nil`
        def refresh_job(store, entry)
          return [entry, nil] if TERMINAL_STATUSES.include?(entry['status'])
          job_id = entry['job_id']
          # Secrets are not persisted: take them from current transfer options (e.g. `--transfer`), for the same agent type
          agent_params = current_agent_params(entry['agent_type']).merge(entry['agent_params'] || {})
          # Inject the in-process agent reference (direct/httpgw) if still alive in this process.
          ref = store.agent_ref(job_id)
          agent_params['_agent_ref'] = ref if ref
          live = query_live_status(entry.merge('agent_params' => agent_params))
          # No status from the agent: the saved one is kept
          return [entry, (live || {}).slice(*QUERY_FIELDS)] if live.nil? || live['status'].eql?('unknown')
          entry = entry.except(*QUERY_FIELDS).merge(live)
          store.write(job_id, entry)
          [entry, nil]
        end

        # @param agent_type [String] agent of the async transfer
        # @return [Hash] agent parameters from current transfer options (e.g. `--transfer`), if for the same agent type
        def current_agent_params(agent_type)
          current = context.transfer.transfer_options
          return {} unless (current['agent'] || 'direct').to_s.eql?(agent_type)
          current.except('agent', 'asynchronous')
        end

        # Lazy accessor - requires context.persistency (available in all Base sub-classes).
        # Delegate to the TransferAgent's store so that the in-memory agent-ref
        # registry is shared between the two components in the same process.
        def async_transfer_store
          context.transfer.async_store
        end

        # Delegate to the appropriate agent class method.
        # All agent types are supported:
        # - in-process agents (direct, httpgw): re-queryable while the same process lives
        #   (e.g. MCP mode); '_agent_ref' in agent_params points to the live instance.
        #   When the process has restarted, '_agent_ref' is nil and transfer_status returns
        #   {'status' => 'unknown'} — which is the correct and safe answer.
        # - daemon agents (node, desktop, connect, transferd): re-query via their REST/IPC API.
        def query_live_status(entry)
          agent_type   = entry['agent_type']
          transfer_id  = entry['transfer_id']
          agent_params = entry['agent_params'] || {}

          # Class of the agent: the file of the entry of its bundle
          agent_class = Aspera::Agent::Factory.instance.agent_class(agent_type)
          agent_class.transfer_status(transfer_id, agent_params)
        rescue StandardError => e
          Log.log.warn { "Could not re-query #{entry['agent_type']} agent for job #{entry['job_id']}: #{e}" }
          nil
        end
      end
    end
  end
end
