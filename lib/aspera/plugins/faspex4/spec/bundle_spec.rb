# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `faspex4`: gateway that emulates the Faspex 4 API, and its options schema, used by the bundles aoc and faspex5.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../../aoc/commands'
require_relative '../../faspex5/commands'

module Aspera
  module Plugins
    module Faspex4
      RSpec.describe('Bundle faspex4') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        it 'is a library of the bundles aoc and faspex5: no command, no dependency' do
          expect(registry.unavailable_reason(:faspex4)).to(be_nil)
          expect(registry[:faspex4]).to(have_attributes(form: :bundle, path: bundle_folder))
          expect(registry[:faspex4].commands?).to(be(false))
          expect(registry[:faspex4].depends).to(eq([]))
          expect(Cli::Plugins::Factory.instance.plugin_list).not_to(include(:faspex4))
        end

        it 'is used by the bundles aoc and faspex5, which do not depend on each other' do
          expect(registry[:aoc].depends).to(include(:faspex4))
          expect(registry[:faspex5].depends).to(include(:faspex4))
          expect(registry[:aoc].depends).not_to(include(:faspex5))
          expect(registry[:faspex5].depends).not_to(include(:aoc))
          expect(Aoc::Commands.command_registry[%i[gateway]].arguments.first.schema).to(eq(Aoc::Commands::GATEWAY_OPTIONS))
          expect(Faspex5::Commands.command_registry[%i[gateway]].arguments.first.schema).to(eq(Aoc::Commands::GATEWAY_OPTIONS))
        end

        describe 'options of the gateway' do
          let(:schema_path) { Aoc::Commands::GATEWAY_OPTIONS }

          it 'are an owned schema of the bundle, no longer in the framework' do
            expect(registry.schema(:faspex4_opts)).to(have_attributes(bundle: :faspex4, file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            expect(Schema::Registry.owned?(schema_path)).to(be(true))
            framework = Schema::Registry.instance.reader(Schema::Registry::OPTIONS)['components']['schemas']
            expect(framework.keys).not_to(include('Faspex4GatewayOptions', 'Faspex4PostProcOptions'))
          end

          it 'include a copy of the options of the web server of the framework' do
            branches = Schema::Registry.instance.reader(schema_path)['allOf']
            web_server = Schema::Registry.instance.reader(Schema::Registry::WEB_SERVER_OPTIONS).current
            expect(branches.first).to(eq(web_server))
            expect(branches.first).not_to(be(web_server))
          end

          it 'are validated, with the properties of the web server' do
            validator = Schema::Validator.instance
            expect(validator.errors({'url' => 'http://localhost:9080', 'username' => 'fx4_user'}, schema_path)).to(eq([]))
            expect(validator.errors({'port' => 9080}, schema_path)).not_to(be_empty)
          end
        end
      end
    end
  end
end
