# frozen_string_literal: true

require 'spec_helper'
require 'aspera/rest'
require 'aspera/oauth/client/web'

RSpec.describe(Aspera::OAuth::Web) do
  def web(redirect_uri) = described_class.new(redirect_uri: redirect_uri, base_url: 'https://example.com/oauth2')

  it 'accepts a loopback redirect_uri, also IPv6' do
    %w[http://localhost:12345 http://127.0.0.1:12345 http://127.0.0.2:12345/cb http://[::1]:12345 https://[::1]:12345/cb].each do |redirect_uri|
      expect { web(redirect_uri) }.not_to(raise_error, redirect_uri)
    end
  end

  it 'refuses a redirect_uri that is not loopback' do
    %w[http://example.com:12345 http://0.0.0.0:12345 http://[::]:12345].each do |redirect_uri|
      expect { web(redirect_uri) }.to(raise_error(Aspera::AssertError, /redirect_uri host must be loopback/), redirect_uri)
    end
  end
end
