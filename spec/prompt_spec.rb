# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Prompt — no terminal needed.

require_relative '../lib/aspera/prompt'
require 'securerandom'

module Aspera
  RSpec.describe(Prompt) do
    let(:secret) { SecureRandom.alphanumeric(12) }

    # marks without Unicode: `***` (empty) and `...` (not empty)
    before { allow(Environment).to(receive(:unicode_environment?).and_return(false)) }

    describe '.prompt_user_input' do
      it 'reads a line from standard input' do
        allow($stdin).to(receive_messages(tty?: false, gets: "#{secret}\n"))
        expect { expect(described_class.prompt_user_input('pw')).to(eq(secret)) }.to(output("pw> ").to_stderr)
      end

      it 'fails on end of standard input' do
        allow($stdin).to(receive_messages(tty?: false, gets: nil))
        expect { described_class.prompt_user_input('pw') }.to(raise_error(Aspera::AssertError, /Unexpected end of standard input/).and(output.to_stderr))
      end

      context 'with sensitive input on a terminal' do
        it 'hides the input, and shows only whether it is empty' do
          type_on_terminal(secret)
          expect { expect(described_class.prompt_user_input('pw', sensitive: true)).to(eq(secret)) }.to(output("pw> ***\b \b\b \b\b \b...\r\n").to_stderr)
        end

        it 'handles erase keys' do
          type_on_terminal("ab\u007fc d\u0017e\u0015xy")
          expect { expect(described_class.prompt_user_input('pw', sensitive: true)).to(eq('xy')) }.to(output.to_stderr)
        end

        context 'with hidden_silent' do
          around do |example|
            Environment.instance.hidden_silent = true
            example.run
          ensure
            Environment.instance.hidden_silent = false
          end

          it 'reads without echo, and without mark' do
            allow($stdin).to(receive(:tty?).and_return(true))
            allow($stdin).to(receive(:noecho)) { |&block| block.call(StringIO.new("#{secret}\n")) }
            expect { expect(described_class.prompt_user_input('pw', sensitive: true)).to(eq(secret)) }.to(output("pw> \n").to_stderr)
          end

          it 'reads a line if the terminal cannot disable echo' do
            allow($stdin).to(receive(:tty?).and_return(true))
            allow($stdin).to(receive(:noecho).and_raise(Errno::ENOTTY))
            allow($stdin).to(receive(:gets).and_return("#{secret}\n"))
            expect { expect(described_class.prompt_user_input('pw', sensitive: true)).to(eq(secret)) }.to(output('pw> ').to_stderr)
          end
        end

        context 'with validate' do
          # accepts only "good" (its result is not used)
          let(:validate) { ->(text) { text.eql?('good') ? :ignored : raise(Aspera::ParameterError, 'Bad input') } }

          around do |example|
            saved = Rainbow.enabled
            Rainbow.enabled = false
            example.run
          ensure
            Rainbow.enabled = saved
          end

          it 'shows if the input is valid, and returns the input' do
            type_on_terminal('good')
            # g, go, goo: invalid; good: valid
            expect { expect(described_class.prompt_user_input('pw', sensitive: true, validate: validate)).to(eq('good')) }
              .to(output("pw> ***#{"\b \b" * 3}invalid#{"\b \b" * 7}valid\r\n").to_stderr)
          end

          it 'shows a colored check mark or cross with Unicode' do
            allow(Environment).to(receive(:unicode_environment?).and_return(true))
            Rainbow.enabled = true
            type_on_terminal("x\u0015good")
            erase = "\b \b"
            cross = Rainbow('✗').red
            expect { described_class.prompt_user_input('pw', sensitive: true, validate: validate) }
              .to(output("pw> 🔑#{erase * 2}#{cross}#{erase}🔑#{erase * 2}#{cross}#{erase}#{Rainbow('✓').green}\r\n").to_stderr)
          end

          it 'displays the error and asks again if the input is not valid' do
            inputs = %W[bad\r good\r]
            allow($stdin).to(receive(:tty?).and_return(true))
            allow($stdin).to(receive(:raw)) { |&block| block.call(StringIO.new(inputs.shift)) }
            expect { expect(described_class.prompt_user_input('pw', sensitive: true, validate: validate)).to(eq('good')) }
              .to(output(/\Apw> [^\n]*invalid\r\nBad input\. Try again, or Ctrl-C to stop\.\npw> [^\n]*\x08valid\r\n\z/).to_stderr)
          end

          it 'raises the error if standard input is not a terminal' do
            allow($stdin).to(receive_messages(tty?: false, gets: "bad\n"))
            expect { described_class.prompt_user_input('pw', sensitive: true, validate: validate) }.to(raise_error(Aspera::ParameterError, 'Bad input').and(output('pw> ').to_stderr))
          end

          it 'returns the input if standard input is not a terminal' do
            allow($stdin).to(receive_messages(tty?: false, gets: "good\n"))
            expect { expect(described_class.prompt_user_input('pw', sensitive: true, validate: validate)).to(eq('good')) }.to(output('pw> ').to_stderr)
          end
        end

        # error depends on the OS: ENODEV (macOS), ENOTTY (Linux)
        [Errno::ENODEV, Errno::ENOTTY].each do |error|
          it "reads a line if the terminal has no raw mode (#{error.name})" do
            allow($stdin).to(receive(:tty?).and_return(true))
            allow($stdin).to(receive(:raw).and_raise(error))
            allow($stdin).to(receive(:gets).and_return("#{secret}\n"))
            expect { expect(described_class.prompt_user_input('pw', sensitive: true)).to(eq(secret)) }.to(output("pw> ***\b \b\b \b\b \b").to_stderr)
          end
        end
      end
    end
  end
end
