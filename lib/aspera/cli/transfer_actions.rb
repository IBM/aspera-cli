# frozen_string_literal: true

require 'aspera/cli/async_transfer_store'
require 'aspera/agent/factory'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # Mixin for Config plugin: async transfer management actions.
    # Exposes three sub-commands under `config transfer`:
    #   status  --id=<job_id>   Re-query a running/completed transfer
    #   list                    List all persisted async transfer entries
    #   cleanup                 Remove completed/failed/cancelled entries
    #
    # Architecture:
    #   - remote-daemon agents (desktop, node, connect, transferd): transfer_id + agent_params
    #     are persisted in AsyncTransferStore; status is re-queried via Agent::Xxx.transfer_status
    #   - direct agent: transfers live in Ruby threads - store is the agent's @sessions;
    #     status is not persistable across process restarts (returns an informational message)
    module TransferActions
      # Re-query the status of a single async transfer job.
      # @param job_id [String] UUID returned at submission time
      def action_transfer_status(job_id:, **)
        store = async_transfer_store
        entry = store.read(job_id)
        Aspera.assert(!entry.nil?, type: Cli::BadArgument){"Unknown job_id: #{job_id}"}
        live = query_live_status(entry)
        if live
          entry.merge!(live)
          store.write(job_id, entry)
        end
        Result::SingleObject.new(entry)
      end

      # List all persisted async transfer entries.
      def action_transfer_list(**)
        rows = async_transfer_store.list
        Result::ObjectList.new(rows, fields: %w[job_id agent_type status started_at ended_at bytes_transferred transfer_id])
      end

      TERMINAL_STATUSES = %w[completed failed cancelled].freeze
      private_constant :TERMINAL_STATUSES

      # Delete completed, failed, and cancelled entries from the store.
      def action_transfer_cleanup(**)
        store = async_transfer_store
        deleted = store.list
          .select{ |e| TERMINAL_STATUSES.include?(e['status'])}
          .map do |e|
          store.delete(e['job_id'])
          e['job_id']
        end
        Result::Status.new("Deleted #{deleted.size} completed transfer(s)#{": #{deleted.join(', ')}" unless deleted.empty?}")
      end

      private

      # Lazy accessor - requires context.persistency (available in all Base sub-classes).
      def async_transfer_store
        @async_transfer_store ||= AsyncTransferStore.new(persistency)
      end

      # Delegate to the appropriate agent class method.
      # Returns nil for direct transfers (in-process only, not re-queryable across processes).
      def query_live_status(entry)
        agent_type  = entry['agent_type']
        transfer_id = entry['transfer_id']
        agent_params = entry['agent_params'] || {}

        # direct transfers live in Ruby threads - not persistable across process restarts
        return if agent_type.eql?('direct')

        require "aspera/agent/#{agent_type}"
        agent_class = Aspera::Agent.const_get(agent_type.capitalize)
        agent_class.transfer_status(transfer_id, agent_params)
      rescue StandardError => e
        Log.log.warn{"Could not re-query #{entry['agent_type']} agent for job #{entry['job_id']}: #{e}"}
        nil
      end
    end
  end
end
