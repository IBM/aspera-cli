# frozen_string_literal: true

# Unit tests for Aspera::Api::Faspex — no server needed.

require 'spec_helper'
require_relative '../lib/aspera/api/faspex'
require 'securerandom'

RSpec.describe(Aspera::Api::Faspex) do
  describe 'web authentication' do
    # @return [Aspera::OAuth::Web]
    def web_oauth(**kwargs)
      described_class.new(url: 'https://faspex.example.com/aspera/faspex', auth: :web, client_id: 'CLIENT', redirect_uri: 'http://localhost:12345', **kwargs).oauth
    end

    it 'uses PKCE' do
      expect(web_oauth.instance_variable_get(:@pkce)).to(be(true))
    end

    it 'sends the client secret when it is set (API client with HTTP basic auth)' do
      client_secret = SecureRandom.hex
      expect(web_oauth(client_secret: client_secret).params).to(eq({client_id: 'CLIENT', client_secret: client_secret}))
    end

    it 'sends no client secret when it is not set' do
      expect(web_oauth.params).to(eq({client_id: 'CLIENT'}))
    end
  end
end
