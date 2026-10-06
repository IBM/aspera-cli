# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'aspera/rest/aspera_errors'

RSpec.describe(Aspera::Rest::ErrorAnalyzer) do
  it 'has Aspera handlers registered once on require' do
    req = Net::HTTP::Get.new('/api')
    req['host'] = 'example.com'
    http = instance_double(Net::HTTPResponse, code: '400', message: 'Bad Request')
    expect { described_class.instance.raise_on_error(req, {'message' => 'boom'}, http) }
      .to(raise_error(Aspera::Rest::CallError, "boom\nexample.com 400 Bad Request"))
  end
end
