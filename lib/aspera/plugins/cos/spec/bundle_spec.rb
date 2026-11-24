# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `cos`: commands, API, mount of the Node commands.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../commands'

module Aspera
  module Plugins
    module Cos
      RSpec.describe('Bundle cos') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin cos, from the bundle' do
            expect(registry.unavailable_reason(:cos)).to(be_nil)
            expect(registry[:cos].depends).to(eq([:node]))
            expect(registry[:cos].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:cos)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:cos)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('cos'))
          end

          it 'mount the Node commands on the COS bucket' do
            expect(Commands.command_registry.mount_of([:node])).to(have_attributes(plugin: Node::Commands, only: Node::Commands::COMMANDS_COS))
          end
        end

        describe 'API' do
          it 'is a Node API' do
            expect(Api.superclass).to(be(Node::Api))
          end
        end
      end
    end
  end
end
