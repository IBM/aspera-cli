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

  it 'fails on bad file uri' do
    Aspera::UriReader.read_as_file('file:foo.bar')
    raise 'Shall not reach here'
  rescue => e
    expect(e.message).to(include('use format: file:///'))
  end

  it 'decodes data scheme' do
    expect(Aspera::UriReader.read('data:text/plain;base64,SGVsbG8gd29ybGQh')).to(eq('Hello world!'))
  end
end
