# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Tests for the REST client of Aspera::Plugins::Node::Agent: basic authentication, or bearer token of an access key.

require 'spec_helper'
require_relative '../../../rest'
require_relative '../agent'
require 'securerandom'

RSpec.describe(Aspera::Plugins::Node::Agent) do
  subject(:agent) { described_class.allocate }

  it 'requires the root file id with a bearer token' do
    token = Aspera::OAuth::Factory.bearer_authorization(SecureRandom.alphanumeric(16))
    expect { agent.send(:setup_api, url: 'https://node.example.com', username: 'access_key', password: token) }
      .to(raise_error(Aspera::ParameterError, 'root_id is required with a bearer token (access key)'))
  end
end
