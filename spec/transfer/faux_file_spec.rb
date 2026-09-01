# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/transfer/faux_file'
require 'aspera/transfer/error'

module Aspera
  module Transfer
    RSpec.describe(FauxFile) do
      describe '.create' do
        context 'when the name does not use the faux scheme' do
          it 'returns nil for a plain path' do
            expect(described_class.create('/tmp/file.bin')).to(be_nil)
          end

          it 'returns nil for an http URI' do
            expect(described_class.create('http://example.com/file')).to(be_nil)
          end
        end

        context 'when the URI is malformed' do
          it 'raises when the size part is missing' do
            expect{described_class.create('faux:///file.bin')}.to(raise_error(Aspera::Transfer::Error))
          end

          it 'raises when the unit is unknown' do
            expect{described_class.create('faux:///file.bin?42x')}.to(raise_error(Aspera::Transfer::Error))
          end
        end

        context 'when the URI is valid' do
          it 'returns a FauxFile instance' do
            expect(described_class.create('faux:///file.bin?1k')).to(be_a(described_class))
          end

          it 'sets the correct path' do
            ff = described_class.create('faux:///some/path/file.bin?1k')
            expect(ff.path).to(eq('some/path/file.bin'))
          end

          it 'parses kilobytes' do
            expect(described_class.create('faux:///f?1k').size).to(eq(1024))
          end

          it 'parses megabytes' do
            expect(described_class.create('faux:///f?2m').size).to(eq(2 * 1024**2))
          end

          it 'parses gigabytes' do
            expect(described_class.create('faux:///f?3g').size).to(eq(3 * 1024**3))
          end

          it 'accepts uppercase units' do
            expect(described_class.create('faux:///f?1K').size).to(eq(1024))
          end

          it 'accepts mixed case units' do
            expect(described_class.create('faux:///f?2M').size).to(eq(2 * 1024**2))
          end

          it 'parses raw bytes when no unit is given' do
            expect(described_class.create('faux:///f?10').size).to(eq(10))
          end

          it 'parses zero bytes without unit' do
            expect(described_class.create('faux:///f?0').size).to(eq(0))
          end
        end
      end

      describe '#read' do
        let(:ff){described_class.new('file.bin', 100)}

        it 'returns a string of the requested size when enough bytes remain' do
          expect(ff.read(10).bytesize).to(eq(10))
        end

        it 'returns null bytes' do
          expect(ff.read(4)).to(eq("\x00" * 4))
        end

        it 'returns only the remaining bytes when chunk_size exceeds what is left' do
          ff.read(95)
          expect(ff.read(10).bytesize).to(eq(5))
        end

        it 'returns nil at EOF' do
          ff.read(100)
          expect(ff.read(10)).to(be_nil)
        end

        it 'advances the offset across successive reads' do
          ff.read(60)
          ff.read(40)
          expect(ff).to(be_eof)
        end
      end

      describe '#eof?' do
        it 'is false before any read' do
          expect(described_class.new('f', 10)).not_to(be_eof)
        end

        it 'is true after reading all bytes' do
          ff = described_class.new('f', 10)
          ff.read(10)
          expect(ff).to(be_eof)
        end
      end

      describe '#close' do
        it 'does not raise' do
          expect{described_class.new('f', 10).close}.not_to(raise_error)
        end
      end
    end
  end
end
