# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `alee`: commands, API.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'

module Aspera
  module Plugins
    module Alee
      RSpec.describe('Bundle alee') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin alee, from the bundle' do
            expect(registry.unavailable_reason(:alee)).to(be_nil)
            expect(registry[:alee].depends).to(eq([]))
            expect(registry[:alee].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:alee)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:alee)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('alee'))
          end
        end

        describe 'API' do
          it 'is a REST client of the ALEE service' do
            expect(Api.superclass).to(be(Aspera::Rest::Client))
            expect(Api::SAAS_DOMAIN_PROD).to(eq('ibmaspera.com'))
          end
        end
      end
    end
  end
end
