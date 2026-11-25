# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Xfer::SyncActions: the database read by `sync admin` is checked against the security level — no async needed.

require_relative '../../../cli/security'
require_relative '../sync_actions'
require 'fileutils'
require 'tmpdir'

module Aspera
  module Cli
    RSpec.describe(Aspera::Plugins::Xfer::SyncActions) do
      subject(:host) do
        Class.new do
          class << self
            # DSL of the plugin class that includes the mixin: not used here
            def option(*, **); end
          end
          include Aspera::Plugins::Xfer::SyncActions

          public :admin_sync_info, :readable_db_files
        end.new
      end

      let(:security) { Security.instance }
      # Real path: on macOS, the temporary folder is behind a symbolic link (/var -> /private/var)
      let(:folder) { File.realpath(Dir.mktmpdir('sync_actions_spec')) }
      let(:allowed) { File.join(folder, 'allowed').tap { |path| Dir.mkdir(path) } }
      let(:outside) { File.join(folder, 'outside').tap { |path| Dir.mkdir(path) } }

      # @param local_db_dir [String] folder of the databases
      # @param name         [String] name of the session
      # @return [String] database file of the session, created
      def make_db(local_db_dir, name)
        session = File.join(local_db_dir, Sync::Operations.const_get(:PRIVATE_FOLDER), name).tap { |path| FileUtils.mkdir_p(path) }
        File.join(session, 'snap.db').tap { |path| File.write(path, '') }
      end

      before do
        make_db(allowed, 'in')
        make_db(outside, 'out')
        security.options = {'level' => 'medium', 'allowed_paths' => [allowed]}
      end

      after do
        security.reset
        FileUtils.rm_rf(folder)
      end

      it 'reads the database of a session in the folder given as argument' do
        expect(host.admin_sync_info(path: allowed, sync_info: {'name' => 'in'})['local']['path']).to(eq(allowed))
        expect(host.readable_db_files(allowed).keys).to(eq(['in']))
      end

      it 'refuses a database folder given by sync_info outside of allowed paths' do
        expect { host.admin_sync_info(path: allowed, sync_info: {'name' => 'out', 'local_db_dir' => outside}) }
          .to(raise_error(BadArgument, /no such file in security.allowed_paths/))
        expect { host.admin_sync_info(path: allowed, sync_info: {'sessions' => [{'name' => 'out', 'local_db_dir' => outside}]}) }
          .to(raise_error(BadArgument, /no such file in security.allowed_paths/))
      end

      it 'refuses a session name that leads outside of allowed paths' do
        name = File.join('..', '..', 'outside', Sync::Operations.const_get(:PRIVATE_FOLDER), 'out')
        expect(File.exist?(File.join(allowed, Sync::Operations.const_get(:PRIVATE_FOLDER), name, 'snap.db'))).to(be(true))
        expect { host.admin_sync_info(path: allowed, sync_info: {'name' => name}) }
          .to(raise_error(BadArgument, /no such file in security.allowed_paths/))
      end

      it 'skips a session whose folder is a symbolic link outside of allowed paths' do
        File.symlink(File.dirname(make_db(outside, 'other')), File.join(allowed, Sync::Operations.const_get(:PRIVATE_FOLDER), 'linked'))
        expect(host.readable_db_files(allowed).keys).to(eq(['in']))
        expect { host.admin_sync_info(path: allowed, sync_info: {'name' => 'linked'}) }.to(raise_error(BadArgument, /no such file in security.allowed_paths/))
      end
    end
  end
end
