# frozen_string_literal: true

# cspell:ignore asperascp asws getname lastlog lsass pcap tokengen trapd userdata winuser wtmp
require 'resolv'
require 'set'
require 'time'
require 'aspera/ascp/log_analyzer/log_file'
require 'aspera/ascp/log_analyzer/records'

module Aspera
  module Ascp
    # Analysis of ascp transfer logs: sessions, statistics and diagnostics.
    # Results are tables: Hash (one object) or Array of Hash (list of objects).
    class LogAnalyzer
      # Oldest ascp version for which the analysis is designed
      MIN_VERSION = '4.0'
      # Files analyzed when scanning a folder
      INCLUDED_FILES = /transfer|messages|log/i
      # Files not analyzed when scanning a folder (path relative to folder)
      EXCLUDED_FILES = %r{async|ssl_|\.dat|\.xml|\.html|graph|winuser|manager|asperascp\.20|background|asws|node|plugin|opt/aspera/var|\.exe|trapd|rtf|lsass|lastlog|wtmp|
        process|stats|production|mongrel|console|ntp\.|prepost|aspx|aspshell|tokengen|userdata|http|asconfigurator|ascmd|\.jpg|\.png|ui\.|connect|ssh|
        stderr|stdout|central|sync|\.zip|\.msi|\.gz|\.tgz|\.tbz|\.tar|\.rar|\.bz2?|\.pcap|analysis\.txt|\.7z}ix
      # Folders not scanned
      EXCLUDED_FOLDERS = /\$|recycle/i
      # Statistics summed over log files
      SUMMED_STATS = %i[total_sessions success failed cancelled http_fallback smart_reset win_clock retries] + LogFile::FINDINGS.keys
      # Severities of diagnostics, most severe first
      SEVERITIES = %w[error warning info].freeze
      # Maximum values of log files
      MAXIMA = {max_total: 'max_throughput', max_out: 'max_send', max_in: 'max_receive', max_sess: 'max_sessions'}.freeze

      # @return [Array<LogFile>] analyzed log files
      attr_reader :log_files

      # @param period     [Integer]      Snapshot period in seconds
      # @param zero_bytes [Boolean]      Include sessions without transferred bytes
      # @param mtu        [Integer, nil] MTU to use when not found in logs
      # @param resolve    [Boolean]      Resolve peer addresses to host names
      def initialize(period: 60, zero_bytes: false, mtu: nil, resolve: false)
        @options = {period: period, zero_bytes: zero_bytes, mtu: mtu}
        @resolve = resolve
        @log_files = []
      end

      class << self
        # @param path [String] log file, or folder
        # @return [Array<String>] the log file, or the log files in the folder (recursively)
        def log_paths(path)
          return [path] unless File.directory?(path)
          scan_folder(path, path, [])
        end

        private

        # @return [Array<String>] files, with the log files of folder added
        def scan_folder(root, folder, files)
          Dir.children(folder).sort.each do |name|
            next if name.start_with?('.')
            path = File.join(folder, name)
            if File.directory?(path)
              scan_folder(root, path, files) unless name.match?(EXCLUDED_FOLDERS)
            elsif name.match?(INCLUDED_FILES) && !path.delete_prefix(root).match?(EXCLUDED_FILES)
              files.push(path)
            end
          end
          files
        end
      end

      # Analyze a log file, or the log files in a folder (recursively)
      # @param path [String] file or folder
      # @return [self]
      def add(path)
        self.class.log_paths(path).each { |file| @log_files.push(LogFile.new(file, **@options).analyze) }
        self
      end

      # @return [Hash] statistics over all log files
      def summary
        stats = Hash.new(0)
        errors = Hash.new(0)
        categories = Hash.new(0)
        result = {}
        @log_files.each do |log|
          SUMMED_STATS.each { |key| stats[key] += log.stats[key] }
          stats[:stuck_nack_loss] = [stats[:stuck_nack_loss], log.stats[:stuck_nack_loss]].max
          log.stats[:errors].each { |error, count| errors[error] += count }
          log.stats[:error_categories].each { |category, count| categories[category] += count }
          MAXIMA.each do |key, name|
            next if log.stats[key] <= result.fetch(name, 0)
            result[name] = log.stats[key]
            result["#{name}_time"] = iso(log.stats[:"#{key}_time"])
          end
        end
        first = @log_files.filter_map(&:first_time).min
        last = @log_files.filter_map(&:last_time).max
        {
          'files'            => @log_files.size,
          'first_log'        => iso(first),
          'last_log'         => iso(last),
          'sessions'         => stats[:total_sessions],
          'success'          => stats[:success],
          'failed'           => stats[:failed],
          'cancelled'        => stats[:cancelled],
          'success_rate'     => ((100.0 * (stats[:total_sessions] - stats[:failed]) / stats[:total_sessions]).round(2) if stats[:total_sessions].positive?),
          'http_fallback'    => stats[:http_fallback],
          'retries'          => stats[:retries],
          'multi_session'    => @log_files.sum { |log| log.multi_sessions.size },
          'errors'           => errors.sort_by { |_, count| -count }.to_h,
          'error_categories' => categories.sort_by { |_, count| -count }.to_h,
          'diagnostics'      => SEVERITIES.to_h { |severity| [severity, 0] }.merge(diagnostics.map { |row| row['severity'] }.tally).reject { |_, count| count.zero? }
        }.merge(result).merge(
          'findings' => LogFile.findings(stats),
          'warnings' => warnings
        ).compact
      end

      # @return [Array<String>] warnings about log files
      def warnings
        @log_files.flat_map do |log|
          log.old_versions.map { |version| "#{log.path}: ascp #{version} is older than #{MIN_VERSION}, analysis may be inaccurate" }
        end
      end

      # @return [Array<Hash>] one row per session, with the other side if its log is also analyzed
      def sessions
        rows = @log_files.flat_map(&:session_reports)
        join_sides(rows)
        single_file(rows)
      end

      # @return [Array<Hash>] one row per diagnostic of sessions: id, severity, message
      def diagnostics
        single_file(@log_files.flat_map(&:diagnostics))
      end

      # @return [Array<Hash>] one row per multi-session transfer
      def multi_sessions
        single_file(@log_files.flat_map(&:multi_sessions))
      end

      # @return [Array<Hash>] one row per snapshot period: aggregate rates
      def snapshots
        single_file(@log_files.flat_map(&:snapshots))
      end

      # @return [Array<Hash>] one row per session in each snapshot period
      def snapshot_sessions
        single_file(@log_files.flat_map(&:snapshot_sessions))
      end

      # @return [Array<Hash>] sessions and errors by peer address, most failures first
      def peers
        rows = {}
        each_session do |_, s|
          peer = s[:peer] or next
          row = (rows[peer] ||= {'peer' => peer, 'users' => Set.new, 'sessions' => 0, 'success' => 0, 'failed' => 0, 'cancelled' => 0, 'errors' => Hash.new(0)})
          row['users'].add(s[:user]) if s[:user]
          row['sessions'] += 1
          case s[:status]
          when 'success' then row['success'] += 1
          when 'failed'
            row[s[:error].to_s.match?(/cancelled/i) ? 'cancelled' : 'failed'] += 1
            row['errors'][s[:error]] += 1 if s[:error]
          end
        end
        rows.values.sort_by { |row| -row['failed'] }.map do |row|
          row.merge('users' => row['users'].to_a, 'errors' => row['errors'].to_h).merge(hostname(row['peer']))
        end
      end

      # @return [Array<Hash>] one row per transferred file
      def transfers
        result = []
        each_session do |log, s|
          s.files.each do |name, file|
            result.push({
              'file'        => log.path,
              'session'     => s[:uuid],
              'pid'         => s.pid,
              'user'        => s[:user],
              'peer'        => s[:peer],
              'destination' => s[:dest],
              'start'       => iso(s[:start]),
              'stop'        => iso(s[:stop]),
              'path'        => name,
              'direction'   => file[:op] == 'recv' ? 'receive' : file[:op],
              'size'        => file[:size],
              'status'      => file[:status],
              'error'       => file[:error]
            }.compact)
          end
        end
        single_file(result)
      end

      # @return [Array<Hash>] licenses of local and peer systems
      def licenses
        @log_files.each_with_object({}) do |log, all|
          log.licenses.each { |key, license| all[key] = license.merge(file: log.path) }
        end.map do |(number, address), license|
          {'license' => number, 'address' => address, 'product' => license[:product], 'account' => license[:account], 'os' => license[:os], 'file' => license[:file]}.compact
        end
      end

      # @return [Array<Hash>] by peer: number of sessions with loss due to overdriving of network (shallow queues) or storage
      def overdrives
        counts = Hash.new(0)
        each_session do |_, s|
          cause = s.overdrive
          counts[[s[:peer], cause]] += 1 if cause
        end
        counts.sort_by { |_, count| -count }.map do |(peer, cause), count|
          {'peer' => peer, 'cause' => cause.to_s, 'occurrences' => count}.merge(hostname(peer))
        end
      end

      private

      def iso(time)
        Time.at(time).iso8601 if time
      end

      def each_session
        @log_files.each { |log| log.sessions.each { |s| yield(log, s) } }
      end

      # Same session in the logs of sender and receiver: add the other side to each row
      # @param rows [Array<Hash>] sessions
      def join_sides(rows)
        rows.group_by { |row| row['session'] }.each do |uuid, same|
          next if uuid.nil? || same.size != 2 || same.map { |row| row['direction'] }.uniq.size != 2
          same.each_with_index do |row, index|
            other = same[1 - index]
            row['peer_side'] = other.slice('file', 'pid', 'role', 'status', 'error').compact
            row['peer_diagnostics'] = other['diagnostics'] if other['diagnostics']&.any?
          end
        end
      end

      # Remove column `file` when only one file is analyzed
      def single_file(rows)
        return rows if @log_files.size > 1
        rows.each { |row| row.delete('file') }
      end

      # @return [Hash] host name of address, if resolution is enabled and successful
      def hostname(address)
        return {} unless @resolve && address
        @hostnames ||= {}
        @hostnames[address] ||= Resolv::DNS.open do |dns|
          dns.timeouts = 5
          dns.getname(address).to_s
        rescue Resolv::ResolvError, ArgumentError
          ''
        end
        @hostnames[address].empty? ? {} : {'hostname' => @hostnames[address]}
      end
    end
  end
end
