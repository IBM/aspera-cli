# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Cli::ExtendedValue — no server, no config file needed.

require_relative '../lib/aspera/cli/extended_value'
require 'stringio'
require 'securerandom'
require 'tempfile'

module Aspera
  module Cli
    RSpec.describe(ExtendedValue) do
      subject(:extended) { described_class.instance }

      def evaluate(value) = extended.evaluate(value, context: 'test')

      describe '#evaluate' do
        it 'decodes a value starting with a decoder, including a multi-line parameter' do
          expect(evaluate(%Q(@json:{\n"a": 1\n}))).to(eq({'a' => 1}))
        end

        it 'does not decode a multi-line value whose other lines start with a decoder' do
          value = "first line\n@env:HOME"
          expect(evaluate(value)).to(eq(value))
          value = "first line\n@ruby:1+1"
          expect(evaluate(value)).to(eq(value))
        end

        it 'evaluates embedded values anywhere with @extend:' do
          ENV['ASCLI_TEST_EXTEND'] = 'value'
          expect(evaluate("@extend:line 1\nx @env:ASCLI_TEST_EXTEND@ y")).to(eq("line 1\nx value y"))
        ensure
          ENV.delete('ASCLI_TEST_EXTEND')
        end

        it 'decodes first a single extended value on the right of @extend:, then evaluates embedded values' do
          ENV['ASCLI_TEST_EXTEND'] = 'value'
          Tempfile.create(['extend', '.json']) do |file|
            file.write('{"a":["@env:ASCLI_TEST_EXTEND@"]}')
            file.close
            expect(evaluate("@json:@extend:@file:#{file.path}")).to(eq({'a' => ['value']}))
            # Embedded value: inserted as is
            expect(evaluate("@extend:@file:#{file.path}@")).to(eq('{"a":["@env:ASCLI_TEST_EXTEND@"]}'))
          end
        ensure
          ENV.delete('ASCLI_TEST_EXTEND')
        end

        it 'refuses @env: of a variable that is not set, with its name, also embedded' do
          ENV.delete('ASCLI_TEST_NOT_SET')
          expect { evaluate('@env:ASCLI_TEST_NOT_SET') }.to(raise_error(BadArgument, /environment variable ASCLI_TEST_NOT_SET is not set/))
          expect { evaluate('@extend:a=@env:ASCLI_TEST_NOT_SET@') }.to(raise_error(BadArgument, /environment variable ASCLI_TEST_NOT_SET is not set/))
        end

        it 'gives the value of @env: of a variable set to an empty string' do
          ENV['ASCLI_TEST_EMPTY'] = ''
          expect(evaluate('@env:ASCLI_TEST_EMPTY')).to(eq(''))
        ensure
          ENV.delete('ASCLI_TEST_EMPTY')
        end

        it 'does not evaluate again a value inserted by @extend:' do
          ENV['ASCLI_TEST_EXTEND'] = '@env:HOME@'
          expect(evaluate('@extend:a=@env:ASCLI_TEST_EXTEND@ b')).to(eq('a=@env:HOME@ b'))
        ensure
          ENV.delete('ASCLI_TEST_EXTEND')
        end
      end

      describe '@stdin:' do
        around do |example|
          saved = $stdin
          $stdin = StringIO.new("line\n")
          example.run
        ensure
          $stdin = saved
        end

        it 'reads standard input' do
          expect(evaluate('@stdin:')).to(eq("line\n"))
        end

        it 'reads standard input without final newline with chomp' do
          expect(evaluate('@stdin:chomp')).to(eq('line'))
        end

        it 'gives the standard input, read by the command, with stream' do
          stream = extended.evaluate('@stdin:stream', context: 'test', allowed: [String, StandardInput])
          expect(stream).to(be_a(StandardInput))
          expect(stream.to_s).to(eq('-'))
          expect(stream.read).to(eq("line\n"))
        end

        it 'refuses stream where a command does not read a file, or with a decoder' do
          expect { evaluate('@stdin:stream') }.to(raise_error(BadArgument, /@stdin:stream is only for a command that reads a file, not for test: use @stdin:/))
          expect { evaluate('@extend:x@stdin:stream@') }.to(raise_error(BadArgument, /@stdin:stream is only for a command that reads a file/))
          expect { extended.evaluate('@json:@stdin:stream', context: 'test', allowed: [String, StandardInput]) }.to(raise_error(BadArgument, /@json: for test: @stdin:stream is read by the command, it cannot be decoded/))
          expect($stdin.read).to(eq("line\n"))
        end

        it 'refuses an unknown mode' do
          expect { evaluate('@stdin:foo') }.to(raise_error(BadArgument, /supports only: "", "bin", "chomp", "stream"/))
        end
      end

      describe '@secret:' do
        around do |example|
          saved = Environment.instance.url_method
          example.run
        ensure
          Environment.instance.url_method = saved
        end

        it 'asks on terminal when user interface is text' do
          Environment.instance.url_method = :text
          secret = SecureRandom.alphanumeric(12)
          type_on_terminal(secret)
          expect { expect(evaluate('@secret:pw')).to(eq(secret)) }.to(output(/\Apw> /).to_stderr)
        end

        it 'asks on a web page when user interface is graphical' do
          require_relative '../lib/aspera/cli/web_secret'
          Environment.instance.url_method = :graphical
          secret = SecureRandom.alphanumeric(12)
          allow(WebSecret).to(receive(:ask).and_return(secret))
          expect(evaluate('@secret:')).to(eq(secret))
          expect(WebSecret).to(have_received(:ask).with('secret'))
        end

        it 'declares the secret, so that it is hidden wherever it appears' do
          Environment.instance.url_method = :text
          Environment.unicode = false
          secret = SecureRandom.alphanumeric(12)
          type_on_terminal(secret)
          evaluate('@secret:pw')
          expect(Secret::Hider.instance.hidden_copy({'a' => ["x #{secret} y"]})).to(eq({'a' => ['x *** y']}))
        ensure
          Environment.unicode = nil
        end
      end
    end
  end
end
