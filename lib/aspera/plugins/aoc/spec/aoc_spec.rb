# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../api'
require 'bundler/setup'

RSpec.describe(Aspera::Plugins::Aoc::Api) do
  describe '#node_api_from' do
    let(:auth) { {type: :oauth2, grant_method: :jwt, params: {scope: 'user:all'}} }

    # AoC API with OAuth auth parameters, without server
    let(:aoc) do
      api = Aspera::Plugins::Aoc::Api.allocate
      api.instance_variable_set(:@auth_params, auth)
      allow(api).to(receive(:read).with('nodes/n1').and_return({'url' => 'https://node', 'access_key' => 'ak1'}))
      api
    end

    it 'does not modify auth parameters of AoC API' do
      node_params = aoc.node_api_from(node_id: 'n1', scope: Aspera::Plugins::Node::Api::Scope::ADMIN).auth_params[:params]
      expect(node_params).to(eq({scope: 'node.ak1:admin:all', owner_access: true}))
      expect(auth[:params]).to(eq({scope: 'user:all'}))
      expect(aoc.node_api_from(node_id: 'n1').auth_params[:params]).to(eq({scope: 'node.ak1:user:all'}))
    end
  end
end
