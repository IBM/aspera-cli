# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/string_ext'
require 'bundler/setup'

RSpec.describe(String) do
  it 'converts capitalized to snake' do
    expect('BonjourLaBelgique'.capital_to_snake).to(eq('bonjour_la_belgique'))
  end

  it 'converts snake to capitalized' do
    expect('bonjour_la_france'.snake_to_capital).to(eq('BonjourLaFrance'))
  end
end
