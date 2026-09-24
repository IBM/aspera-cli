# frozen_string_literal: true

# Validates that the CommandRegistry of each plugin is internally consistent:
# every leaf command has either an explicit action or a matching action_* method,
# and every action accepts any keyword (the dispatch context).
# This spec does NOT require spec_helper (no live server config needed).

require 'bundler/setup'
require 'aspera/cli/runner'
Dir[File.join(__dir__, '../lib/aspera/cli/plugins/*.rb')].each { |f| require f }

module Aspera
  module Cli
    RSpec.describe(Plugins::Base) do
      plugins = ObjectSpace.each_object(Class).select { |c| c < described_class && c.command_registry.any? }.sort_by(&:name)

      it 'finds plugins with commands' do
        expect(plugins).to(include(Plugins::Aoc, Plugins::Node, Plugins::Config))
      end

      plugins.each do |plugin|
        it "#{plugin.name.split('::').last}: passes validate! with plugin_class" do
          expect { plugin.command_registry.validate!(plugin_class: plugin) }.not_to(raise_error)
        end
      end
    end
  end
end
