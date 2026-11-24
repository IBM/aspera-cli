# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `preview`: commands, generator, schema of the options.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'

module Aspera
  module Plugins
    module Preview
      RSpec.describe('Bundle preview') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin preview, from the bundle' do
            expect(registry.unavailable_reason(:preview)).to(be_nil)
            expect(registry[:preview].depends).to(eq(%i[node transfer_agents]))
            expect(registry[:preview].gems).to(eq(['marcel']))
            expect(Cli::Plugins::Factory.instance.plugin_source(:preview)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:preview)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('preview'))
          end
        end

        describe 'schemas' do
          it 'give the options of the generator, owned by ascli, no longer in the framework' do
            expect(registry.schema(:preview)).to(have_attributes(bundle: :preview, file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            expect(Schema::Registry::LOCATIONS).not_to(include(:preview))
            expect(Schema::Registry.owned?(Generator::OPTIONS_SCHEMA)).to(be(true))
            expect(Generator::Options.members).to(include(:office_conversion, :video_conversion))
          end

          it 'keep the error images next to the generator' do
            %w[image_error.png video_error.png].each { |name| expect(File.exist?(File.join(bundle_folder, name))).to(be(true), name) }
          end
        end
      end
    end
  end
end
