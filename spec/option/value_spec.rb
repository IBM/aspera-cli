# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../../lib/aspera/cli/option/value'

RSpec.describe(Aspera::Cli::Option::Value) do
  def hash_option(name = :opt, **)
    described_class.new(option: name, allowed: [Hash], **)
  end

  describe '#assign_value' do
    it 'merges a value of a lower source under a value set by code' do
      option = hash_option(:table_style)
      option.assign_value({'a' => 1}, source: :code)
      option.assign_value({'a' => 2, 'b' => 3}, source: :preset)
      expect(option.value).to(eq({'a' => 1, 'b' => 3}))
    end

    it 'ignores a value of a lower source when the value is final, also a container' do
      option = hash_option(:vault)
      option.assign_value({'a' => 1}, source: :code, final: true)
      %i[preset plugin_preset env].each { |source| option.assign_value({'b' => 2}, source: source) }
      expect(option.value).to(eq({'a' => 1}))
    end

    it 'does not check the security level of the value of a lower source when the value is final' do
      Aspera::Cli::Security.instance.lock('spec', default: :high)
      option = hash_option(:vault, security: :low)
      option.assign_value({'a' => 1}, source: :code, final: true)
      expect { option.assign_value({'b' => 2}, source: :preset) }.not_to(raise_error)
      expect { option.assign_value({'b' => 2}, source: :cmdline) }.to(raise_error(Aspera::Cli::BadArgument, /option vault: disabled by security level high/))
      expect(option.value).to(eq({'a' => 1}))
    ensure
      Aspera::Cli::Security.instance.reset
    end

    # The configuration is read-only for a client at levels `medium` and `high`: the values of a preset read from it are the ones of the operator
    it 'checks the security level of a preset given by the client, not of a preset read from the configuration' do
      Aspera::Cli::Security.instance.options = {'level' => 'high'}
      expect { hash_option(:vault, security: :low).assign_value({'a' => 1}, source: :preset) }.to(raise_error(Aspera::Cli::BadArgument, /option vault: disabled by security level high/))
      %i[preset plugin_preset].each do |source|
        option = hash_option(:vault, security: :low)
        expect { option.assign_value({'a' => 1}, source: source, configured: true) }.not_to(raise_error)
        expect(option.value).to(eq({'a' => 1}))
      end
    ensure
      Aspera::Cli::Security.instance.reset
    end
  end
end
