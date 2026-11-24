# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `ats`: commands, API, mount of the Node commands.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'

module Aspera
  module Plugins
    module Ats
      RSpec.describe('Bundle ats') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin ats, from the bundle' do
            expect(registry.unavailable_reason(:ats)).to(be_nil)
            expect(registry[:ats].depends).to(eq(%i[node alee]))
            expect(registry[:ats].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:ats)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:ats)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('ats'))
          end

          it 'mount the Node commands on the access keys' do
            expect(Commands.command_registry.mount_of(%i[access_key node])).to(have_attributes(plugin: Node::Commands))
          end
        end

        describe 'API' do
          it 'is a REST client of the public ATS service' do
            expect(Api.superclass).to(be(Rest::Client))
            expect(Api::SERVICE_BASE_URL).to(eq('https://ats.aspera.io'))
          end
        end
      end
    end
  end
end
