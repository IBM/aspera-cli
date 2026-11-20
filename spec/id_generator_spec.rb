# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/id_generator'

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

    it 'keeps a list of URLs separated by spaces as text (OAuth scope)' do
      scope = 'https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.force-ssl'
      id = described_class.from_list('token', 'https://accounts.google.com/o/oauth2', scope)
      expect(id).to(start_with('token_accounts_google_com_'))
      expect(id).to(include('youtube_upload'))
      expect(id).to(include('youtube_force-ssl'))
    end

    it 'keeps an invalid URL as text' do
      expect(described_class.from_list('app', 'https://host.example.com/a|b')).to(eq('app_https_host_example_com_a_b'))
    end

    it 'keeps a URL without host as text' do
      expect(described_class.from_list('app', 'https:///path')).to(eq('app_https_path'))
    end

    it 'keeps identifiers that parse as a URI without host, and non String values' do
      expect(described_class.from_list('app', 'user:read', :sym, 12)).to(eq('app_user_read_sym_12'))
    end

    it 'ignores the case of the scheme and of the host' do
      expect(described_class.from_list('app', 'HTTPS://Test.Example.com/x')).to(eq('app_test_example_com'))
    end
  end
end
