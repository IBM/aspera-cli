# frozen_string_literal: true

require 'spec_helper'
require 'aspera/sync/operations'

RSpec.describe(Aspera::Sync::Operations) do
  # `conf` format: `local` at top level, `args` format: `sessions` list
  let(:conf_db)    { {'name' => 's1', 'local' => {'path' => '/l'}, 'local_db_dir' => '/db'} }
  let(:conf_local) { {'name' => 's1', 'local' => {'path' => '/l'}} }
  let(:conf_none)  { {'name' => 's1', 'local' => {}} }
  let(:args_db)    { {'sessions' => [{'name' => 's2', 'local_dir' => '/l', 'local_db_dir' => '/db'}]} }
  let(:args_local) { {'sessions' => [{'name' => 's2', 'local_dir' => '/l'}]} }
  let(:args_none)  { {'sessions' => [{'name' => 's2'}]} }

  describe '.local_db_folder' do
    it 'prefers local_db_dir, then local folder' do
      expect(described_class.local_db_folder(conf_db)).to(eq('/db'))
      expect(described_class.local_db_folder(conf_local)).to(eq('/l'))
      expect(described_class.local_db_folder(args_db)).to(eq('/db'))
      expect(described_class.local_db_folder(args_local)).to(eq('/l'))
    end

    it 'fails without any local folder' do
      expect { described_class.local_db_folder(conf_none) }.to(raise_error(Aspera::Error, /local.path/))
      expect { described_class.local_db_folder(args_none) }.to(raise_error(Aspera::Error, /local_dir/))
      expect { described_class.local_db_folder({}) }.to(raise_error(Aspera::Error, /must be present/))
    end
  end

  describe '.session_name' do
    it 'reads name in both formats' do
      expect(described_class.session_name(conf_local)).to(eq('s1'))
      expect(described_class.session_name(args_local)).to(eq('s2'))
    end
  end

  describe '.admin_status' do
    def admin_args(sync_info)
      captured = nil
      allow(Aspera::Environment).to(receive(:secure_execute)) do |*args, **|
        captured = args
        ['']
      end
      described_class.admin_status(sync_info)
      captured
    end

    it 'passes database folder or local folder to asyncadmin' do
      expect(admin_args(conf_db)).to(eq(%w[asyncadmin --quiet --name=s1 --local-db-dir=/db]))
      expect(admin_args(conf_local)).to(eq(%w[asyncadmin --quiet --name=s1 --local-dir=/l]))
      expect(admin_args(args_db)).to(eq(%w[asyncadmin --quiet --name=s2 --local-db-dir=/db]))
      expect(admin_args(args_local)).to(eq(%w[asyncadmin --quiet --name=s2 --local-dir=/l]))
    end

    it 'fails without any local folder' do
      expect { described_class.admin_status(conf_none) }.to(raise_error(Aspera::Error, /local.path/))
      expect { described_class.admin_status(args_none) }.to(raise_error(Aspera::Error, /local_dir/))
    end
  end

  describe '.remote_certificates' do
    it 'removes SSH parameters for web socket sessions' do
      remote = {'connect_mode' => 'ws', 'port' => 33001, 'fingerprint' => 'x', 'ws_port' => 443}
      expect(described_class.remote_certificates(remote)).to(eq([]))
      expect(remote).to(eq({'connect_mode' => 'ws', 'ws_port' => 443}))
    end
  end

  describe '.args_to_conf' do
    it 'converts preserve time and scp-like remote' do
      expect(described_class.args_to_conf(%w[-t --name=s1 -r user@host:/path])).to(eq({
        'preserve_modification_time' => true,
        'name'                       => 's1',
        'remote'                     => {'path' => '/path', 'user' => 'user', 'host' => 'host'}
      }))
    end
  end
end
