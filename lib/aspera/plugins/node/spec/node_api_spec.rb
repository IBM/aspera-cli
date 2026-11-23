# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Node::Api — `read` is stubbed, no node server needed.

require 'spec_helper'
require_relative '../api'
require 'openssl'
require 'securerandom'

RSpec.describe(Aspera::Plugins::Node::Api) do
  let(:access_key) { 'my_access_key' }
  let(:token) { "Bearer #{SecureRandom.hex(16)}" }
  let(:api) do
    described_class.new(
      base_url: 'https://node.example.com',
      auth:     {type: :none},
      headers:  {described_class::HEADER_X_ASPERA_ACCESS_KEY => access_key, 'Authorization' => token}
    )
  end
  # Logged warnings
  let(:warnings) { [] }

  # Class level options are restored after each test
  around do |example|
    options = described_class.api_options.dup
    example.run
  ensure
    described_class.instance_variable_set(:@api_options, options)
    described_class.instance_variable_set(:@dynamic_key, nil)
  end

  before { allow(Aspera::Log.log).to(receive(:warn)) { |*args, &block| warnings.push(block ? block.call : args.first) } }

  describe '.decode_bearer_token' do
    let(:private_key) { OpenSSL::PKey::RSA.new(2048) }

    it 'decodes the payload of a bearer token' do
      token = described_class.bearer_token(access_key: access_key, payload: {'user_id' => 'user1'}, private_key: private_key)
      expect(described_class.decode_bearer_token(token)).to(include('user_id' => 'user1', 'scope' => "node.#{access_key}:user:all"))
    end

    it 'refuses a token that decompresses to more than the limit, without decompressing all of it' do
      bomb = Base64.strict_encode64(Zlib::Deflate.deflate("{\"user_id\":\"#{'a' * 100_000_000}\"}", Zlib::BEST_COMPRESSION))
      expect { described_class.decode_bearer_token(bomb) }.to(raise_error(Aspera::ParameterError, /Node bearer token is too large when decompressed/))
    end
  end

  describe '.add_public_key' do
    it 'adds the public key in OpenSSH format when a dynamic key is set' do
      expect(described_class.add_public_key({})).to(eq({}))
      described_class.use_dynamic_key = OpenSSL::PKey::RSA.new(2048).to_pem
      expect(described_class.add_public_key({})['public_keys']).to(match(%r{\Assh-rsa [A-Za-z0-9+/=]+\z}))
    end
  end

  describe '#node_id_to_node' do
    let(:app_api) { instance_double('Aspera::Api::AoC') }
    let(:app_info) { Struct.new(:node_info, :api, :workspace_id, :workspace_name).new({'id' => 'n1'}, app_api, 'w1', 'ws') }
    let(:app_node) { described_class.new(base_url: 'https://node.example.com', app_info: app_info) }

    it 'warns without resolver' do
      expect(api.node_id_to_node('n2')).to(be_nil)
      expect(warnings).to(include(/no resolver/))
    end

    it 'returns self for the same node, and asks the application for another node' do
      allow(app_api).to(receive(:node_api_from).and_return(:other_node))
      expect(app_node.node_id_to_node('n1')).to(be(app_node))
      expect(app_node.node_id_to_node('n2')).to(eq(:other_node))
      expect(app_api).to(have_received(:node_api_from).with(node_id: 'n2', workspace_id: 'w1', workspace_name: 'ws'))
    end

    it 'warns when the application fails to resolve the node' do
      allow(app_api).to(receive(:node_api_from).and_raise(Aspera::Rest::CallError, 'forbidden'))
      expect(app_node.node_id_to_node('n2')).to(be_nil)
      expect(warnings).to(include(/Cannot resolve link with node id n2: forbidden/))
    end
  end

  describe '#entry_has_link_information' do
    it 'reads missing target information on the entry' do
      allow(api).to(receive(:read).with('files/l1').and_return({'target_node_id' => 'n2', 'target_id' => 't2'}))
      entry = {'id' => 'l1', 'name' => 'lnk'}
      expect(api.entry_has_link_information(entry)).to(be(true))
      expect(entry).to(include('target_node_id' => 'n2', 'target_id' => 't2'))
    end

    it 'warns if target information is still missing' do
      allow(api).to(receive(:read).with('files/l1').and_return({}))
      expect(api.entry_has_link_information({'id' => 'l1', 'name' => 'lnk'})).to(be(false))
      expect(warnings).to(include('Missing target information for link: lnk'))
    end
  end

  describe '#read_folder_content' do
    it 'iterates with the token of API v4' do
      pages = [[[{'name' => 'a'}], {described_class::HEADER_X_NEXT_ITER_TOKEN => 'tok'}], [[{'name' => 'b'}], {}]]
      queries = []
      allow(api).to(receive(:read)) do |_path, query, **_kwargs|
        queries.push(query.dup)
        pages.shift
      end
      expect(api.read_folder_content('f1').map { |e| e['name'] }).to(eq(%w[a b]))
      expect(queries).to(eq([{'per_page' => 1000}, {'per_page' => 1000, 'iteration_token' => 'tok'}]))
    end

    it 'reads pages of API v3 with per_page' do
      described_class.api_options = {accept_v4: false}
      pages = [[[{'name' => 'a'}], {}], [[], {}]]
      queries = []
      allow(api).to(receive(:read)) do |_path, query, **_kwargs|
        queries.push(query.dup)
        pages.shift
      end
      expect(api.read_folder_content('f1', {'per_page' => 1}).map { |e| e['name'] }).to(eq(%w[a]))
      # First page is 1 (node: start index is (page - 1) * per_page)
      expect(queries.map { |query| query['page'] }).to(eq([1, 2]))
    end

    it 'adds per_page with page only, as API v3 requires both' do
      described_class.api_options = {accept_v4: false}
      queries = []
      allow(api).to(receive(:read)) do |_path, query, **_kwargs|
        queries.push(query.dup)
        [[], {}]
      end
      api.read_folder_content('f1', {'page' => 3})
      expect(queries).to(eq([{'page' => 3, 'per_page' => 1000}]))
    end

    it 'logs instead of raising when exception is false' do
      described_class.api_options = {accept_v4: false}
      allow(api).to(receive(:read).and_raise(Aspera::Rest::CallError, 'denied'))
      expect(api.read_folder_content('f1', {'per_page' => 10}, exception: false, path: '/x')).to(eq([]))
      expect(warnings).to(include('/x: Aspera::Rest::CallError denied'))
    end
  end

  describe '#process_folder_tree' do
    it 'logs entries in error and skips them' do
      allow(api).to(receive(:read_folder_content).and_return([{'error' => {'user_message' => 'access denied'}}, {'error' => 'x'}]))
      allow(Aspera::Log.log).to(receive(:error))
      api.process_folder_tree(method_sym: :unused, state: nil, top_file_id: 'f1')
      expect(Aspera::Log.log).to(have_received(:error).with('access denied').once)
    end
  end

  describe '#resolve_api_fid_paths' do
    it 'transfers the content of a single folder' do
      allow(api).to(receive(:resolve_api_fid).and_return(Aspera::Plugins::Node::NodeFileId.new(api, 'd1')))
      allow(api).to(receive(:read).with('files/d1').and_return({'type' => 'folder'}))
      expect(api.resolve_api_fid_paths('root', [{'source' => 'dir'}])[1]).to(eq([{'source' => '.'}]))
    end
  end

  describe '#transfer_spec_gen4' do
    it 'uses the access key and authorization headers without authentication' do
      allow(api).to(receive(:read).with('info').and_return({'transfer_user' => 'xfer', 'settings' => [{'name' => 'wss_enabled', 'value' => true}]}))
      tspec = api.transfer_spec_gen4('f1', 'send')
      expect(tspec).to(include('token' => token, 'remote_host' => 'node.example.com', 'remote_user' => 'xfer', 'wss_enabled' => true))
      expect(tspec.dig('tags', 'aspera', 'node')).to(eq({'access_key' => access_key, 'file_id' => 'f1'}))
    end
  end

  describe '#read_with_paging' do
    def link(token) = {'Link' => "<https://node.example.com/ops/transfers?iteration_token=#{token}>; rel=\"next\""}

    it 'stops at the maximum number of items' do
      allow(api).to(receive(:read).and_return([[1, 2, 3], link('t1')]))
      expect(api.read_with_paging('ops/transfers', {Aspera::Rest::List::MAX_ITEMS => 2})).to(eq([1, 2]))
    end

    it 'warns on an invalid URI in the Link header' do
      allow(api).to(receive(:read).and_return([[1], {'Link' => '<https://node .example.com/x?iteration_token=t1>; rel="next"'}]))
      expect(api.read_with_paging('ops/transfers')).to(eq([1]))
      expect(warnings).to(include(/Invalid URI in Link header/))
    end
  end

  describe '#read_with_pages' do
    it 'reads pages until a partial page' do
      pages = [[[1, 2], {described_class::HEADER_X_TOTAL_COUNT => '3'}], [[3], {}]]
      allow(api).to(receive(:read)) { pages.shift }
      expect(api.read_with_pages('users', {'per_page' => 2})).to(eq([1, 2, 3]))
    end

    it 'returns the items read before an error' do
      calls = 0
      allow(api).to(receive(:read)) do
        calls += 1
        raise Aspera::Rest::CallError, 'gone' if calls > 1
        [[1, 2], {}]
      end
      expect(api.read_with_pages('users', {'per_page' => 2})).to(eq([1, 2]))
      expect(warnings).to(include('Aspera::Rest::CallError gone'))
    end
  end
end
