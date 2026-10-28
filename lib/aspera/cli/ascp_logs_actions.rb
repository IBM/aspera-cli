# frozen_string_literal: true

require 'aspera/schema/registry'
require 'aspera/assert'
require 'aspera/log'

module Aspera
  module Cli
    # Mixin for Config plugin: commands of `ascp logs`, analysis of `ascp` log files (sessions, statistics and diagnostics)
    module AscpLogsActions
      LOG_FILES = [{name: :paths, description: 'Log files, or folders with log files', multiple: true, complete: :file}].freeze
      # Command => description, and default fields
      LISTS = {
        sessions:          ['Sessions, with diagnostics',                                           %w[pid session user direction peer status error error_category start transmitted_bytes average_rate loss_rate diagnostics]],
        diagnostics:       ['Diagnostics of sessions: id, severity, message',                       nil],
        multi_sessions:    ['Multi-session transfers: sessions with the same transfer identifier',  nil],
        snapshots:         ['Aggregate rates (bps) per period',                                     nil],
        snapshot_sessions: ['Rates (bps) of sessions per period',                                   nil],
        peers:             ['Sessions and errors by peer address',                                  nil],
        transfers:         ['Transferred files',                                                    %w[session peer start path size status error]],
        licenses:          ['Licenses of local and peer systems',                                   nil],
        overdrives:        ['Sessions with loss due to overdriving of network or storage, by peer', nil]
      }.freeze
      # Kind of record of log lines => description, and default fields
      RECORDS = {
        samples:   ['Periodic statistics of sessions: `Receiver bl` or `Sender bl` line, with its `DS Qs` line', %w[time pid side rate.t rate.c rate.n prog.t prog.e]],
        sessions:  ['Sessions: `Session Start`, `Params`, `Stop` and `Statistics` lines', %w[uuid pid start stop op status errstr user peer targetrate effective_rate]],
        transfers: ['Files: `Transfer Start` and `Transfer Stop` lines', %w[uuid start stop op status file size rate]]
      }.freeze
      RECORD_KIND = {name: :kind, description: RECORDS.map { |kind, (description, _)| "#{kind}: #{description}" }.join(', '), allowed: RECORDS.keys}.freeze
      # Default values of option `ascp_logs` (see schema `AscpLogsOptions`)
      DEFAULTS = {'period' => 1, 'zero_bytes' => false, 'mtu' => nil, 'resolve' => false}.freeze
      private_constant :LOG_FILES, :LISTS, :RECORDS, :RECORD_KIND, :DEFAULTS
      # When a plugin class includes AscpLogsActions, register the :ascp_logs option
      # in that class's DSL registry so Base#initialize auto-declares it,
      # and add the class-level DSL methods of ClassMethods.
      class << self
        def included(base)
          base.option(:ascp_logs, description: 'Ascp: log analysis (dot-notation: period, zero_bytes, mtu, resolve)', schema: Schema::Registry::ASCP_LOGS_OPTIONS)
          base.extend(ClassMethods)
        end
      end

      # Class-level DSL methods added to the plugin class that includes AscpLogsActions.
      module ClassMethods
        # DSL class method: declare the `logs` node and its commands.
        # @param parent [Symbol, Array<Symbol>] path relative to current scope, e.g. :logs
        def ascp_logs_commands(parent)
          commands_under(parent, description: 'Analyze ascp log files') do
            command(:summary, description: 'Statistics and findings', arguments: LOG_FILES, action: :action_ascp_logs_summary)
            LISTS.each do |name, (description, fields)|
              command(name, description: description, arguments: LOG_FILES, action: ->(paths:, **) { Result::ObjectList.new(analyze_ascp_logs(paths).public_send(name), fields: fields) })
            end
            command(:records, description: 'Log lines parsed into records, with the field names of the log', arguments: [RECORD_KIND] + LOG_FILES, action: :action_ascp_logs_records)
            command(:fields, description: 'Description of the fields of records', arguments: [RECORD_KIND], action: :action_ascp_logs_fields)
          end
        end
      end

      def action_ascp_logs_summary(paths:, **)
        Result::SingleObject.new(analyze_ascp_logs(paths).summary)
      end

      def action_ascp_logs_records(kind:, paths:, **)
        require 'aspera/ascp/log_analyzer'
        paths.each { |path| Aspera.assert(File.exist?(path), type: BadArgument) { "No such file or folder: #{path}" } }
        Result::ObjectList.new(Ascp::LogAnalyzer::Records.list(kind, paths), fields: RECORDS[kind].last)
      end

      def action_ascp_logs_fields(kind:, **)
        require 'aspera/ascp/log_analyzer'
        require 'aspera/schema/documentation'
        builder = Schema::Documentation.new(TerminalFormatter, Schema::Registry.instance.reader(Ascp::LogAnalyzer::Records::SCHEMAS[kind])).build
        Result::ObjectList.new(builder.rows, fields: builder.columns)
      end

      private

      # @param paths [Array<String>] log files or folders
      # @return [Aspera::Ascp::LogAnalyzer]
      def analyze_ascp_logs(paths)
        require 'aspera/ascp/log_analyzer'
        params = DEFAULTS.merge((options.get_option(:ascp_logs) || {}).transform_keys(&:to_s))
        analyzer = Ascp::LogAnalyzer.new(
          period:     params['period'] * 60,
          zero_bytes: params['zero_bytes'],
          mtu:        params['mtu'],
          resolve:    params['resolve']
        )
        paths.each do |path|
          Aspera.assert(File.exist?(path), type: BadArgument) { "No such file or folder: #{path}" }
          Log.log.debug { "Analyzing: #{path}" }
          analyzer.add(path)
        end
        analyzer.warnings.each { |warning| Log.log.warn(warning) }
        analyzer
      end
    end
  end
end
