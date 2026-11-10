# frozen_string_literal: true

require 'spec_helper'
require 'aspera/schema/registry'

RSpec.describe(Aspera::Schema::Registry) do
  describe 'transferd configuration schema' do
    let(:file) { File.join(File.expand_path('../lib', __dir__), described_class::LOCATIONS[:transferd]) }

    it 'is registered and owned by ascli' do
      expect(described_class.known?(:transferd)).to(be(true))
      expect(described_class.owned?('transferd')).to(be(true))
    end

    it 'is a file of the gem, loadable with the YAML loader despite the header comment' do
      expect(File.exist?(file)).to(be(true))
      schema = Aspera::Yaml.safe_load(File.read(file))
      expect(schema['additionalProperties']).to(be(false))
      expect(schema['$comment']).to(match(/transferd \d+\.\d+\.\d+/))
    end

    it 'is readable through the registry' do
      expect(described_class.instance.reader('transferd')['properties']).to(include('port', 'tls', 'authentication', 'fasp_runtime'))
    end
  end
end
