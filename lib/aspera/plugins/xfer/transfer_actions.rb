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
        # Jobs of `list` whose agent is queried at the same time: an agent that does not answer costs its call timeout once per batch, not once per job
        MAX_PARALLEL_QUERIES = 10
        private_constant :TERMINAL_STATUSES, :QUERY_FIELDS, :LIST_FIELDS, :MAX_PARALLEL_QUERIES

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
        # Their agents are queried in parallel, by batches of `MAX_PARALLEL_QUERIES`.
        def action_agents_jobs_list(**)
          store = async_transfer_store
          entries = store.list
          live_statuses = query_live_statuses(entries.reject { |entry| ended?(entry) }.map { |entry| query_entry(store, entry) })
          # Job identifiers by reason of a status not refreshed: one warning for each reason
          not_refreshed_jobs = Hash.new { |hash, reason| hash[reason] = [] }
          rows = entries.map do |entry|
            next entry if ended?(entry)
            entry, not_refreshed = apply_live_status(store, entry, live_statuses[entry['job_id']])
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
          return [entry, nil] if ended?(entry)
          apply_live_status(store, entry, query_live_status(query_entry(store, entry)))
        end

        # @param entry [Hash] Saved entry of a job
        # @return [Boolean] `true` if the job does not change: its agent is not queried again
        def ended?(entry) = TERMINAL_STATUSES.include?(entry['status'])

        # @param store [AsyncTransferStore] Store of the jobs
        # @param entry [Hash]               Saved entry of the job
        # @return [Hash] The entry with the parameters of its agent for a query, not saved: secrets of the current options, reference of an in-process agent
        def query_entry(store, entry)
          # Secrets are not persisted: take them from current transfer options (e.g. `--transfer`), for the same agent type
          agent_params = current_agent_params(entry['agent_type']).merge(entry['agent_params'] || {})
          # Inject the in-process agent reference (direct/httpgw) if still alive in this process.
          ref = store.agent_ref(entry['job_id'])
          agent_params['_agent_ref'] = ref if ref
          entry.merge('agent_params' => agent_params)
        end

        # Save the status given by the agent of a job
        # @param store [AsyncTransferStore] Store of the jobs
        # @param entry [Hash]               Saved entry of the job
        # @param live  [Hash, nil]          Status given by the agent, `nil`: the agent could not be queried
        # @return [Array(Hash, Hash)] See `refresh_job`
        def apply_live_status(store, entry, live)
          # No status from the agent: the saved one is kept
          return [entry, (live || {}).slice(*QUERY_FIELDS)] if live.nil? || live['status'].eql?('unknown')
          entry = entry.except(*QUERY_FIELDS).merge(live)
          store.write(entry['job_id'], entry)
          [entry, nil]
        end

        # Query the agents of several jobs, `MAX_PARALLEL_QUERIES` at the same time.
        # Only the calls to the agents are in threads: the classes of the agents are loaded before, the store is written after.
        # @param entries [Array<Hash>] Entries of jobs, see `query_entry`
        # @return [Hash{String => Hash, nil}] Status of each job, by `job_id`, see `query_live_status`
        def query_live_statuses(entries)
          agent_classes = entries.map { |entry| entry['agent_type'] }.uniq.to_h { |agent_type| [agent_type, agent_class_of(agent_type)] }
          entries.each_slice(MAX_PARALLEL_QUERIES).each_with_object({}) do |batch, statuses|
            batch
              .map { |entry| Thread.new { [entry['job_id'], query_live_status(entry, agent_classes[entry['agent_type']])] } }
              .each { |thread| statuses.store(*thread.value) }
          end
        end

        # @param agent_type [String] Agent of a job
        # @return [Class, StandardError] Class of the agent: the file of the entry of its bundle, or the error that prevents loading it
        def agent_class_of(agent_type)
          Aspera::Agent::Factory.instance.agent_class(agent_type)
        rescue StandardError => e
          e
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
        # @param entry       [Hash]                      Entry of the job, see `query_entry`
        # @param agent_class [Class, StandardError, nil] Class of its agent, see `agent_class_of`; `nil`: loaded here
        # @return [Hash, nil] Status given by the agent, `nil`: it could not be queried (warning)
        def query_live_status(entry, agent_class = nil)
          agent_class ||= agent_class_of(entry['agent_type'])
          raise agent_class if agent_class.is_a?(StandardError)
          agent_class.transfer_status(entry['transfer_id'], entry['agent_params'] || {})
        rescue StandardError => e
          Log.log.warn { "Could not re-query #{entry['agent_type']} agent for job #{entry['job_id']}: #{e}" }
          nil
        end
      end
    end
  end
end
