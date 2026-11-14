# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/products/transferd_service'
require_relative '../lib/aspera/schema/validator'

RSpec.describe(Aspera::Products::TransferdService) do
  let(:sdk) { '/opt/sdk/1.1.10' }
  let(:file) { '/etc/transferd/transferd.json' }

  def config(existing, overrides, **kwargs)
    described_class.config(existing, overrides, sdk, **kwargs)
  end

  describe '.config' do
    it 'accepts a valid configuration and computes fasp_runtime from the SDK folder' do
      result = config(nil, {port: 55_002, 'workers' => {'max_concurrent' => 10}})
      expect(result['port']).to(eq(55_002))
      expect(result['workers']).to(eq({'max_concurrent' => 10}))
      expect(result['fasp_runtime']).to(eq({'use_embedded' => false, 'user_defined' => {'bin' => sdk, 'etc' => sdk}}))
    end

    it 'lets the user override the computed fasp_runtime' do
      result = config(nil, {'fasp_runtime' => {'use_embedded' => true}})
      expect(result['fasp_runtime']['use_embedded']).to(be(true))
    end

    it 'merges deeply with the existing configuration' do
      result = config({'port' => 1, 'workers' => {'max_concurrent' => 5, 'transfer_max_age' => 10}}, {'workers' => {'max_concurrent' => 7}})
      expect(result['port']).to(eq(1))
      expect(result['workers']).to(eq({'max_concurrent' => 7, 'transfer_max_age' => 10}))
    end

    it 'removes a key given as null' do
      result = config({'port' => 1, 'log_level' => 'debug', 'workers' => {'max_concurrent' => 5}}, {'log_level' => nil, 'workers' => nil})
      expect(result.keys).to(contain_exactly('port', 'fasp_runtime'))
    end

    it 'does not modify its arguments' do
      existing = {'workers' => {'max_concurrent' => 5}}
      overrides = {'workers' => {'max_concurrent' => 7}}
      config(existing, overrides)
      expect(existing).to(eq({'workers' => {'max_concurrent' => 5}}))
      expect(overrides).to(eq({'workers' => {'max_concurrent' => 7}}))
    end

    it 'reports an unknown key, and the file when the key is in the existing configuration' do
      expect { config({'log_levl' => 'debug'}, {}, file: file) }.to(raise_error(Aspera::ParameterError, /log_levl.*#{Regexp.escape(file)}/m))
    end

    it 'reports an unknown key given by the user without file' do
      expect { config({}, {'log_levl' => 'debug'}, file: file) }.to(raise_error(Aspera::ParameterError) do |e|
        expect(e.message).to(include('log_levl'))
        expect(e.message).not_to(include(file))
      end)
    end

    it 'reports a wrong type' do
      expect { config(nil, {'port' => 'abc'}) }.to(raise_error(Aspera::ParameterError, %r{/port}))
    end

    it 'refuses tls.enabled without certificate' do
      expect { config(nil, {'tls' => {'enabled' => true}}) }.to(raise_error(Aspera::ParameterError, /certificate/))
    end

    it 'accepts tls.enabled with certificate and key' do
      result = config(nil, {'tls' => {'enabled' => true, 'certificate' => '/c.pem', 'key' => '/k.pem'}})
      expect(result['tls']['enabled']).to(be(true))
    end

    it 'refuses use_embedded false without user_defined' do
      expect { config(nil, {'fasp_runtime' => {'user_defined' => nil}}) }.to(raise_error(Aspera::ParameterError, /user_defined/))
    end

    it 'generates an API key when authentication is enabled and none is given' do
      key = config(nil, {'authentication' => {'enabled' => true}})['authentication']['api_key']
      expect(key).to(match(/\A\h{64}\z/))
    end

    it 'keeps the API key of the existing configuration' do
      existing = {'authentication' => {'enabled' => true, 'api_key' => 'kept'}}
      expect(config(existing, {})['authentication']['api_key']).to(eq('kept'))
      expect(config(existing, {'authentication' => {'enabled' => true}})['authentication']['api_key']).to(eq('kept'))
    end

    it 'uses the API key given by the user' do
      existing = {'authentication' => {'enabled' => true, 'api_key' => 'kept'}}
      expect(config(existing, {'authentication' => {'api_key' => 'new'}})['authentication']['api_key']).to(eq('new'))
    end

    it 'does not generate an API key when authentication is not enabled' do
      expect(config(nil, {'authentication' => {'enabled' => false}})['authentication']).to(eq({'enabled' => false}))
    end
  end

  describe 'service schema' do
    let(:validator) { Aspera::Schema::Validator.instance }
    let(:path) { Aspera::Schema::Registry::SERVICE_OPTIONS }

    it 'is registered' do
      expect(Aspera::Schema::Registry.instance.reader(path)['properties']).to(include('name', 'user', 'group', 'unit_dir', 'after', 'environment'))
    end

    it 'accepts valid values and refuses unknown keys' do
      expect(validator.errors({'user' => 'aspweb', 'environment' => {'TRANSFERD_PORT' => '1'}}, path)).to(be_empty)
      expect(validator.errors({'usr' => 'aspweb'}, path)).not_to(be_empty)
    end
  end

  describe 'service config schema' do
    let(:validator) { Aspera::Schema::Validator.instance }
    let(:path) { Aspera::Schema::Registry::TRANSFERD_SERVICE_CONFIG }

    it 'is registered' do
      expect(Aspera::Schema::Registry.instance.reader(path)['properties']).to(include('service', 'config'))
    end

    it 'accepts valid values and refuses unknown keys' do
      expect(validator.errors({'service' => {'user' => 'aspweb'}, 'config' => {'port' => 55_002}}, path)).to(be_empty)
      expect(validator.errors({'unknown_key' => 'test'}, path)).not_to(be_empty)
      expect(validator.errors({'service' => {'unknown_service_opt' => 'test'}}, path)).not_to(be_empty)
    end
  end
end
