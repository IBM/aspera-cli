# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/cli/version'
require 'bundler/setup'

RSpec.describe(Aspera::Cli) do
  it 'has a valid version string' do
    version = Aspera::Cli::VERSION
    expect(version).to(be_a(String))
    expect(Gem::Version.correct?(version)).to(be(true))
  end
end
