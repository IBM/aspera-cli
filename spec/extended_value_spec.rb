# frozen_string_literal: true

# Unit tests for Aspera::Cli::ExtendedValue — no server, no config file needed.

require 'stringio'
require 'securerandom'
require 'aspera/cli/extended_value'

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
          allow($stdin).to(receive_messages(tty?: true, getpass: secret))
          expect(evaluate('@secret:pw')).to(eq(secret))
          expect($stdin).to(have_received(:getpass).with('pw> '))
        end

        it 'asks on a web page when user interface is graphical' do
          require 'aspera/cli/web_secret'
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
          allow($stdin).to(receive_messages(tty?: true, getpass: secret))
          evaluate('@secret:pw')
          expect(Secret::Hider.instance.hidden_copy({'a' => ["x #{secret} y"]})).to(eq({'a' => ['x *** y']}))
        ensure
          Environment.unicode = nil
        end
      end
    end
  end
end
