# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/cli/deprecation'

module Aspera
  module Cli
    RSpec.describe(Deprecation) do
      describe '.create' do
        it 'builds from a Hash' do
          dep = described_class.create({last: '4.27.0', message: 'use --out.level'})
          expect(dep.last).to(eq('4.27.0'))
          expect(dep.to_s).to(eq('deprecated after 4.27.0: use --out.level'))
        end

        it 'returns nil for nil' do
          expect(described_class.create(nil)).to(be_nil)
        end

        it 'rejects a String' do
          expect { described_class.create('use --out.level') }.to(raise_error(InternalError))
        end

        it 'rejects a missing or invalid version' do
          expect { described_class.create({message: 'use x'}) }.to(raise_error(AssertError))
          expect { described_class.create({last: 'next', message: 'use x'}) }.to(raise_error(AssertError))
        end

        it 'rejects a version not released yet' do
          expect { described_class.create({last: VERSION, message: 'use x'}) }.to(raise_error(AssertError))
        end
      end
    end
  end
end
