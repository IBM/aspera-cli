# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'aspera/data_repository'

RSpec.describe(Aspera::DataRepository) do
  subject(:repository) { described_class.instance }

  let(:source_root) { File.expand_path('..', __dir__) }

  it 'has one data file per item' do
    expect(Dir.children(File.join(source_root, 'lib', 'aspera', 'data')).size).to(eq(described_class::ELEMENTS.size))
  end

  it 'decodes all items when loaded alone (no dependency on other files)' do
    script = 'require "aspera/data_repository"; Aspera::DataRepository::ELEMENTS.each { |i| Aspera::DataRepository.instance.item(i) }'
    output, status = Open3.capture2e(RbConfig.ruby, "-I#{File.join(source_root, 'lib')}", '-e', script)
    expect(status).to(be_success, output)
  end

  it 'returns all items as valid UTF-8 text' do
    described_class::ELEMENTS.each do |name|
      value = repository.item(name)
      expect(value.encoding).to(eq(Encoding::UTF_8), name.to_s)
      expect(value).to(be_valid_encoding, name.to_s)
      expect(value).not_to(be_empty, name.to_s)
    end
  end

  it 'decodes SSH keys as PEM private keys of the expected type' do
    {dsa: OpenSSL::PKey::DSA, rsa: OpenSSL::PKey::RSA}.each do |name, klass|
      key = OpenSSL::PKey.read(repository.item(name))
      expect(key).to(be_a(klass))
      expect(key).to(be_private)
    end
  end

  it 'decodes uuid as a UUID' do
    expect(repository.item(:uuid)).to(match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/))
  end

  it 'decodes client secrets as base64url' do
    %i[aspera.global-cli-client aspera.drive].each do |name|
      expect(repository.item(name)).to(match(/\A[A-Za-z0-9_-]+=*\z/), name.to_s)
    end
  end

  it 'rejects an unknown item' do
    expect { repository.item(:unknown) }.to(raise_error(Aspera::ParameterError, /data item/))
  end
end
