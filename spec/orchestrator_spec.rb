# frozen_string_literal: true

require_relative 'spec_helper'
require 'aspera/cli/plugins/orchestrator'
require 'aspera/cli/parser'
require 'aspera/cli/context'

RSpec.describe(Aspera::Cli::Plugins::Orchestrator) do
  let(:parser) { Aspera::Cli::Parser.new('orchestrator') }
  let(:context) do
    ctx = Aspera::Cli::Context.new
    ctx.man_header = false
    ctx.options = parser
    ctx
  end
  let(:orchestrator) { described_class.new(context: context) }

  before do
    described_class.declare_options(parser, target: orchestrator)
  end

  describe '#api_orch' do
    def parse_argv(argv)
      p = Aspera::Cli::Parser.new('orchestrator', argv)
      described_class.declare_options(p, target: orchestrator)
      p.parse_options!
      context.options = p
    end

    it 'configures Rest::Client for token auth (JWT credentials) with username and password by default' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret])
      client = orchestrator.api_orch
      expect(client.base_url).to(eq('https://orch.example.com'))
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(username: 'admin', password: 'secret'))
    end

    it 'configures Rest::Client for basic auth with username and password' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret --auth_style=basic])
      client = orchestrator.api_orch
      expect(client.base_url).to(eq('https://orch.example.com'))
      expect(client.auth_params).to(eq(type: :basic, username: 'admin', password: 'secret'))
    end

    it 'configures Rest::Client for query auth with username and password' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret --auth_style=query])
      client = orchestrator.api_orch
      expect(client.auth_params).to(eq(type: :url, url_query: {'login' => 'admin', 'password' => 'secret'}))
    end

    it 'configures Rest::Client for token auth (JWT credentials) with username and password' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=secret --auth_style=token])
      client = orchestrator.api_orch
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(username: 'admin', password: 'secret'))
    end

    it 'configures Rest::Client for query auth with apikey' do
      parse_argv(%w[--url=https://orch.example.com --apikey=mykey123 --auth_style=query])
      client = orchestrator.api_orch
      expect(client.auth_params).to(eq(type: :url, url_query: {'apikey' => 'mykey123'}))
    end

    it 'configures Rest::Client for token auth with apikey' do
      parse_argv(%w[--url=https://orch.example.com --apikey=mykey123 --auth_style=token])
      client = orchestrator.api_orch
      expect(client.auth_params[:type]).to(eq(:oauth2))
      expect(client.auth_params[:grant_method]).to(eq(:json_credentials))
      expect(client.auth_params[:path_token]).to(eq('api/login'))
      expect(client.auth_params[:token_field]).to(eq('token'))
      expect(client.auth_params[:json]).to(eq(apikey: 'mykey123'))
    end

    it 'does not include passwords or apikey in token cache id' do
      parse_argv(%w[--url=https://orch.example.com --username=admin --password=my_secret_password --auth_style=token])
      client = orchestrator.api_orch
      token_cache_id = client.oauth.instance_variable_get(:@token_cache_id)
      expect(token_cache_id).not_to(include('my_secret_password'))
      expect(token_cache_id).to(include('admin'))

      orchestrator.instance_variable_set(:@api_orch, nil)
      parse_argv(%w[--url=https://orch.example.com --apikey=my_super_secret_key --auth_style=token])
      client2 = orchestrator.api_orch
      token_cache_id2 = client2.oauth.instance_variable_get(:@token_cache_id)
      expect(token_cache_id2).not_to(include('my_super_secret_key'))
    end

    it 'raises error when using basic auth_style with apikey' do
      parse_argv(%w[--url=https://orch.example.com --apikey=mykey123 --auth_style=basic])
      expect { orchestrator.api_orch }.to(raise_error(Aspera::Cli::BadArgument, /basic auth style cannot be used with apikey/))
    end
  end
end
