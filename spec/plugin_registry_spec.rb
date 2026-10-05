# frozen_string_literal: true

# Validates that the CommandRegistry of each plugin is internally consistent:
# every leaf command has either an explicit action or a matching action_* method,
# and every action accepts any keyword (the dispatch context), see `CommandRegistry#validate!`.
# Also checks that the test command displayed by the wizard of each plugin exists.
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

      # The wizard displays a test command: `<plugin> <test_args>`
      plugins.select { |plugin| plugin.method_defined?(:wizard) && plugin.instance_method(:wizard).owner.eql?(plugin) }.each do |plugin|
        it "#{plugin.name.split('::').last}: wizard test_args designate a command" do
          source = File.read(plugin.instance_method(:wizard).source_location.first)
          test_args = source.scan(/test_args:\s*'([^']*)'/).flatten
          expect(test_args).not_to(be_empty)
          test_args.each do |args|
            path, unknown = plugin.command_registry.command_path(args.split.map(&:to_sym))
            expect(unknown).to(be_nil, "#{args}: unknown word #{unknown}")
            expect(plugin.command_registry.children_of(path)).to(be_empty, "#{args}: not a leaf command")
          end
        end
      end
    end
  end
end
