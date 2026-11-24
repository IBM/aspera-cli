# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `console`: commands.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'

module Aspera
  module Plugins
    module Console
      RSpec.describe('Bundle console') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin console, from the bundle' do
            expect(registry.unavailable_reason(:console)).to(be_nil)
            expect(registry[:console].depends).to(eq([]))
            expect(registry[:console].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:console)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:console)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('console'))
          end
        end

        describe 'API schema' do
          it 'is the vendor schema of the bundle (downloaded), not in LOCATIONS' do
            schema = registry.schema(:console)
            expect(schema).not_to(be_nil)
            expect(schema.key).to(eq(:console))
            expect(schema.owned).to(be(false))
            expect(schema.source['url']).to(end_with('-enhanced.yaml'))
            expect(schema.file).to(eq(File.join(bundle_folder, 'schemas', 'IBM Aspera Console-enhanced.yaml')))
            expect(Schema::Registry.known?(:console)).to(be(true))
            expect(Schema::Registry.owned?('console')).to(be(false))
            expect(Schema::Registry::LOCATIONS).not_to(include(:console))
          end
        end
      end
    end
  end
end
