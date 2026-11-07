# frozen_string_literal: true

require 'aspera/schema/registry'
require 'aspera/assert'
require 'aspera/log'

module Aspera
  module Cli
    # Mixin for Config plugin: commands of `ascp logs`, analysis of `ascp` log files (sessions, statistics and diagnostics)
    module AscpLogsActions
      LOG_FILES = [{name: :paths, description: 'Log files (gzip supported), `-` for standard input, or folders with log files', multiple: true, complete: :file}].freeze
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
        sessions:  ['Sessions: `Session Start`, `Params`, `Stop` and `Statistics` lines, with license, MTU and rate lines of the process', %w[uuid pid start stop op status errstr user peer targetrate effective_rate]],
        transfers: ['Files: `Transfer Start` and `Transfer Stop` lines', %w[uuid start stop op status file size rate]]
      }.freeze
      RECORD_KIND = {name: :kind, description: RECORDS.map { |kind, (description, _)| "#{kind}: #{description}" }.join(', '), allowed: RECORDS.keys}.freeze
      # Default values of option `ascp_logs` (see schema `AscpLogsOptions`)
      DEFAULTS = {'period' => 1, 'zero_bytes' => false, 'mtu' => nil, 'resolve' => false, 'thresholds' => {}, 'timezone' => nil, 'health_minutes' => 60, 'remote_max_size' => 268_435_456}.freeze
      private_constant :LOG_FILES, :LISTS, :RECORDS, :RECORD_KIND, :DEFAULTS
      # When a plugin class includes AscpLogsActions, register the :ascp_logs option
      # in that class's DSL registry so Base#initialize auto-declares it,
      # and add the class-level DSL methods of ClassMethods.
      class << self
        def included(base)
          base.option(:ascp_logs, description: 'Ascp: log analysis (dot-notation: period, zero_bytes, mtu, resolve, thresholds, timezone, health_minutes, remote_max_size)', schema: Schema::Registry::ASCP_LOGS_OPTIONS)
          base.extend(ClassMethods)
        end
      end

      # Class-level DSL methods added to the plugin class that includes AscpLogsActions.
      module ClassMethods
        # DSL class method: declare the `logs` node and its commands.
        # @param parent    [Symbol, Array<Symbol>] path relative to current scope, e.g. :logs
        # @param arguments [Array<Hash>]           argument that gives the log files (default: local files)
        def ascp_logs_commands(parent, arguments: LOG_FILES)
          commands_under(parent, description: 'Analyze ascp log files') do
            command(:summary, description: 'Statistics and findings', arguments: arguments, action: :action_ascp_logs_summary)
            command(:health, description: 'Health check for monitoring', arguments: arguments, action: :action_ascp_logs_health)
            LISTS.each do |name, (description, fields)|
              command(name, description: description, arguments: arguments, action: ->(paths:, **) { Result::ObjectList.new(analyze_ascp_logs(paths).public_send(name), fields: fields) })
            end
            command(:records, description: 'Log lines parsed into records, with the field names of the log', arguments: [RECORD_KIND] + arguments, action: :action_ascp_logs_records)
            command(:fields, description: 'Description of the fields of records', arguments: [RECORD_KIND], action: :action_ascp_logs_fields)
          end
        end
      end

      def action_ascp_logs_summary(paths:, **)
        Result::SingleObject.new(analyze_ascp_logs(paths).summary)
      end

      # Health check for monitoring. Reports failed sessions and low efficiency sessions over the last N minutes.
      # @param paths [Array<String>] Log files or folders
      # @param now [Time, Integer, nil] Current reference time (can be injected for testing)
      # @return [Aspera::Cli::Result::ObjectList] Nagios status list
      def action_ascp_logs_health(paths:, now: nil, **)
        require 'aspera/nagios'
        analyzer = analyze_ascp_logs(paths)
        params = ascp_logs_params
        health_minutes = params['health_minutes'].to_i

        ref_time = now ? now.to_i : Time.now.to_i

        failed_count = 0
        low_efficiency_count = 0

        analyzer.log_files.each do |log_file|
          windows_log = log_file.path.match?(/\w:/)
          log_file.sessions.each do |s|
            start_time = s[:start]
            next unless start_time && start_time >= (ref_time - health_minutes * 60) && start_time <= ref_time

            s.report(windows_log: windows_log)
            failed_count += 1 if s[:status] == 'failed'
            low_efficiency_count += 1 if s.diagnostics.any? { |d| d['id'] == 'low_efficiency' }
          end
        end

        nagios = Nagios.new
        msg = "#{failed_count} failed, #{low_efficiency_count} low efficiency in last #{health_minutes} min"
        if failed_count.positive?
          nagios.add_critical('ascp logs', msg)
        elsif low_efficiency_count.positive?
          nagios.add_warning('ascp logs', msg)
        else
          nagios.add_ok('ascp logs', msg)
        end

        Result::ObjectList.new(nagios.status_list)
      end

      def action_ascp_logs_records(kind:, paths:, **)
        require 'aspera/ascp/log_analyzer'
        ascp_logs_files(paths) do |files|
          check_ascp_logs_paths(files)
          Result::ObjectList.new(Ascp::LogAnalyzer::Records.list(kind, files, timezone: ascp_logs_params['timezone']), fields: RECORDS[kind].last)
        end
      rescue ParameterError => e
        raise BadArgument, e.message
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
        params = ascp_logs_params
        user_thresholds = (params['thresholds'] || {}).transform_keys(&:to_s)
        analyzer = Ascp::LogAnalyzer.new(
          period:     params['period'] * 60,
          zero_bytes: params['zero_bytes'],
          mtu:        params['mtu'],
          resolve:    params['resolve'],
          thresholds: user_thresholds,
          timezone:   params['timezone']
        )
        ascp_logs_files(paths) do |files|
          check_ascp_logs_paths(files)
          files.each do |path|
            Log.log.debug { "Analyzing: #{path}" }
            analyzer.add(path)
          end
        end
        analyzer.warnings.each { |warning| Log.log.warn(warning) }
        analyzer
      rescue ParameterError => e
        raise BadArgument, e.message
      end

      # Local log files or folders to analyze, for the paths given as arguments.
      # A plugin that gets logs elsewhere (e.g. `server logs`) redefines this method: files exist only during the block.
      # @param paths [Array<String>] arguments of the command
      # @yieldparam files [Array<String>] local log files or folders
      def ascp_logs_files(paths)
        yield(paths)
      end

      # @return [Hash] value of option `ascp_logs`, with defaults
      def ascp_logs_params
        DEFAULTS.merge((options.get_option(:ascp_logs) || {}).transform_keys(&:to_s))
      end

      # Standard input (`-`) is read by the analyzer
      def check_ascp_logs_paths(paths)
        paths.each do |path|
          Aspera.assert(path == Ascp::LogAnalyzer::STDIN_PATH || File.exist?(path), type: BadArgument) { "No such file or folder: #{path}" }
        end
      end
    end
  end
end
