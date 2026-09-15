# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/uri_reader'

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
end
