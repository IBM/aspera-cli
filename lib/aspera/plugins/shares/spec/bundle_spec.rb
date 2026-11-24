# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `shares`: commands, SAML token creator, Shares API schema, mount of the Node commands.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'

module Aspera
  module Plugins
    module Shares
      RSpec.describe('Bundle shares') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin shares, from the bundle' do
            expect(registry.unavailable_reason(:shares)).to(be_nil)
            expect(registry[:shares].depends).to(eq([:node]))
            expect(registry[:shares].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:shares)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:shares)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('shares'))
          end

          it 'mount the Node commands on the files of Shares' do
            expect(Commands.command_registry.mount_of([:files])).to(have_attributes(plugin: Node::Commands, only: Node::Commands::COMMANDS_SHARES))
          end
        end

        describe 'schemas' do
          it 'give the Shares API (downloaded, vendor), no longer in the framework' do
            api = registry.schema(:shares)
            expect(api).to(have_attributes(bundle: :shares, file: File.join(bundle_folder, 'schemas/IBM_Aspera_Shares.yaml'), owned: false))
            expect(api.source['url']).to(end_with('/openapi/IBM_Aspera_Shares.yaml'))
            expect(Schema::Registry::LOCATIONS).not_to(include(:shares))
            expect(Schema::Registry.req_body(Commands::API_SCHEMA, 'data/shares.post')).to(eq('shares:paths./api/v1/data/shares.post.requestBody.content.application/json.schema'))
            expect(Schema::Registry.instance.reader(Schema::Registry.req_body(Commands::API_SCHEMA, 'data/shares.post')).current).to(be_a(Hash))
          end
        end

        describe 'token creator' do
          it 'is registered under the grant method named after its class' do
            expect(OAuth::Factory.class_to_id(SharesWeb)).to(eq(:shares_web))
            expect(OAuth::Factory.instance.instance_variable_get(:@token_type_classes)[:shares_web]).to(be(SharesWeb))
          end
        end
      end
    end
  end
end
