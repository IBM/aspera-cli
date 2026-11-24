# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `faspex5`: commands, API, public link token creator, Faspex 4 post-processing servlet, Faspex 5 API schema, shims of the moved files.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'
require_relative '../faspex4_post_proc_servlet'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Faspex5
      RSpec.describe('Bundle faspex5') do
        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        # @param script [String] Ruby code run in another process: the former constants are not defined in the process of the specs
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def run_ruby(script)
          Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
        end

        describe 'commands' do
          it 'are those of plugin faspex5, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:faspex5)).to(be_nil)
            expect(registry[:faspex5].depends).to(eq(%i[transfer_agents faspex4]))
            expect(registry[:faspex5].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:faspex5)).to(eq(bundle_folder))
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
            expect(Schema::Registry.instance.reader(Commands::GATEWAY_OPTIONS).current).to(be_a(Hash))
            expect(Schema::Registry.instance.reader(Commands::POSTPROC_OPTIONS)['allOf'].first).to(eq(Schema::Registry.instance.reader(Schema::Registry::WEB_SERVER_OPTIONS).current))
          end
        end

        describe 'public link token creator' do
          it 'is registered under the grant method of the former class name' do
            expect(OAuth::Factory.class_to_id(FaspexPubLink)).to(eq(:faspex_pub_link))
            expect(OAuth::Factory.instance.instance_variable_get(:@token_type_classes)[:faspex_pub_link]).to(be(FaspexPubLink))
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/faspex5' => %w[Aspera::Cli::Plugins::Faspex5 Aspera::Plugins::Faspex5::Commands aspera/plugins/faspex5/commands],
            'aspera/api/faspex'          => %w[Aspera::Api::Faspex Aspera::Plugins::Faspex5::Api aspera/plugins/faspex5/api],
            'aspera/faspex_postproc'     => %w[Aspera::Faspex4PostProcServlet Aspera::Plugins::Faspex5::Faspex4PostProcServlet aspera/plugins/faspex5/faspex4_post_proc_servlet]
          }.freeze

          it 'warn once when loaded, and give the moved constants under their former names' do
            MOVED.each do |path, (former, current, new_path)|
              stdout, stderr, status = run_ruby("2.times { require #{path.inspect} }\nputs Object.const_get(#{former.inspect}).name\n")
              expect(status.success?).to(be(true), stderr)
              expect(stdout.chomp).to(eq(current))
              expect(stderr.scan("#{path} is deprecated: use #{new_path} (removed in 5.0)").length).to(eq(1), stderr)
              # `-w`: warning of `deprecate_constant`, and no other warning
              expect(stderr.lines(chomp: true).grep(/warning:/)).to(eq(["-e:2: warning: constant #{former} is deprecated"]), stderr)
            end
          end

          it 'give the public link token creator under its former name' do
            stdout, stderr, status = run_ruby("require 'aspera/api/faspex'\nputs Aspera::FaspexPubLink.name\n")
            expect(status.success?).to(be(true), stderr)
            expect(stdout.chomp).to(eq('Aspera::Plugins::Faspex5::FaspexPubLink'))
            expect(stderr.lines(chomp: true).grep(/warning:/)).to(eq(['-e:2: warning: constant Aspera::FaspexPubLink is deprecated']), stderr)
          end
        end
      end
    end
  end
end
