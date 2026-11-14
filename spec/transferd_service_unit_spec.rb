# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/products/transferd_service'

RSpec.describe(Aspera::Products::TransferdService) do
  describe '.unit' do
    let(:default_unit) do
      <<~UNIT
        [Unit]
        Description=IBM Aspera Transfer Daemon
        After=network.target

        [Service]
        Type=simple
        User=asperadaemon
        ExecStart=/opt/aspera/transferd/bin/transferd --config /etc/transferd/transferd.json
        Restart=always

        [Install]
        WantedBy=multi-user.target
      UNIT
    end

    it 'generates default unit when given empty options' do
      expect(described_class.unit({})).to(eq(default_unit))
    end

    it 'generates default unit when called without arguments' do
      expect(described_class.unit).to(eq(default_unit))
    end

    it 'accepts custom executable and config_file' do
      unit = described_class.unit(
        executable:  '/opt/sdk/1.1.10/bin/transferd',
        config_file: '/etc/aspera/transferd.json'
      )
      expect(unit).to(include('ExecStart=/opt/sdk/1.1.10/bin/transferd --config /etc/aspera/transferd.json'))
    end

    it 'accepts custom user and group' do
      unit = described_class.unit(
        user:  'aspweb',
        group: 'aspweb'
      )
      expect(unit).to(include("User=aspweb\nGroup=aspweb"))
    end

    it 'omits Group when group is nil or empty' do
      unit = described_class.unit(group: nil)
      expect(unit).not_to(include('Group='))
      unit_empty = described_class.unit(group: '')
      expect(unit_empty).not_to(include('Group='))
    end

    it 'accepts custom after as an array or string' do
      unit_array = described_class.unit(after: ['network.target', 'local-fs.target'])
      expect(unit_array).to(include('After=network.target local-fs.target'))

      unit_str = described_class.unit(after: 'syslog.target')
      expect(unit_str).to(include('After=syslog.target'))
    end

    it 'includes Environment directives only when given' do
      unit_no_env = described_class.unit(environment: {})
      expect(unit_no_env).not_to(include('Environment='))

      unit_env = described_class.unit(
        environment: {
          'TRANSFERD_PORT'    => '55002',
          'TRANSFERD_ADDRESS' => '127.0.0.1'
        }
      )
      expect(unit_env).to(include(%Q(Environment="TRANSFERD_ADDRESS=127.0.0.1"\nEnvironment="TRANSFERD_PORT=55002")))
    end

    it 'handles CONFIG with nested service section and String keys' do
      config = {
        'service'     => {
          'name'        => 'aspera-transferd',
          'user'        => 'aspweb',
          'group'       => 'aspweb',
          'unit_dir'    => '/etc/systemd/system',
          'after'       => ['network.target', 'local-fs.target'],
          'environment' => {'TRANSFERD_PORT' => '55002'}
        },
        'executable'  => '/opt/aspera/transferd/bin/transferd',
        'config_file' => '/etc/transferd/transferd.json'
      }
      unit = described_class.unit(config)
      expect(unit).to(include('User=aspweb'))
      expect(unit).to(include('Group=aspweb'))
      expect(unit).to(include('After=network.target local-fs.target'))
      expect(unit).to(include('ExecStart=/opt/aspera/transferd/bin/transferd --config /etc/transferd/transferd.json'))
      expect(unit).to(include('Environment="TRANSFERD_PORT=55002"'))
    end

    it 'derives executable from sdk_folder if given' do
      unit = described_class.unit(sdk_folder: '/opt/aspera/sdk/1.1.10')
      expect(unit).to(include('ExecStart=/opt/aspera/sdk/1.1.10/bin/transferd --config /etc/transferd/transferd.json'))
    end
  end
end
