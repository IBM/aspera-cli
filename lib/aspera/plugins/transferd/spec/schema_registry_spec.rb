# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../../../schema/registry'

RSpec.describe(Aspera::Schema::Registry) do
  describe 'transferd configuration schema' do
    let(:file) { described_class.bundle_schema(:transferd).file }

    it 'is registered and owned by ascli' do
      expect(described_class.known?(:transferd)).to(be(true))
      expect(described_class.owned?('transferd')).to(be(true))
    end

    it 'is a file of the bundle, loadable with the YAML loader despite the header comment' do
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
