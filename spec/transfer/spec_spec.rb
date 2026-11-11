# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/transfer/spec'
require 'aspera/schema/documentation'

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
