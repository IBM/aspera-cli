# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# cspell:ignore errstr fstat zstr zmode zuid zgid zctime zatime zmtime fcount dcount ascmdtypes
require_relative '../../log'
require_relative '../../assert'

module Aspera
  module Plugins
    module Server
      # Run `ascmd` commands using specified executor (usually, remotely on transfer node)
      # Equivalent of SDK "command client"
      # execute: "ascmd -h" to get syntax
      #
      # Protocol (see `ascmdtypes.h`):
      # - Input: one command per line (`as_<operation> <arguments>`), then `as_exit`.
      # - Output: one reply per command, `ascmd` continues after a failed command.
      #   The first reply is the system information: sent at start (protocol 1), or for `as_session_init` (protocol 2).
      # - Replies and their fields are Type-Length-Value: type (1 byte), length (4 bytes), value. Numbers are big endian.
      class AsCmd
        # Operations:
        # - `args`: Integer: the arguments are split into one command per group of this size (at least one group).
        #           Range: all arguments in a single command, their number in the range.
        # - `reply`: types of reply of a successful command (else: `error`).
        OPERATION_SPECS = {
          ls:     {args: 1,    reply: %i[file dir]},
          rm:     {args: 1,    reply: %i[success]},
          mv:     {args: 2,    reply: %i[success]},
          cp:     {args: 2,    reply: %i[success]},
          mkdir:  {args: 1,    reply: %i[success]},
          du:     {args: 1,    reply: %i[size]},
          md5sum: {args: 1,    reply: %i[md5sum]},
          df:     {args: 0..1, reply: %i[df]},
          info:   {args: 0..0, reply: %i[info]}
        }.freeze

        # Enumerations of the protocol start at one: TLV type = index in the list + `ENUM_START`
        ENUM_START = 1

        # Reply types (`as_ftype_e`)
        REPLY_TYPES = %i[file dir size error info success exit df md5sum].freeze

        # Fields of structures, in the order of their enumeration: name and base type, plus `:multiple` for a field that repeats (Array of values).
        # Fields `mode`, `uid` and `gid` are not sent by `ascmd`.
        STRUCTURES = {
          # as_fstat_e
          stat:   [
            %i[name zstr], %i[size int64], %i[mode int32], %i[zmode zstr], %i[uid int32], %i[zuid zstr], %i[gid int32], %i[zgid zstr],
            %i[ctime epoch], %i[zctime zstr], %i[mtime epoch], %i[zmtime zstr], %i[atime epoch], %i[zatime zstr], %i[symlink zstr],
            %i[errno int32], %i[errstr zstr]
          ],
          # as_info_e
          info:   [
            %i[platform zstr], %i[version zstr], %i[lang zstr], %i[territory zstr], %i[codeset zstr], %i[lc_ctype zstr], %i[lc_numeric zstr],
            %i[lc_time zstr], %i[lc_all zstr], %i[dev zstr multiple], %i[browse_caps zstr], %i[protocol zstr]
          ],
          # as_size_e
          size:   [%i[size int64], %i[fcount int32], %i[dcount int32], %i[failed_fcount int32], %i[failed_dcount int32]],
          # as_error_e
          error:  [%i[errno int32], %i[errstr zstr]],
          # as_mnt_e
          mnt:    [
            %i[fs zstr], %i[dir zstr], %i[type zstr], %i[total int64], %i[used int64], %i[free int64], %i[fcount int64], %i[errno int32],
            %i[errstr zstr]
          ],
          # as_md5sum_e
          md5sum: [%i[md5sum zstr]]
        }.freeze

        # Size of the header of a TLV: type (1 byte) and length (4 bytes)
        TLV_HEADER_SIZE = 5
        # `ascmd` reads a command line with `fgets` in a buffer of `AS_MAX_BUFFER` (4096): newline and NUL included
        MAX_LINE_BYTES = 4094

        # A decoded reply
        Reply = Data.define(:type, :value)

        private_constant :OPERATION_SPECS, :ENUM_START, :REPLY_TYPES, :STRUCTURES, :TLV_HEADER_SIZE, :MAX_LINE_BYTES, :Reply

        # list of supported actions
        OPERATIONS = OPERATION_SPECS.keys.freeze

        # Raised when one or more commands of `ascmd` failed. The other commands were executed.
        class Error < StandardError
          # A failed command
          # @!attribute [r] errno     [Integer, nil]  Error number (-1: error of `ascmd` itself), `nil` if no reply
          # @!attribute [r] errstr    [String]        Error message
          # @!attribute [r] arguments [Array<String>] Arguments of the command
          Failure = Data.define(:errno, :errstr, :arguments)

          # @return [Symbol] the operation
          attr_reader :operation
          # @return [Array<Failure>] failed commands, in order
          attr_reader :failures

          # @param operation [Symbol]         the operation
          # @param failures  [Array<Failure>] failed commands
          def initialize(operation, failures)
            @operation = operation
            @failures = failures
            super(failures.map { |f| "ascmd: #{f.errstr}#{" (#{f.errno})" unless f.errno.nil?}" }.join("\n"))
          end

          # @return [String] one line per failed command, with its arguments
          def extended_message
            @failures.map { |f| %Q{ascmd: errno=#{f.errno} errstr="#{f.errstr}" command=#{@operation} arguments=#{f.arguments.join(',')}} }.join("\n")
          end
        end

        # @param command_executor [Object] provides the "execute" method, taking a command to execute, and stdin to feed to it, typically: ssh or local
        def initialize(command_executor)
          @command_executor = command_executor
        end

        # Execute an operation in one session of `ascmd`: one command per group of arguments.
        # All commands are executed, even after one failed.
        # @param operation [Symbol]        One of OPERATIONS
        # @param arguments [Array<String>] Paths (`mv`, `cp`: source and destination pairs)
        # @param version   [Integer]       Protocol: 1 or 2
        # @param host      [String, nil]   Sent with `as_session_init` (protocol 2)
        # @return [true, Array<Hash>, Hash] depending on operation:
        #   `rm`, `mv`, `cp`, `mkdir`: `true`;
        #   `ls`: entries of all paths;
        #   `du`, `md5sum`: one Hash per path, with key `path`;
        #   `df`: mount points;
        #   `info`: system information.
        # @raise [Error] if one or more commands failed
        # @raise [ParameterError] if the arguments do not fit the operation, or cannot be sent to `ascmd`
        def execute_single(operation, arguments, version: 2, host: nil)
          arguments = [] if arguments.nil?
          Log.log.debug { "execute_single:#{operation}:#{arguments}" }
          Aspera.assert_values(operation, OPERATIONS)
          Aspera.assert_values(version, [1, 2]) { 'protocol' }
          Aspera.assert_array_all(arguments, String) { 'arguments' }
          commands = command_arguments(operation, arguments)
          remote_cmd = 'ascmd'
          lines = []
          if version.eql?(2)
            lines.push(['as_session_init', "--protocol=#{version}", (quote("--host=#{host}") unless host.nil?)].compact.join(' '))
            remote_cmd += ' -V2'
          end
          commands.each { |args| lines.push(["as_#{operation}", *args.map { |arg| quote(arg) }].join(' ')) }
          lines.each do |line|
            Aspera.assert(line.bytesize <= MAX_LINE_BYTES, type: ParameterError) { "ascmd: command longer than #{MAX_LINE_BYTES} bytes: #{line[0, 80]}..." }
          end
          lines.push('as_exit', '')
          stdin_input = lines.join("\n")
          Log.log.trace1 { "execute_single:#{stdin_input}" }
          output = @command_executor.execute(remote_cmd, input: stdin_input)
          Aspera.assert(!output.empty?, 'empty answer from server')
          replies = each_tlv(output).map { |id, value| decode_reply(id, value) }
          Log.log.trace1 { "execute_single:replies=#{replies}" }
          system_info = replies.shift
          # `ascmd` failed to start, e.g. invalid docroot
          raise Error.new(operation, [failure(system_info.value, [])]) if system_info.type.eql?(:error)
          Aspera.assert(system_info.type.eql?(:info)) { "ascmd: expecting system information first, but have: #{system_info.type}" }
          Aspera.assert(replies.length <= commands.length) { "ascmd: #{replies.length} replies for #{commands.length} commands" }
          failures = []
          commands.each_with_index do |args, index|
            reply = replies[index]
            if reply.nil?
              # `ascmd` stopped before this command
              failures.push(Error::Failure.new(errno: nil, errstr: 'no reply', arguments: args))
            elsif reply.type.eql?(:error)
              failures.push(failure(reply.value, args))
            else
              Aspera.assert_values(reply.type, OPERATION_SPECS[operation][:reply]) { "ascmd: reply to #{operation}" }
            end
          end
          raise Error.new(operation, failures) unless failures.empty?
          return result_of(operation, commands, replies)
        end

        private

        # Arguments of each command of the operation
        # @param operation [Symbol]        One of OPERATIONS
        # @param arguments [Array<String>] Arguments of the operation
        # @return [Array<Array<String>>] arguments of each command
        def command_arguments(operation, arguments)
          count = OPERATION_SPECS[operation][:args]
          case count
          when Integer
            Aspera.assert(!arguments.empty? && (arguments.length % count).zero?, type: ParameterError) do
              "ascmd #{operation}: expecting a non-zero multiple of #{count} arguments, but have #{arguments.length}"
            end
            arguments.each_slice(count).to_a
          when Range
            Aspera.assert(count.cover?(arguments.length), type: ParameterError) { "ascmd #{operation}: expecting #{count} arguments, but have #{arguments.length}" }
            [arguments]
          else Aspera.error_unexpected_value(count) { 'args' }
          end
        end

        # Argument of a command line of `ascmd`: in double quotes, `"` and `\` escaped.
        # A newline cannot be escaped: it ends the command, the rest would be another command.
        # @param value [String] the argument
        # @return [String] quoted argument
        def quote(value)
          Aspera.assert(!value.match?(/[\n\0]/), type: ParameterError) { "ascmd: newline and NUL characters are not supported: #{value.inspect}" }
          %Q{"#{value.gsub(/["\\]/) { |s| "\\#{s}" }}"}
        end

        # @param error     [Hash]          Value of a reply `error`
        # @param arguments [Array<String>] Arguments of the command
        # @return [Error::Failure]
        def failure(error, arguments)
          Error::Failure.new(errno: error[:errno], errstr: error[:errstr], arguments: arguments)
        end

        # Result of the operation, from the replies of its successful commands
        # @param operation [Symbol]               One of OPERATIONS
        # @param commands  [Array<Array<String>>] Arguments of each command
        # @param replies   [Array<Reply>]         Reply of each command
        def result_of(operation, commands, replies)
          case operation
          when :rm, :mv, :cp, :mkdir then true
          when :ls
            replies.flat_map do |reply|
              case reply.type
              when :dir then reply.value
              when :file then [reply.value]
              else Aspera.error_unexpected_value(reply.type) { 'reply' }
              end
            end
          when :du, :md5sum then commands.zip(replies).map { |args, reply| {path: args.first}.merge(reply.value) }
          when :df, :info then replies.first.value
          else Aspera.error_unexpected_value(operation) { 'operation' }
          end
        end

        # Iterate on a sequence of TLV
        # @param data [String] Binary data
        # @yieldparam id    [Integer] TLV type
        # @yieldparam value [String]  TLV value
        # @return [Enumerator] if no block given
        def each_tlv(data)
          return enum_for(__method__, data) unless block_given?
          offset = 0
          while offset < data.bytesize
            Aspera.assert(offset + TLV_HEADER_SIZE <= data.bytesize) { "ascmd: truncated header at #{offset}" }
            id, length = data.unpack('CL>', offset: offset)
            offset += TLV_HEADER_SIZE
            Aspera.assert(offset + length <= data.bytesize) { "ascmd: truncated value at #{offset}, length #{length}" }
            yield(id, data.byteslice(offset, length))
            offset += length
          end
        end

        # @param id    [Integer] TLV type of the reply
        # @param value [String]  TLV value
        # @return [Reply]
        def decode_reply(id, value)
          type = enum_value(REPLY_TYPES, id)
          Aspera.assert(!type.nil?) { "ascmd: unknown reply type: #{id}" }
          decoded =
            case type
            when :file then decode_structure(:stat, value)
            # entries are replies `file`
            when :dir
              each_tlv(value).map do |entry_id, entry|
                Aspera.assert(enum_value(REPLY_TYPES, entry_id).eql?(:file)) { "ascmd: dir: unexpected entry type: #{entry_id}" }
                decode_structure(:stat, entry)
              end
            # mount points one after the other, each one starts with its first field
            when :df then decode_structure(:mnt, value, list: true)
            when :size, :error, :info, :md5sum then decode_structure(type, value)
            when :success then true
            else Aspera.error_unexpected_value(type) { 'reply' }
            end
          Reply.new(type: type, value: decoded)
        end

        # @param name  [Symbol]  Structure name
        # @param data  [String]  Its fields as TLV
        # @param list  [Boolean] `true`: several structures, each one starts with its first field
        # @return [Hash, Array<Hash>] decoded structure, or list of structures
        def decode_structure(name, data, list: false)
          structures = []
          each_tlv(data) do |id, value|
            structures.push({}) if structures.empty? || (list && id.eql?(ENUM_START))
            field_name, type, repeat = enum_value(STRUCTURES[name], id)
            Aspera.assert(!field_name.nil?) { "ascmd: #{name}: unknown field: #{id}" }
            decoded = decode_value(type, value)
            fields = structures.last
            case repeat
            when nil
              Aspera.assert(!fields.key?(field_name)) { "ascmd: #{name}: duplicate field: #{field_name}" }
              fields[field_name] = decoded
            when :multiple then (fields[field_name] ||= []).push(decoded)
            else Aspera.error_unexpected_value(repeat) { 'field' }
            end
          end
          return structures if list
          return structures.first || {}
        end

        # @param list [Array]   Values of an enumeration of the protocol, in order
        # @param id   [Integer] TLV type
        # @return [Object, nil] the value, `nil` if unknown (a negative index would wrap around)
        def enum_value(list, id)
          list[id - ENUM_START] if id >= ENUM_START
        end

        # @param type  [Symbol] Base type
        # @param value [String] Binary value
        # @return [String, Integer, Time] decoded value
        def decode_value(type, value)
          case type
          when :zstr then value.unpack1('Z*').force_encoding(Encoding::UTF_8)
          # signed: errno is -1 for an error of ascmd itself
          when :int32 then decode_number(value, 'l>', 4)
          when :int64 then decode_number(value, 'Q>', 8)
          # signed: seconds since 1970
          when :epoch then Time.at(decode_number(value, 'q>', 8))
          else Aspera.error_unexpected_value(type) { 'base type' }
          end
        end

        # @param value  [String]  Binary value
        # @param format [String]  Format of `unpack1`
        # @param size   [Integer] Expected size in bytes
        # @return [Integer]
        def decode_number(value, format, size)
          Aspera.assert(value.bytesize.eql?(size)) { "ascmd: expecting #{size} bytes, but have #{value.bytesize}" }
          value.unpack1(format)
        end
      end
    end
  end
end
