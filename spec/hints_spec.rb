# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/cli/hints'

module Aspera
  module Cli
    RSpec.describe(Hints) do
      # Error class of the examples
      let(:error_class) { Class.new(StandardError) }
      let(:lines) { [] }

      before { allow(Log.log).to(receive(:info)) { |&block| lines.push(block.call) } }

      around do |example|
        added = described_class.instance_variable_get(:@added).dup
        example.run
      ensure
        described_class.instance_variable_set(:@added, added)
      end

      it 'gives the built-in hints of an error' do
        described_class.hint_for(OpenSSL::SSL::SSLError.new('certificate verify failed'), nil)
        expect(lines.join("\n")).to(include('--insecure=yes'))
      end

      it 'gives the hints added by bundles, after the built-in ones: whole message (String) or Regexp' do
        described_class.add(exception: error_class, match: 'exact message', remediation: ['first'])
        described_class.add(exception: error_class, match: [/part/], remediation: %w[second third])
        described_class.hint_for(error_class.new('exact message'), nil)
        described_class.hint_for(error_class.new('exact message and more'), nil)
        described_class.hint_for(error_class.new('a part of it'), nil)
        expect(lines.map { |line| line.split(' ').last }).to(eq(%w[first second third]))
      end

      it 'refuses an invalid hint' do
        expect { described_class.add(exception: 'error_class', match: 'x', remediation: ['y']) }.to(raise_error(AssertError))
        expect { described_class.add(exception: error_class, match: 1, remediation: ['y']) }.to(raise_error(AssertError, /String or Regexp/))
        expect { described_class.add(exception: error_class, match: 'x', remediation: 'y') }.to(raise_error(AssertError))
      end
    end
  end
end
