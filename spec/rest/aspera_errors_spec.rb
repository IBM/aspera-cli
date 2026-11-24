# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../../lib/aspera/rest/aspera_errors'
require 'net/http'

RSpec.describe(Aspera::Rest::ErrorAnalyzer) do
  it 'has Aspera handlers registered once on require' do
    req = Net::HTTP::Get.new('/api')
    req['host'] = 'example.com'
    http = instance_double(Net::HTTPResponse, code: '400', message: 'Bad Request')
    expect { described_class.instance.raise_on_error(req, {'message' => 'boom'}, http) }
      .to(raise_error(Aspera::Rest::CallError, "boom\nexample.com 400 Bad Request"))
  end

  it 'gives the message of an answer with field error (and the other fields)' do
    req = Net::HTTP::Post.new('/token')
    req['host'] = 'example.com'
    http = instance_double(Net::HTTPResponse, code: '400', message: 'Bad Request')
    expect { described_class.instance.raise_on_error(req, {'error' => 'invalid_grant', 'error_description' => 'bad key'}, http) }
      .to(raise_error(Aspera::Rest::CallError, "invalid_grant\nerror_description: bad key\nbad key\nerror: invalid_grant\nexample.com 400 Bad Request"))
  end

  it 'has no handler of a specific API (registered by the bundles)' do
    names = described_class.instance.instance_variable_get(:@error_handlers).map { |handler| handler[:name] }
    expect(names).to(include('Type 1: error:user_message', 'Type 4: error', 'Type 7: errors[]', 'Type Generic'))
  end
end
