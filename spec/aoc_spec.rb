# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/api/aoc'
require 'bundler/setup'

RSpec.describe(Aspera::Api::AoC) do
  describe '.new with auth web' do
    let(:web_args) { {scope: 'user:all', url: 'https://org.ibmaspera.com', auth: :web, redirect_uri: 'http://localhost:12345'} }

    before do
      allow(described_class).to(receive(:link_info).and_return({instance_domain: 'ibmaspera.com', organization: 'org'}))
    end

    it 'refuses the global client' do
      expect { described_class.new(**web_args) }.to(raise_error(Aspera::ParameterError, /API client of the organization/))
    end

    it 'accepts an API client of the organization' do
      expect(described_class.new(client_id: 'c1', **web_args).auth_params[:redirect_uri]).to(eq('http://localhost:12345'))
    end
  end

  describe '#node_api_from' do
    let(:auth) { {type: :oauth2, grant_method: :jwt, params: {scope: 'user:all'}} }

    # AoC API with OAuth auth parameters, without server
    let(:aoc) do
      api = Aspera::Api::AoC.allocate
      api.instance_variable_set(:@auth_params, auth)
      allow(api).to(receive(:read).with('nodes/n1').and_return({'url' => 'https://node', 'access_key' => 'ak1'}))
      api
    end

    it 'does not modify auth parameters of AoC API' do
      node_params = aoc.node_api_from(node_id: 'n1', scope: Aspera::Api::Node::Scope::ADMIN).auth_params[:params]
      expect(node_params).to(eq({scope: 'node.ak1:admin:all', owner_access: true}))
      expect(auth[:params]).to(eq({scope: 'user:all'}))
      expect(aoc.node_api_from(node_id: 'n1').auth_params[:params]).to(eq({scope: 'node.ak1:user:all'}))
    end
  end
end
