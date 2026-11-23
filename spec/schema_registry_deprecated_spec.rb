# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/schema/registry'
require_relative '../lib/aspera/plugins/aoc/commands'
require_relative '../lib/aspera/plugins/console/commands'
require_relative '../lib/aspera/plugins/faspex5/commands'
require_relative '../lib/aspera/plugins/faspio/commands'
require_relative '../lib/aspera/plugins/node/commands'
require_relative '../lib/aspera/plugins/orchestrator/commands'
require_relative '../lib/aspera/plugins/shares/commands'
require_relative '../lib/aspera/plugins/transferd/service'

# Constants of released versions, moved to the bundles: kept until 5.0
RSpec.describe(Aspera::Schema::Registry) do
  plugins = Aspera::Plugins
  {
    AOC:                      plugins::Aoc::Commands::AOC_SCHEMA,
    AUTOMATION:               plugins::Aoc::Commands::AUTOMATION_SCHEMA,
    CONSOLE:                  plugins::Console::Commands::API_SCHEMA,
    FASPEX:                   plugins::Faspex5::Commands::API_SCHEMA,
    FASPIO:                   plugins::Faspio::Commands::API_SCHEMA,
    NODE:                     plugins::Node::Commands::API_SCHEMA,
    ORCHESTRATOR:             plugins::Orchestrator::Commands::API_SCHEMA,
    SHARES:                   plugins::Shares::Commands::API_SCHEMA,
    PREVIEW_OPTIONS:          'preview',
    TRANSFERD_AGENT_OPTIONS:  'opts:components.schemas.TransferdAgentOptions',
    TRANSFERD_SERVICE_CONFIG: plugins::Transferd::Service::SERVICE_CONFIG
  }.each do |old_name, new_value|
    describe "constant #{old_name}" do
      it 'has the value of its new name' do
        expect(described_class.const_get(old_name)).to(eq(new_value))
      end

      it 'resolves the same schema' do
        # the component `shares+/api/v1` has a path prefix: the registry key is before `+`
        old = described_class.instance.reader(described_class.const_get(old_name).split('+', 2).first).current
        expect(old).not_to(be_nil)
        expect(old).to(eq(described_class.instance.reader(new_value.split('+', 2).first).current))
      end

      it 'warns that it is deprecated' do
        previous = [Warning[:deprecated], $VERBOSE]
        # `$VERBOSE` is nil when libraries are loaded: it silences all warnings
        Warning[:deprecated] = true
        $VERBOSE = false
        begin
          expect { described_class.const_get(old_name) }.to(output(/constant .*#{old_name} is deprecated/).to_stderr)
        ensure
          Warning[:deprecated], $VERBOSE = previous
        end
      end
    end
  end
end
