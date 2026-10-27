# frozen_string_literal: true

# cspell:ignore abrtxfer
require 'strscan'
require 'time'
require 'aspera/ascp/log_analyzer/rules'
require 'aspera/ascp/log_analyzer/lines'
require 'aspera/schema/registry'
require 'aspera/assert'

module Aspera
  module Ascp
    class LogAnalyzer
      # Lines of an ascp log file parsed into records, with the field names of the log lines:
      # - samples: `Receiver bl` or `Sender bl` line, merged with the `DS Qs` line that follows it
      # - sessions: `Session Start`, `Session Params`, `Session Stop` and `Session Statistics` lines of a session
      # - transfers: `Transfer Start` and `Transfer Stop` lines of a file
      # Fields are described in schema `ascp_log`.
      class Records
        include Lines

        # Kind of record => schema
        SCHEMAS = {
          samples:   "#{Schema::Registry::ASCP_LOG}:components.schemas.Sample",
          sessions:  "#{Schema::Registry::ASCP_LOG}:components.schemas.Session",
          transfers: "#{Schema::Registry::ASCP_LOG}:components.schemas.Transfer"
        }.freeze
        # Message of a line of ascp: `ascp[1234]: LOG <message>` or `[4c58-140234] LOG <message>`
        MESSAGE = /\]:?\s+LOG\s+(.*?)\s*\z/
        # Line message => method called with (pid, time, MatchData)
        MESSAGES = {
          /\A(Receiver|Sender) (bl .*)/            => :sample_line,
          /\A(Receiver|Sender) DS (.*)/            => :queues_line,
          /\AFASP Session (Start|Stop) (.*)/       => :session_line,
          /\AFASP Session Params (.*)/             => :params_line,
          /\AFASP Session Statistics \[\w+\] (.*)/ => :statistics_line,
          /\AFASP Transfer (Start|Stop) (.*)/      => :transfer_line
        }.freeze
        # Group of a sample line: `name k1/k2=v1/v2`, or `key=value` alone
        GROUP_FIELDS = %r{(?:([A-Za-z_]+)\s+)?([A-Za-z_]+(?:/[A-Za-z_]+)*)=(-?\d+(?:/-?\d+)*)}
        # `mgmt backlog i/s/n = 0/3/0 1/4/0` of `DS Qs` lines: one triplet per management socket
        MGMT_BACKLOG = %r{\s*mgmt backlog ([a-z/]+) =((?:\s+-?\d+(?:/-?\d+)*)*)}
        # `[peer errcode=27 errstr="..."]`: fields of the peer
        PREFIXED = /\[(\w+)\s+([^\]]*)\]/
        KEY = %r{([A-Za-z_][\w/]*)=}
        # Value of `key=value`: quoted, in brackets, or up to the next key (it may contain spaces, e.g. `ver=4.4.8.2596 b12cd13`)
        QUOTED = /"(.*?)"(?=\s|\z)/
        BRACKETS = /\[([^\]]*)\]/
        UNQUOTED = %r{.*?(?=\s+(?:\[\w+\s|[A-Za-z_][\w/]*=)|\s*\z)}
        # Group of `Session Statistics`: `(name: key value key value)`, or `(name: value unit)`
        STATISTICS_GROUP = /\(([a-z ]+):\s*([^()]*)\)/
        # Never output: contains user names and emails
        HIDDEN_FIELDS = %w[cookie].freeze
        # Keys with a slash: name of each value
        SPLIT_KEYS = {'exclude_older/newer_than' => %w[exclude_older_than exclude_newer_than]}.freeze
        # Number, with optional unit
        NUMBER = /\A(-?\d+(?:\.\d+)?)\s*([KMG]?bps|ms|s|%)?\z/
        RATE_UNITS = {'Kbps' => 1e3, 'Mbps' => 1e6, 'Gbps' => 1e9}.freeze

        class << self
          # @param kind  [Symbol]        One of the keys of SCHEMAS
          # @param paths [Array<String>] Log files or folders
          # @return [Array<Hash>] records of all log files, with field `log_file` when there are several log files
          def list(kind, paths)
            Aspera.assert_values(kind, SCHEMAS.keys)
            files = paths.flat_map { |path| LogAnalyzer.log_paths(path) }
            files.flat_map do |file|
              rows = new(file).parse.public_send(kind)
              files.size > 1 ? rows.map { |row| {'log_file' => file}.merge(row) } : rows
            end
          end

          # @param kind [Symbol] One of the keys of SCHEMAS
          # @return [Hash{String => String}] dot path of field => JSON type
          def field_types(kind)
            (@field_types ||= {})[kind] ||= {}.tap do |types|
              Schema::Registry.instance.reader(SCHEMAS[kind]).each_property do |schema, _name, full_name, _required|
                types[full_name] = schema.current['type']
              end
            end
          end

          # @param text [String]      Value in log line
          # @param type [String, nil] JSON type of field, `nil` if not in schema
          # @return [String, Integer, Float] value: numbers in bps, ms, s or %, without unit
          def value(text, type)
            return text if type.eql?('string')
            if type.nil?
              return text.to_i if text.match?(/\A-?\d+\z/)
              return text.to_f if text.match?(/\A-?\d+\.\d+\z/)
              return text
            end
            m = text.match(NUMBER) or return text
            number = m[1].to_f * RATE_UNITS.fetch(m[2], 1)
            type.eql?('integer') ? number.round : number
          end
        end

        # @return [Array<Hash>] one record per sample of a session
        attr_reader :samples

        # @param path [String] Log file
        def initialize(path)
          @path = path
          @samples = []
          # uuid => session record
          @sessions = {}
          @transfers = []
          # PID => uuid of current session of process
          @uuids = {}
          # PID => last sample, until its `DS Qs` line
          @last_sample = {}
          # [uuid, file] => transfer record, until its `Transfer Stop` line
          @open_transfers = {}
        end

        # Read and parse the log file
        # @return [self]
        def parse
          File.foreach(@path, mode: 'r:UTF-8') do |line|
            line = line.scrub unless line.valid_encoding?
            parse_line(normalize(line))
          end
          self
        end

        # @return [Array<Hash>] one record per session
        def sessions
          @sessions.values.map(&:compact)
        end

        # @return [Array<Hash>] one record per transferred file
        def transfers
          @transfers.map(&:compact)
        end

        private

        def parse_line(line)
          return unless line.include?(' LOG ')
          pid = line[PID, 1] or return
          process = line[PROCESS, 1]
          return unless process.nil? || process.match?(ASCP_PROCESS)
          message = line[MESSAGE, 1] or return
          MESSAGES.each do |regex, method|
            m = message.match(regex) or next
            stamp = parse_time(line[LINE_TIME, 1])
            send(method, pid, stamp && Time.at(stamp).iso8601, m)
            break
          end
        end

        # @return [Hash] first fields of a sample
        def sample_record(pid, time, side)
          {'time' => time, 'pid' => pid, 'uuid' => @uuids[pid], 'side' => side}.compact
        end

        # `Receiver bl ...` or `Sender bl ...`
        def sample_line(pid, time, m)
          record = sample_record(pid, time, m[1]).merge(group_fields(m[2]))
          @samples.push(record)
          @last_sample[pid] = record
        end

        # `Receiver DS Qs ...` or `Sender DS Qs ...`: in the sample logged before
        def queues_line(pid, time, m)
          text = m[2]
          backlog = text.match(MGMT_BACKLOG)
          text = backlog.pre_match + backlog.post_match if backlog
          queues = group_fields(text)
          if backlog
            keys = backlog[1].split('/')
            queues['mgmt_backlog'] = backlog[2].split.map { |values| keys.zip(values.split('/').map(&:to_i)).to_h }
          end
          record = @last_sample.delete(pid)
          if record.nil? || record['side'] != m[1]
            record = sample_record(pid, time, m[1])
            @samples.push(record)
          end
          record['DS'] = queues
        end

        # @return [Hash] session record of uuid: created on first line
        def session_record(uuid, pid)
          @uuids[pid] = uuid
          @sessions[uuid] ||= {'uuid' => uuid, 'pid' => pid, 'start' => nil, 'stop' => nil}
        end

        # `Session Start` or `Session Stop`: same fields, the ones of `Session Stop` replace the ones of `Session Start`
        def session_line(pid, time, m)
          fields = key_values(m[2])
          uuid = fields['uuid'] or return
          record = session_record(uuid, pid)
          record[m[1].downcase] = time
          record.merge!(typed(fields, :sessions))
        end

        def params_line(pid, _time, m)
          fields = key_values(m[1])
          uuid = fields['uuid'] or return
          session_record(uuid, pid).merge!(typed(fields, :sessions))
        end

        def statistics_line(pid, _time, m)
          fields = statistics_fields(m[1])
          uuid = fields.delete('id') or return
          session_record(uuid, pid).merge!(typed(fields, :sessions))
        end

        # `Transfer Start` or `Transfer Stop`: same fields, the ones of `Transfer Stop` replace the ones of `Transfer Start`
        def transfer_line(pid, time, m)
          fields = key_values(m[2])
          uuid = fields['uuid'] or return
          @uuids[pid] = uuid
          key = [uuid, fields['file']]
          record = m[1].eql?('Stop') ? @open_transfers.delete(key) : nil
          if record.nil?
            record = {'uuid' => uuid, 'pid' => pid, 'start' => nil, 'stop' => nil}
            @transfers.push(record)
            @open_transfers[key] = record if m[1].eql?('Start')
          end
          record[m[1].downcase] = time
          record.merge!(typed(fields, :transfers))
        end

        # @param text [String] groups of a sample line: `name k1/k2=v1/v2`, or `key=value`
        # @return [Hash] name => {key => value}, and key => value. A repeated group gets a number: `bl`, `bl2`
        def group_fields(text)
          seen = Hash.new(0)
          text.scan(GROUP_FIELDS).each_with_object({}) do |(group, keys, numbers), result|
            values = keys.split('/').zip(numbers.split('/').map(&:to_i)).to_h
            if group.nil?
              result.merge!(values)
            else
              seen[group] += 1
              result[seen[group] > 1 ? "#{group}#{seen[group]}" : group] = values
            end
          end
        end

        # @param text [String] `key=value key="value" key=[k=v,k=v] [prefix key=value]`
        # @return [Hash] key => value (String), or Hash for brackets
        def key_values(text)
          fields = {}
          scanner = StringScanner.new(text)
          loop do
            scanner.skip(/\s+/)
            break if scanner.eos?
            if scanner.scan(PREFIXED)
              prefix = scanner[1]
              key_values(scanner[2]).each { |key, value| fields["#{prefix}_#{key}"] = value }
            elsif scanner.scan(KEY)
              key = scanner[1]
              value =
                if scanner.scan(QUOTED) then scanner[1]
                elsif scanner.scan(BRACKETS) then scanner[1].split(',').to_h { |pair| pair.split('=', 2) }
                else scanner.scan(UNQUOTED)
                end
              add_field(fields, key, value)
            else
              scanner.skip(/\S+/)
            end
          end
          fields.except(*HIDDEN_FIELDS)
        end

        # A key with a slash has one value per name: `exclude_older/newer_than=0/0`
        def add_field(fields, key, value)
          if key.include?('/') && value.is_a?(String)
            SPLIT_KEYS.fetch(key) { key.split('/') }.zip(value.split('/')) { |name, part| fields[name] = part }
          else
            fields[key] = value
          end
        end

        # @param text [String] `key=value`, `key value` and `(group: key value key value)` of `Session Statistics`
        # @return [Hash] key => value, group => {key => value}. Key of `a->b.key`: `key`
        def statistics_fields(text)
          fields = {}
          scanner = StringScanner.new(text)
          loop do
            scanner.skip(/\s+/)
            break if scanner.eos?
            if scanner.scan(STATISTICS_GROUP)
              tokens = scanner[2].split
              fields[scanner[1].split.join('_')] = tokens.first&.match?(/\A-?\d/) ? tokens.first : pairs(tokens)
            elsif scanner.scan(/([^\s=]+)=(\S*)/) || scanner.scan(/(\S+)\s+(-?\d\S*)/)
              fields[scanner[1].split(/->|\./).last] = scanner[2]
            else
              scanner.skip(/\S+/)
            end
          end
          fields
        end

        # @param tokens [Array<String>] `key value key value`
        # @return [Hash] key => value. A repeated key with a percentage: `<key>_pct`, e.g. `lost 1 lost 1.47%`
        def pairs(tokens)
          tokens.each_slice(2).with_object({}) do |(key, value), result|
            key = "#{key}_pct" if result.key?(key) && value.to_s.end_with?('%')
            result[key] = value
          end
        end

        # @param fields [Hash]   Values from log line (String)
        # @param kind   [Symbol] Kind of record
        # @return [Hash] values with the type of the field in the schema
        def typed(fields, kind, prefix = '')
          types = self.class.field_types(kind)
          fields.to_h do |key, value|
            path = "#{prefix}#{key}"
            value =
              case value
              when Hash then typed(value, kind, "#{path}.")
              when String then self.class.value(value, types[path])
              else value
              end
            [key, value]
          end
        end
      end
    end
  end
end
