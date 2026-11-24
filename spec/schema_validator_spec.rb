# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/schema/validator'
require_relative '../lib/aspera/plugins/xfer/transfer_agent'

RSpec.describe(Aspera::Schema::Validator) do
  subject(:validator) { described_class.instance }

  let(:agent_options) { Aspera::Plugins::Xfer::TransferAgent::TRANSFER_OPTION_SCHEMA }
  let(:workflow_start) { 'orchestrator_opts:components.schemas.OrchestratorWorkflowStart' }

  it 'accepts a valid value' do
    expect(validator.errors({'synchronous' => true, 'variable' => 'x'}, workflow_start)).to(be_empty)
  end

  it 'reports path and reason of wrong type' do
    expect(validator.errors({'synchronous' => 'yes'}, workflow_start)).to(eq(['value at `/synchronous` is not a boolean']))
  end

  it 'reports additional property' do
    expect(validator.errors({'foo' => 1}, workflow_start).first).to(include('/foo'))
  end

  it 'reports value not in enum' do
    expect(validator.errors({'direction' => 'sideways'}, Aspera::Schema::Registry::TRANSFER_SPEC, partial: true).first).to(include('/direction'))
  end

  it 'enforces required unless partial' do
    telemetry = 'node_opts:components.schemas.NodeTelemetryOptions'
    expect(validator.errors({}, telemetry).first).to(include('required'))
    expect(validator.errors({}, telemetry, partial: true)).to(be_empty)
  end

  it 'ignores null values (removal) in partial value' do
    ts = Aspera::Schema::Registry::TRANSFER_SPEC
    expect(validator.errors({'wss_enabled' => nil, 'wss_port' => nil}, ts, partial: true)).to(be_empty)
    expect(validator.errors({'wss_enabled' => nil}, ts)).not_to(be_empty)
  end

  it 'accepts symbol keys and values' do
    expect(validator.errors({agent: :node, url: 'https://x'}, agent_options, partial: true)).to(be_empty)
  end

  it 'reports unknown discriminator value' do
    expect(validator.errors({'agent' => 'bogus'}, agent_options, partial: true).first).to(start_with('value at `/agent` is not one of:'))
  end

  it 'ignores missing discriminator in partial value' do
    expect(validator.errors({'wss' => true}, agent_options, partial: true)).to(be_empty)
  end

  describe 'keys of variants (unevaluatedProperties of the selector)' do
    it 'accepts the keys of the selector and of the selected variant' do
      expect(validator.errors({'agent' => 'direct', 'wss' => true, 'asynchronous' => true}, agent_options, partial: true)).to(be_empty)
    end

    it 'refuses a key that is not of the selected variant' do
      expect(validator.errors({'agent' => 'node', 'wss' => true}, agent_options, partial: true)).to(eq(['object property at `/wss` is a disallowed additional property']))
    end

    it 'refuses an unknown key when the selector is missing in a partial value (default variant)' do
      expect(validator.errors({'spawn_timout_sec' => 5}, agent_options, partial: true)).to(eq(['object property at `/spawn_timout_sec` is a disallowed additional property']))
    end

    it 'reports only the error of the variant when its value is wrong' do
      expect(validator.errors({'agent' => 'direct', 'wss' => 'yes', 'quiet' => true}, agent_options, partial: true)).to(eq(['value at `/wss` is not a boolean']))
    end

    it 'reports only the selector when it is not valid' do
      expect(validator.errors({'agent' => 'bogus', 'wss' => true}, agent_options, partial: true).size).to(eq(1))
    end
  end

  it 'ignores null values when asked, with required enforced' do
    telemetry = 'node_opts:components.schemas.NodeTelemetryOptions'
    expect(validator.errors({'url' => 'https://x', 'key' => nil}, telemetry, ignore_null: true).first).to(include('key'))
    expect(validator.errors({'url' => 'https://x', 'key' => 'k', 'hostname' => nil}, telemetry, ignore_null: true)).to(be_empty)
  end

  it 'skips vendor API schemas' do
    expect(validator.errors({'foo' => 1}, 'node:components.schemas.transferPostRequest')).to(be_empty)
  end

  it 'compiles all owned schema paths used by options' do
    Aspera::Schema::Registry.constants.map { |c| Aspera::Schema::Registry.const_get(c) }
      .select { |v| v.is_a?(String) && v.include?(':') && Aspera::Schema::Registry.owned?(v) }
      .each { |path| expect { validator.errors({}, path, partial: true) }.not_to(raise_error) }
  end
end
