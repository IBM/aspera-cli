# frozen_string_literal: true

# Validates that the Aoc plugin's CommandRegistry is internally consistent:
# every leaf command has either an explicit handler or a matching handle_* method.
# This spec does NOT require spec_helper (no live server config needed).

require 'bundler/setup'
require 'aspera/cli/plugins/aoc'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Aoc) do
        describe '.command_registry' do
          it 'has at least one registered command' do
            expect(described_class.command_registry.any?).to(be(true))
          end

          it 'passes validate! with plugin_class' do
            expect do
              described_class.command_registry.validate!(plugin_class: described_class)
            end.not_to(raise_error)
          end
        end
      end
    end
  end
end
