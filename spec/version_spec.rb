# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/cli/version'

RSpec.describe(Aspera::Cli) do
  it 'has a valid version string' do
    version = Aspera::Cli::VERSION
    expect(version).to(be_a(String))
    expect(Gem::Version.correct?(version)).to(be(true))
  end
end
