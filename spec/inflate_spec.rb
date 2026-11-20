# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Inflate: decompression with a limit on the size of the result

require 'spec_helper'
require 'zlib'

require_relative '../lib/aspera/inflate'

RSpec.describe(Aspera::Inflate) do
  it 'decompresses data up to the limit' do
    expect(described_class.limited(Zlib::Deflate.deflate('a' * 1000), max_size: 1000, what: 'Data')).to(eq('a' * 1000))
  end

  it 'refuses data larger than the limit when decompressed' do
    expect { described_class.limited(Zlib::Deflate.deflate('a' * 1001), max_size: 1000, what: 'Data') }
      .to(raise_error(Aspera::ParameterError, /Data is too large when decompressed: more than 1000 bytes/))
  end

  it 'stops decompressing when the limit is reached (decompression bomb)' do
    compressor = Zlib::Deflate.new(Zlib::BEST_COMPRESSION)
    chunk = "\0" * (1 << 20)
    # 1 GiB once decompressed, about 1 MB compressed
    bomb = (+'').tap { |data| 1024.times { data << compressor.deflate(chunk) } } << compressor.finish
    compressor.close
    inflater = Zlib::Inflate.new
    allow(Zlib::Inflate).to(receive(:new).and_return(inflater))
    # Bytes decompressed before the error
    inflated = 0
    allow(inflater).to(receive(:inflate).and_wrap_original do |original, data|
      original.call(data).tap { |out| inflated += out.bytesize }
    end)
    expect { described_class.limited(bomb, max_size: 65_536, what: 'Data') }.to(raise_error(Aspera::ParameterError, /too large/))
    # At most one slice of input (4 KiB) beyond the limit: about 4 MiB, not 1 GiB
    expect(inflated).to(be < (8 << 20))
  end

  it 'decompresses data larger than one slice of input' do
    text = Random.new(1).bytes(20_000).unpack1('H*')
    deflated = Zlib::Deflate.deflate(text)
    expect(deflated.bytesize).to(be > 4096)
    expect(described_class.limited(deflated, max_size: text.bytesize, what: 'Data')).to(eq(text))
  end

  it 'ignores data after the end of the zlib stream' do
    expect(described_class.limited(Zlib::Deflate.deflate('abc') + ('x' * 5000), max_size: 10, what: 'Data')).to(eq('abc'))
  end

  it 'refuses incomplete data' do
    expect { described_class.limited(Zlib::Deflate.deflate('a' * 1000)[0..-5], max_size: 1000, what: 'Data') }
      .to(raise_error(Aspera::ParameterError, /Data is incomplete/))
  end

  it 'refuses data that is not zlib' do
    expect { described_class.limited('not zlib', max_size: 1000, what: 'Data') }.to(raise_error(Zlib::Error))
  end
end
