# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../environment'
require_relative '../log'
require_relative '../ascp/log_analyzer'

module Aspera
  module Sync
    # Extract the notable events from `async` (Aspera Sync) log files: file conflicts and errors,
    # unsupported file-system events, session lifecycle (start, stop, idle), and `ERR`-level lines.
    # The bulk of the log (synchronized files, transfers, periodic statistics) is skipped.
    # A line looks like: `2026-11-24 20:51:01.275 [d4fc-18637435] LOG [Sync_reporter] SYNC FILE STOP ... status=CONFLICT`
    module LogParser
      # One log line: timestamp, process id, level, optional bracketed component, message
      LINE = /\A(?<time>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) \[[^\]]+\] (?<level>[A-Z]+) (?:\[(?<component>[^\]]+)\] )?(?<message>.*)\z/
      # `status` of `SYNC FILE STOP` that means the file is synchronized, so not notable (also `SYNCHRONIZED(exs)`: already present)
      FILE_STATUS_OK = 'SYNCHRONIZED'
      # `SYNC SESSION <event>` kept (lifecycle); the others (STATS, PROG, READY, NEW, SCAN, PARAMETERS) are skipped
      SESSION_EVENTS = %w[START STOP IDLE].freeze
      SESSION_EVENT = /\ASYNC SESSION (#{SESSION_EVENTS.join('|')})\b/
      # Log levels that are always notable
      NOTABLE_LEVELS = %w[ERR ERROR FATAL].freeze
      # Text of the file-system watcher error (async `Monitor_fsevents.cpp`)
      UNSUPPORTED_EVENT = 'Unsupported file system event'
      # Longest `detail` kept for display: the raw message of an `ERR` line can be very long
      DETAIL_MAX = 200
      # Names of the `async` log files in a folder: current file and its rotations
      ASYNC_FILE = /\Aasync(?:\.\d+)?\.log(?:\.gz)?\z/
      # Linux and Unix: `async` logs to syslog (one of these files, depending on the syslog configuration)
      SYSLOG_FILES = %w[/var/log/aspera.log /var/log/messages /var/log/syslog].freeze
      # Default fields shown for the events
      FIELDS = %w[time level session kind path status detail].freeze
      # Compiled regular expression for each `key=...` read from a message (built once per key)
      FIELD_RE = Hash.new { |cache, key| cache[key] = /\b#{Regexp.escape(key)}=(?:"([^"]*)"|(\S+))/ }

      class << self
        # @param paths    [Array<String, StandardInput>] log files, folders (scanned for `async*.log`), or standard input
        # @param readable [#call, nil]    For a folder: tells if a file found in it can be read (e.g. it is in the allowed paths of the caller,
        #                                 also through a symbolic link), else it is skipped. `nil`: all are read.
        # @return [Array<Hash>] notable events, oldest first (across files, by timestamp)
        def notable_events(paths, readable: nil)
          paths.flat_map { |path| path_files(path, readable) }
            .flat_map { |file| file_events(file) }
            .sort_by { |event| event['time'] }
        end

        # @return [Array<String>] the `async` log files at the default location of the local host (existing only)
        def default_log_paths
          case Environment.instance.os
          when Environment::OS_MACOS
            [File.join(Dir.home, 'Library', 'Logs', 'Aspera', 'async.log')].select { |file| File.file?(file) }
          when Environment::OS_WINDOWS
            # `async` logs to its working folder on Windows: no fixed default location
            []
          else
            SYSLOG_FILES.select { |file| File.file?(file) }
          end
        end

        # @return [String] human description of the default location, for an error message
        def default_location_hint
          case Environment.instance.os
          when Environment::OS_MACOS then File.join(Dir.home, 'Library', 'Logs', 'Aspera', 'async.log')
          when Environment::OS_WINDOWS then 'the working folder of async'
          else SYSLOG_FILES.join(', ')
          end
        end

        private

        # @param path     [String, StandardInput] a log file, the standard input, or a folder (then only the `async*.log` files in it are kept)
        # @param readable [#call, nil] see `notable_events`
        # @return [Array<String, StandardInput>] the files to read
        def path_files(path, readable)
          return [path] unless Ascp::LogAnalyzer.folder?(path)
          Dir.children(path).sort.select { |name| name.match?(ASYNC_FILE) }.map { |name| File.join(path, name) }
            .select { |file| readable.nil? || readable.call(file) }
        end

        # @param file [String, StandardInput] a log file (plain or gzip), or the standard input
        # @return [Array<Hash>] the notable events of the file
        def file_events(file)
          events = []
          Ascp::LogAnalyzer.read_lines(file, Encoding::UTF_8) do |line|
            event = classify(line.scrub.chomp)
            events.push(event) unless event.nil?
          end
          events
        end

        # @param line [String] one log line
        # @return [Hash, nil] the event, or nil if the line is not notable
        def classify(line)
          match = LINE.match(line)
          return if match.nil?
          level = match[:level]
          message = match[:message]
          if message.start_with?('SYNC FILE STOP ')
            status = field(message, 'status')
            return if status.nil? || status.start_with?(FILE_STATUS_OK)
            build(match, kind: "file #{status.downcase}", path: field(message, 'path'), status: status)
          elsif (session = SESSION_EVENT.match(message))
            build(match, kind: "session #{session[1].downcase}", path: field(message, 'local'), status: field(message, 'status') || field(message, 'op'))
          elsif message.include?(UNSUPPORTED_EVENT)
            build(match, kind: 'unsupported-event', detail: message)
          elsif NOTABLE_LEVELS.include?(level)
            build(match, kind: 'error', detail: message)
          end
        end

        # @return [Hash] an event record
        def build(match, kind:, path: nil, status: nil, detail: nil)
          {
            'time'    => match[:time],
            'level'   => match[:level],
            'session' => field(match[:message], 'name'),
            'kind'    => kind,
            'path'    => path,
            'status'  => status,
            'detail'  => detail.nil? || detail.length <= DETAIL_MAX ? detail : "#{detail[0, DETAIL_MAX]}…"
          }
        end

        # Value of `key=...` in a message: a quoted string (`path="..."`), else a space-delimited token
        # @param message [String] the message part of the line
        # @param key     [String] the key to read
        # @return [String, nil] the value, or nil if the key is absent
        def field(message, key)
          match = FIELD_RE[key].match(message)
          match && (match[1] || match[2])
        end
      end
    end
  end
end
