# frozen_string_literal: true

require 'spec_helper'
require 'aspera/id_generator'

RSpec.describe(Aspera::IdGenerator) do
  describe '.from_list' do
    it 'generates a clean identifier from strings and URLs' do
      expect(described_class.from_list('faspio', 'https://eudemo.asperademo.com/faspio', 'admin')).to(eq('faspio_eudemo_asperademo_com_admin'))
    end

    it 'handles http URLs and nil elements' do
      expect(described_class.from_list('faspio', 'http://localhost:8080', nil)).to(eq('faspio_localhost'))
    end

    it 'flattens nested arrays and handles special characters' do
      expect(described_class.from_list('my_app', ['https://test.example.com', 'client_1'])).to(eq('my_app_test_example_com_client_1'))
    end
  end
end
