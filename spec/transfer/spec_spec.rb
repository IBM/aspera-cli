# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/transfer/spec'
require_relative '../../lib/aspera/schema/documentation'
require_relative '../../lib/aspera/schema/validator'
require 'bundler/setup'

module Aspera
  module Transfer
    RSpec.describe(Spec) do
      describe '.resolve_target_rate' do
        it 'converts target_rate (bps) into target_rate_kbps' do
          ts = {'target_rate' => '100m'}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 100_000}))
        end

        it 'rounds down to kbps' do
          ts = {'target_rate' => 1_999}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 1}))
        end

        it 'overrides target_rate_kbps' do
          ts = {'target_rate_kbps' => 5, 'target_rate' => '1g'}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 1_000_000}))
        end

        it 'removes a nil target_rate and keeps target_rate_kbps' do
          ts = {'target_rate_kbps' => 5, 'target_rate' => nil}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 5}))
        end

        it 'leaves a transfer spec without target_rate unchanged' do
          ts = {'target_rate_kbps' => 5}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 5}))
        end
      end

      describe '.stringify_exclude_times' do
        it 'sends an integer as a string, for the Node API and transferd, and leaves a string unchanged' do
          ts = {'exclude_newer_than' => -30, 'exclude_older_than' => '-86400', 'target_rate_kbps' => 5}
          described_class.stringify_exclude_times(ts)
          expect(ts).to(eq({'exclude_newer_than' => '-30', 'exclude_older_than' => '-86400', 'target_rate_kbps' => 5}))
        end
      end

      describe '.integer_exclude_times' do
        it 'sends an integer, for Connect' do
          ts = {'exclude_newer_than' => '1700000000', 'exclude_older_than' => 1_600_000_000}
          described_class.integer_exclude_times(ts)
          expect(ts).to(eq({'exclude_newer_than' => 1_700_000_000, 'exclude_older_than' => 1_600_000_000}))
        end

        it 'refuses a negative (relative) time and a value that is not an integer, that Connect ignores' do
          ['-30', -30, 'abc', '2026-01-01T00:00:00Z'].each do |value|
            expect { described_class.integer_exclude_times({'exclude_older_than' => value}) }
              .to(raise_error(ParameterError, /agent connect: exclude_older_than must be a time after the epoch/), value.inspect)
          end
        end
      end

      describe 'schema of exclude_newer_than and exclude_older_than' do
        it 'accepts an integer and a string, as the manual shows (hot folder)' do
          errors = ->(ts) { Schema::Validator.instance.errors(ts, Schema::Registry::TRANSFER_SPEC, partial: true) }
          valid_values = [-8, '-8']
          described_class::EXCLUDE_TIMES.each do |key|
            valid_values.each { |value| expect(errors.call({key => value})).to(be_empty, "#{key}: #{value.inspect}") }
            expect(errors.call({key => 1.5})).not_to(be_empty)
          end
        end
      end

      describe '.doc_options' do
        # Formatter without styling
        let(:formatter) do
          Module.new do
            module_function

            def markdown_text(text) = text.to_s
            def special_format(special) = "<#{special}>"
            def tick(yes) = yes ? 'Y' : ' '
          end
        end

        # @return [Hash] row of each parameter, by name
        def rows(agent = nil)
          Schema::Documentation.new(formatter, described_class::SCHEMA, **described_class.doc_options(agent)).build.rows.to_h { |row| [row['name'], row] }
        end

        it 'lists supported agents, if not all, and the ascp option in the description' do
          expect(rows['preserve_acls']['description'].last(2)).to(eq(['(A, T)', '(`--preserve-acls={enum}`)']))
          expect(rows['cipher']['description']).not_to(include(a_string_starting_with('(A')))
        end

        it 'hides parameters supported by no agent' do
          expect(rows.keys).not_to(include('fasp_url'))
        end

        it 'lists only parameters supported by the given agent' do
          expect(rows(:direct).keys).to(include('preserve_acls'))
          expect(rows(:direct).keys).not_to(include('authentication'))
        end

        it 'adds one column per agent for the overview, without line of agents' do
          documentation = Schema::Documentation.new(formatter, described_class::SCHEMA, **described_class.doc_options(described_class::DOC_OVERVIEW)).build
          expect(documentation.columns).to(eq(%w[name type a c d h n t description]))
          preserve_acls = documentation.rows.find { |row| row['name'].eql?('preserve_acls') }
          expect(preserve_acls.slice('a', 'c', 'n', 't')).to(eq({'a' => 'Y', 'c' => ' ', 'n' => ' ', 't' => 'Y'}))
          expect(preserve_acls['description']).not_to(include('(A, T)'))
        end
      end
    end
  end
end
