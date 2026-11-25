# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# cspell:ignore errstr zmode zstr fcount dcount
require 'spec_helper'
require_relative '../ascmd'
require_relative '../commands'
require_relative '../../../cli/parser'
require_relative '../../../cli/context'

# Replies of `ascmd`, encoded as by `asfield.c`: type (1 byte), length (4 bytes, big endian), value
module AscmdReplies
  module_function

  def tlv(type, value) = [type, value.bytesize].pack('CL>') + value.b
  def zstr(type, text) = tlv(type, "#{text}\0")
  def int32(type, value) = tlv(type, [value].pack('l>'))
  def int64(type, value) = tlv(type, [value].pack('q>'))

  # Reply types
  def info(platform = 'Linux') = tlv(5, zstr(1, platform) + zstr(2, '4.4') + zstr(3, 'C') + zstr(10, '/') + zstr(10, '/data'))
  def success = tlv(6, '')
  def error(errno, errstr) = tlv(4, int32(1, errno) + zstr(2, errstr))
  def stat(name, mtime: 1_700_000_000) = zstr(4, '-rw-r--r--') + int64(2, 10) + int64(11, mtime) + zstr(1, name)
  def file(name, **) = tlv(1, stat(name, **))
  def dir(*names) = tlv(2, names.map { |n| file(n) }.join)
  def size(bytes) = tlv(3, int64(1, bytes) + int32(2, 1) + int32(3, 0))
  def md5sum(sum) = tlv(9, zstr(1, sum))
end

# Executor double: records the command and its input, and returns the given output
class AscmdExecutor
  attr_reader :command, :input

  def initialize(output)
    @output = output
  end

  def execute(command, input:)
    @command = command
    @input = input
    @output
  end
end

