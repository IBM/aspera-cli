# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Command `transferd install`: nothing is done if the version is already installed

require 'spec_helper'
require_relative '../lib/aspera/cli/runner'
require_relative '../lib/aspera/cli/plugins/transferd'
require 'tmpdir'
require 'fileutils'

module Aspera
  module Cli
    RSpec.describe(Plugins::Transferd) do
      let(:installation) { Ascp::Installation.instance }
      let(:plugin) { described_class.allocate }
      let(:sdk_url) { nil }

      around do |example|
        Dir.mktmpdir do |dir|
          @sdk_dir = dir
          previous = Products::Transferd.instance_variable_get(:@sdk_dir)
          Products::Transferd.sdk_directory = dir
          example.run
        ensure
          Products::Transferd.instance_variable_set(:@sdk_dir, previous)
        end
      end

      before do
        allow(plugin).to(receive(:sdk_url_option).and_return(sdk_url))
        allow(installation).to(receive(:sdk_location_for_platform)) { |version:, **| {'version' => version || '2.0.0'} }
        allow(installation).to(receive(:install_sdk).and_return(['IBM Aspera Transfer SDK', '1.1.9', @sdk_dir]))
      end

      describe 'action_install' do
        it 'does not install if the version is already installed' do
          allow(installation).to(receive(:installed_sdk_version).and_return('1.1.9'))
          result = plugin.action_install(version: '1.1.9')
          expect(installation).not_to(have_received(:install_sdk))
          expect(result.instance_variable_get(:@data)).to(eq("Version 1.1.9 is already installed in #{@sdk_dir}"))
        end

        it 'installs if another version is installed' do
          allow(installation).to(receive(:installed_sdk_version).and_return('1.1.3'))
          plugin.action_install(version: '1.1.9')
          expect(installation).to(have_received(:install_sdk).with(url: nil, version: '1.1.9'))
        end

        it 'installs if nothing is installed' do
          allow(installation).to(receive(:installed_sdk_version).and_return(nil))
          plugin.action_install(version: '1.1.9')
          expect(installation).to(have_received(:install_sdk))
        end

        it 'uses the default version without argument' do
          allow(installation).to(receive(:installed_sdk_version).and_return(Info::SDK_VERSION))
          plugin.action_install
          expect(installation).not_to(have_received(:install_sdk))
        end

        it 'compares with the latest version for LATEST' do
          allow(installation).to(receive(:installed_sdk_version).and_return('2.0.0'))
          plugin.action_install(version: SpecialValues::LATEST)
          expect(installation).not_to(have_received(:install_sdk))
        end

        context 'with an explicit URL' do
          let(:sdk_url) { 'file:///sdk.tar.gz' }

          it 'always installs' do
            allow(installation).to(receive(:installed_sdk_version).and_return('1.1.9'))
            plugin.action_install(version: '1.1.9')
            expect(installation).to(have_received(:install_sdk).with(url: sdk_url, version: '1.1.9'))
          end
        end
      end
    end

    RSpec.describe(Ascp::Installation) do
      describe 'installed_sdk_version' do
        around do |example|
          Dir.mktmpdir do |dir|
            @sdk_dir = dir
            previous = Products::Transferd.instance_variable_get(:@sdk_dir)
            Products::Transferd.sdk_directory = dir
            example.run
          ensure
            Products::Transferd.instance_variable_set(:@sdk_dir, previous)
          end
        end

        def write_meta(version)
          File.write(File.join(@sdk_dir, Products::Other::INFO_META_FILE), "<product><name>SDK</name><version>#{version}</version></product>")
        end

        it 'is nil if transferd is not installed' do
          write_meta('1.1.9')
          expect(described_class.instance.installed_sdk_version).to(be_nil)
        end

        it 'is nil without meta data file' do
          FileUtils.touch(Products::Transferd.transferd_path)
          expect(described_class.instance.installed_sdk_version).to(be_nil)
        end

        it 'is the version of the meta data file' do
          FileUtils.touch(Products::Transferd.transferd_path)
          write_meta('1.1.9')
          expect(described_class.instance.installed_sdk_version).to(eq('1.1.9'))
        end
      end
    end
  end
end
