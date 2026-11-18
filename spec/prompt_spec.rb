# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Cli::Prompt — no terminal needed.

require_relative '../lib/aspera/cli/prompt'
require 'securerandom'

module Aspera
  module Cli
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
            expect { expect(described_class.prompt_user_input('pw', sensitive: true)).to(eq(secret)) }.to(output("pw> ***\b \b\b \b\b \b...\n").to_stderr)
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
end