RSpec.describe(Aspera::Plugins::Server::AsCmd) do
  include AscmdReplies

  def execute(output, operation, arguments, **)
    @executor = AscmdExecutor.new(output)
    described_class.new(@executor).execute_single(operation, arguments, **)
  end

  describe 'commands' do
    it 'starts a session of protocol 2, one command per path, then exits' do
      execute(info + success + success, :rm, %w[/a /b])
      expect(@executor.command).to(eq('ascmd -V2'))
      expect(@executor.input).to(eq(%Q{as_session_init --protocol=2\nas_rm "/a"\nas_rm "/b"\nas_exit\n}))
    end

    it 'has no session initialization with protocol 1' do
      execute(info + success, :mkdir, %w[/a], version: 1)
      expect(@executor.command).to(eq('ascmd'))
      expect(@executor.input).to(eq(%Q{as_mkdir "/a"\nas_exit\n}))
    end

    it 'sends one command per source and destination pair' do
      execute(info + success + success, :mv, %w[/a /b /c /d])
      expect(@executor.input.lines[1..2]).to(eq([%Q{as_mv "/a" "/b"\n}, %Q{as_mv "/c" "/d"\n}]))
    end

    it 'escapes quotes and backslashes' do
      execute(info + success, :rm, ['/my "dir"\\x'])
      expect(@executor.input.lines[1]).to(eq(%Q{as_rm "/my \\"dir\\"\\\\x"\n}))
    end

    it 'refuses a newline or NUL character, which would start another command' do
      ["/a\nas_rm /b\n", "/a\0"].each do |path|
        expect { execute(info + success, :rm, [path]) }.to(raise_error(Aspera::ParameterError, /newline and NUL/))
        expect(@executor.input).to(be_nil)
      end
    end

    it 'refuses a command line longer than ascmd reads' do
      expect { execute(info + success, :ls, ["/#{'a' * 4094}"]) }.to(raise_error(Aspera::ParameterError, /longer than 4094 bytes/))
    end

    it 'checks the number of arguments' do
      expect { execute(info, :ls, []) }.to(raise_error(Aspera::ParameterError, /non-zero multiple of 1 arguments, but have 0/))
      expect { execute(info, :cp, %w[/a /b /c]) }.to(raise_error(Aspera::ParameterError, /non-zero multiple of 2 arguments, but have 3/))
      expect { execute(info, :df, %w[/a /b]) }.to(raise_error(Aspera::ParameterError, /expecting 0..1 arguments, but have 2/))
      expect { execute(info, :info, %w[/a]) }.to(raise_error(Aspera::ParameterError, /expecting 0..0 arguments, but have 1/))
    end

    it 'refuses an unknown operation' do
      expect { execute(info, :chmod, %w[/a]) }.to(raise_error(Aspera::AssertError, /expecting one of/))
    end
  end

  describe 'results' do
    it 'returns the system information' do
      result = execute(info('Darwin') + info('Linux'), :info, [])
      expect(result).to(eq({platform: 'Linux', version: '4.4', lang: 'C', dev: %w[/ /data]}))
    end

    it 'lists the entries of all paths, files and folders' do
      result = execute(info + file('f1') + dir('d1', 'd2') + dir, :ls, %w[/f1 /d /empty])
      expect(result.map { |e| e[:name] }).to(eq(%w[f1 d1 d2]))
      expect(result.first).to(eq({zmode: '-rw-r--r--', size: 10, mtime: Time.at(1_700_000_000), name: 'f1'}))
    end

    it 'decodes dates as signed' do
      result = execute(info + file('old', mtime: -86_400), :ls, %w[/old])
      expect(result.first[:mtime]).to(eq(Time.at(-86_400)))
    end

    it 'returns one row per path for du and md5sum' do
      expect(execute(info + size(100) + size(200), :du, %w[/a /b])).to(eq([
        {path: '/a', size: 100, fcount: 1, dcount: 0},
        {path: '/b', size: 200, fcount: 1, dcount: 0}
      ]))
      expect(execute(info + md5sum('0123'), :md5sum, %w[/a])).to(eq([{path: '/a', md5sum: '0123'}]))
    end

    it 'returns the mount points of df, each one starting with field fs' do
      mounts = tlv(8, zstr(1, '/dev/sda') + zstr(2, '/') + zstr(3, 'ext4') + int64(4, 1000) + zstr(1, '/dev/sdb') + int32(8, 13) + zstr(9, 'Permission denied'))
      expect(execute(info + mounts, :df, [])).to(eq([
        {fs: '/dev/sda', dir: '/', type: 'ext4', total: 1000},
        {fs: '/dev/sdb', errno: 13, errstr: 'Permission denied'}
      ]))
    end

    it 'returns true when all commands succeed' do
      expect(execute(info + success + success, :cp, %w[/a /b /c /d])).to(be(true))
    end
  end

  describe 'errors' do
    it 'raises the error of a command' do
      expect { execute(info + error(2, 'No such file or directory'), :rm, %w[/a]) }.to(raise_error(described_class::Error, 'ascmd: No such file or directory (2)'))
    end

    it 'reports each failed command, after all commands are executed' do
      execute(info + error(2, 'No such file or directory') + success + error(13, 'Permission denied'), :rm, %w[/a /b /c])
      raise 'shall fail'
    rescue described_class::Error => e
      expect(e.failures.map(&:arguments)).to(eq([%w[/a], %w[/c]]))
      expect(e.message).to(eq("ascmd: No such file or directory (2)\nascmd: Permission denied (13)"))
      expect(e.extended_message.lines.last).to(eq('errno=13 errstr="Permission denied" command=rm arguments=/c'))
    end

    # @return [Class] class of the error raised for the replies
    def error_class(replies, arguments = %w[/a])
      execute(replies, :rm, arguments)
      raise 'shall fail'
    rescue described_class::Error => e
      e.class
    end

    it 'raises the class of the error number of the platform when all commands failed for the same reason' do
      {
        'Linux 6.8.0 #1 SMP'                       => {NotFound: [2, 20], AccessDenied: [1, 13, 28_672], Error: [3, 5, 17, 39, -1]},
        'Darwin 27.2.0 Darwin Kernel Version 27.2' => {NotFound: [2, 20], AccessDenied: [1, 13, 28_672], Error: [3, 66]},
        'Microsoft Windows 10.0 '                  => {NotFound: [2, 3, 267], AccessDenied: [5, 28_672], Error: [1, 13, 20, 145]}
      }.each do |platform, classes|
        classes.each do |name, codes|
          codes.each do |errno|
            expect(error_class(info(platform) + error(errno, 'text') + error(errno, 'text'), %w[/a /b])).to(be(described_class.const_get(name)), "#{platform}: #{errno}")
          end
        end
      end
    end

    it 'raises Error when the commands failed for different reasons, or without reply' do
      expect(error_class(info + error(2, 'No such file or directory') + error(13, 'Permission denied'), %w[/a /b])).to(be(described_class::Error))
      expect(error_class(info + error(2, 'No such file or directory'), %w[/a /b])).to(be(described_class::Error))
    end

    it 'raises the class of an error at start only for the error numbers of all platforms' do
      expect(error_class(error(2, 'Invalid docroot'))).to(be(described_class::NotFound))
      expect(error_class(error(28_672, 'Invalid doc root path'))).to(be(described_class::AccessDenied))
      expect(error_class(error(13, 'Access denied due to invalid authorization'))).to(be(described_class::Error))
    end

    it 'decodes errno as signed (-1: error of ascmd itself)' do
      expect { execute(info + error(-1, 'Usage: as_rm <path>'), :rm, %w[/a]) }.to(raise_error(described_class::Error, 'ascmd: Usage: as_rm <path> (-1)'))
    end

    it 'reports the commands without reply' do
      execute(info + success, :rm, %w[/a /b])
      raise 'shall fail'
    rescue described_class::Error => e
      expect(e.failures).to(eq([described_class::Error::Failure.new(errno: nil, errstr: 'no reply', arguments: %w[/b])]))
      expect(e.message).to(eq('ascmd: no reply'))
    end

    it 'raises the error of ascmd at start' do
      expect { execute(error(2, 'Invalid docroot'), :ls, %w[/a]) }.to(raise_error(described_class::Error, 'ascmd: Invalid docroot (2)'))
    end

    it 'refuses data not conforming to the protocol' do
      {
        'empty answer from server'                          => '',
        'expecting system information first'                => success,
        '2 replies for 1 commands'                          => info + success + success,
        'reply to rm: expecting one of [:success]'          => info + size(1),
        'unknown reply type: 42'                            => info + tlv(42, ''),
        'unknown reply type: 0'                             => info + tlv(0, ''),
        'stat: unknown field: 18'                           => info + tlv(1, zstr(18, 'x')),
        'stat: unknown field: 0'                            => info + tlv(1, zstr(0, 'x')),
        'stat: duplicate field: name'                       => info + tlv(1, zstr(1, 'a') + zstr(1, 'b')),
        'dir: unexpected entry type: 3'                     => info + tlv(2, size(1)),
        'expecting 8 bytes, but have 4'                     => info + tlv(1, int32(2, 10)),
        'truncated header at 0'                             => "\x01\x00",
        'truncated value at 5, length 10'                   => tlv(5, '')[0, 1] + [10].pack('L>')
      }.each do |message, output|
        expect { execute(output, :rm, %w[/a]) }.to(raise_error(Aspera::AssertError, /#{Regexp.escape(message)}/))
      end
    end
  end
end

# Commands of `ascmd` in plugin `server`
RSpec.describe(Aspera::Plugins::Server::Commands) do
  include AscmdReplies

  let(:parser) { Aspera::Cli::Parser.new('server') }
  let(:context) do
    ctx = Aspera::Cli::Context.new
    ctx.man_header = false
    ctx.options = parser
    ctx
  end
  let(:server) { described_class.new(context: context) }

  before do
    described_class.declare_options(parser, target: server)
  end

  def executor(output)
    AscmdExecutor.new(output).tap { |e| allow(server).to(receive(:ascmd_executor).and_return(e)) }
  end

  it 'shows one row per path for du' do
    executor(info + size(100) + size(200))
    result = server.action_du(paths: %w[/a /b])
    expect(result).to(be_a(Aspera::Cli::Result::ObjectList))
    expect(result.data.map { |r| r.values_at('path', 'size') }).to(eq([['/a', 100], ['/b', 200]]))
  end

  it 'reports the failed commands with their arguments and the exit code of their category' do
    {
      error(2, 'No such file or directory') => Aspera::Cli::ExitCode::NOT_FOUND,
      error(13, 'Permission denied')        => Aspera::Cli::ExitCode::AUTH,
      error(17, 'File exists')              => Aspera::Cli::ExitCode::API
    }.each do |reply, code|
      executor(info + success + reply)
      expect { server.action_rm(paths: %w[/a /b]) }.to(raise_error(Aspera::Plugins::Server::AsCmd::Error, %r{\Aerrno=\d+ .* command=rm arguments=/b\z}) do |e|
        expect(Aspera::Cli::ExitCode.error_category(e)).to(eq({label: 'ascmd', code: code}))
      end)
    end
  end

  it 'reports a path that cannot be sent as a bad argument' do
    executor(info + success)
    expect { server.action_rm(paths: ["/a\nb"]) }.to(raise_error(Aspera::Cli::BadArgument, /newline and NUL/))
  end
end
