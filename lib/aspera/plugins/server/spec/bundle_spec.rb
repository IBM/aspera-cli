# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `server`: commands, `ascmd`.

require 'spec_helper'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../commands'

module Aspera
  module Plugins
    module Server
      RSpec.describe('Bundle server') do
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin server, from the bundle' do
            expect(registry.unavailable_reason(:server)).to(be_nil)
            expect(registry[:server].depends).to(eq([:xfer]))
            expect(registry[:server].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:server)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:server)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('server'))
          end

          it 'use the ascmd of the bundle' do
            expect(AsCmd::OPERATIONS).to(include(:ls, :rm, :cp))
            expect(AsCmd::Error.superclass).to(be(StandardError))
          end
        end
      end
    end
  end
end
