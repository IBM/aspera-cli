# frozen_string_literal: true

require 'spec_helper'
require 'aspera/schema/validator'

RSpec.describe(Aspera::Schema::Validator) do
  subject(:validator) { described_class.instance }

  let(:agent_options) { Aspera::Schema::Registry::TRANSFER_AGENT_OPTIONS }
  let(:workflow_start) { 'opts:components.schemas.OrchestratorWorkflowStart' }

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
    telemetry = 'opts:components.schemas.NodeTelemetryOptions'
    expect(validator.errors({}, telemetry).first).to(include('required'))
    expect(validator.errors({}, telemetry, partial: true)).to(be_empty)
  end

  it 'accepts symbol keys and values' do
    expect(validator.errors({agent: :node, url: 'https://x'}, agent_options, partial: true)).to(be_empty)
  end

  it 'reports unknown discriminator value' do
    expect(validator.errors({'agent' => 'bogus'}, agent_options, partial: true).first).to(start_with('value at `/agent` is not one of:'))
  end

  it 'ignores missing discriminator in partial value' do
    expect(validator.errors({'multi_session' => 2}, agent_options, partial: true)).to(be_empty)
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
