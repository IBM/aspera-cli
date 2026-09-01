# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/rest'

RSpec.describe(Aspera::Rest) do
  it 'build URI' do
    expect(Aspera::Rest.build_uri('https://locahost', 'q=e&p=1').to_s).to(eq('https://locahost?q=e&p=1'))
  end

  it 'parses php query' do
    expect(Aspera::Rest.query_to_h('q[]=1&q[]=2')).to(eq({'q' => %w[1 2]}))
    expect(Aspera::Rest.query_to_h('q=1&q=2')).to(eq({'q' => %w[1 2]}))
  end

  it 'parses header' do
    expect(Aspera::Rest.parse_header('application/json; charset=utf-8; version="1.0"')).to(eq({type: 'application/json', parameters: {charset: 'utf-8', version: '1.0'}}))
  end
end
