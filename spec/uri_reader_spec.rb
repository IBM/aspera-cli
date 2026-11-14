# frozen_string_literal: true

require_relative '../lib/aspera/uri_reader'
require 'bundler/setup'

RSpec.describe(Aspera::UriReader) do
  it 'fails on bad uri' do
    Aspera::UriReader.read('unknown:///foo.bar')
    raise 'Shall not reach here'
  rescue Aspera::InternalError => e
    expect(e.message).to(include('unexpected value: "unknown"'))
  end

  it 'reads file with short form (no authority)' do
    content = Aspera::UriReader.read("file:#{__FILE__}")
    expect(content).to(include('frozen_string_literal'))
  end

  it 'reads file with short absolute form' do
    content = Aspera::UriReader.read("file:#{File.expand_path(__FILE__)}")
    expect(content).to(include('frozen_string_literal'))
  end

  it 'resolves path from short file uri via read_as_file' do
    path = Aspera::UriReader.read_as_file("file:#{__FILE__}")
    expect(path).to(eq(__FILE__))
  end

  it 'decodes data scheme' do
    expect(Aspera::UriReader.read('data:text/plain;base64,SGVsbG8gd29ybGQh')).to(eq('Hello world!'))
  end

  describe '.read_first' do
    let(:urls) { %w[https://first.example/doc https://second.example/doc] }

    before do
      allow(Aspera::UriReader).to(receive(:read_fail_fast).with(urls.first).and_raise(StandardError, 'unreachable'))
      allow(Aspera::UriReader).to(receive(:read).with(urls.last).and_return('last content'))
    end

    it 'uses the next URL on read error' do
      expect(Aspera::UriReader.read_first(urls)).to(eq('last content'))
      expect(Aspera::UriReader).to(have_received(:read_fail_fast).with(urls.first))
    end

    it 'uses the next URL when validation fails' do
      allow(Aspera::UriReader).to(receive(:read_fail_fast).with(urls.first).and_return('<html>'))
      result = Aspera::UriReader.read_first(urls) do |content|
        raise 'invalid' if content.start_with?('<')
        content.upcase
      end
      expect(result).to(eq('LAST CONTENT'))
    end

    it 'does not read further URLs when the first is valid' do
      allow(Aspera::UriReader).to(receive(:read_fail_fast).with(urls.first).and_return('first content'))
      expect(Aspera::UriReader.read_first(urls)).to(eq('first content'))
      expect(Aspera::UriReader).not_to(have_received(:read).with(urls.last))
    end

    it 'raises the failure of the last URL' do
      allow(Aspera::UriReader).to(receive(:read).with(urls.last).and_raise(StandardError, 'down'))
      expect { Aspera::UriReader.read_first(urls) }.to(raise_error(StandardError, 'down'))
    end
  end
end
