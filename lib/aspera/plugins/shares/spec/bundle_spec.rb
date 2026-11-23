# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `shares`: commands, SAML token creator, Shares API schema, mount of the Node commands, shims of the moved files.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Shares
      RSpec.describe('Bundle shares') do
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
          it 'are those of plugin shares, from the bundle (which hides the shim of the former plugin file)' do
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
          it 'is registered under the grant method of the former class name' do
            expect(OAuth::Factory.class_to_id(SharesWeb)).to(eq(:shares_web))
            expect(OAuth::Factory.instance.instance_variable_get(:@token_type_classes)[:shares_web]).to(be(SharesWeb))
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/shares'      => %w[Aspera::Cli::Plugins::Shares Aspera::Plugins::Shares::Commands aspera/plugins/shares/commands],
            'aspera/oauth/client/shares_web' => %w[Aspera::OAuth::SharesWeb Aspera::Plugins::Shares::SharesWeb aspera/plugins/shares/shares_web]
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
        end
      end
    end
  end
end
