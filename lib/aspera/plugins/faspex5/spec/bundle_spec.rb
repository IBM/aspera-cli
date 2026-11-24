# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `faspex5`: commands, API, public link token creator, Faspex 4 post-processing servlet, Faspex 5 API schema.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'
require_relative '../faspex4_post_proc_servlet'

module Aspera
  module Plugins
    module Faspex5
      RSpec.describe('Bundle faspex5') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin faspex5, from the bundle' do
            expect(registry.unavailable_reason(:faspex5)).to(be_nil)
            expect(registry[:faspex5].depends).to(eq(%i[xfer faspex4]))
            expect(registry[:faspex5].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:faspex5)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:faspex5)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('faspex5'))
          end

          it 'have the gateway (servlet of the bundle faspex4, shared with aoc) and the post-processing (servlet of the bundle)' do
            expect(Commands.command_registry[%i[gateway]]).not_to(be_nil)
            expect(Commands.command_registry[%i[postprocessing]]).not_to(be_nil)
            expect(Faspex4PostProcServlet.name).to(eq('Aspera::Plugins::Faspex5::Faspex4PostProcServlet'))
          end

          it 'are independent of the bundle aoc (neither depends on the other)' do
            expect(registry[:faspex5].depends).not_to(include(:aoc))
            expect(registry[:aoc].depends).not_to(include(:faspex5))
          end
        end

        describe 'schemas' do
          it 'give the Faspex 5 API (downloaded, vendor), no longer in the framework' do
            api = registry.schema(:faspex)
            expect(api).to(have_attributes(bundle: :faspex5, file: File.join(bundle_folder, 'schemas/IBM Aspera Faspex API-5.0-enhanced.yaml'), owned: false))
            expect(api.source['url']).to(end_with('/openapi/IBM%20Aspera%20Faspex%20API-5.0-enhanced.yaml'))
            expect(Schema::Registry::LOCATIONS).not_to(include(:faspex))
            expect(Schema::Registry.req_body(Commands::API_SCHEMA, 'packages.post')).to(eq('faspex:paths./packages.post.requestBody.content.application/json.schema'))
            expect(Schema::Registry.instance.reader(Schema::Registry.req_body(Commands::API_SCHEMA, 'packages.post')).current).to(be_a(Hash))
          end

          it 'give the options of the Faspex 4 servlets: post-processing in the bundle, gateway in the bundle faspex4' do
            expect(registry.schema(:faspex5_opts)).to(have_attributes(bundle: :faspex5, file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            expect(Schema::Registry.instance.reader(Commands::POSTPROC_OPTIONS).current).to(be_a(Hash))
            expect(Schema::Registry.instance.reader(Faspex4::GatewayOptions::SCHEMA).current).to(be_a(Hash))
            expect(Schema::Registry.instance.reader(Commands::POSTPROC_OPTIONS)['allOf'].first).to(eq(Schema::Registry.instance.reader(Schema::Registry::WEB_SERVER_OPTIONS).current))
          end
        end

        describe 'public link token creator' do
          it 'is registered under the grant method named after its class' do
            expect(OAuth::Factory.class_to_id(FaspexPubLink)).to(eq(:faspex_pub_link))
            expect(OAuth::Factory.instance.instance_variable_get(:@token_type_classes)[:faspex_pub_link]).to(be(FaspexPubLink))
          end
        end
      end
    end
  end
end
