# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Plugins::Aoc::Commands: simple commands that map to one API call — no AoC server needed.
# The AoC API (and the automation and analytics APIs) are replaced by doubles that record calls.

require_relative '../../../cli/context'
require_relative '../../../cli/parser'
require_relative '../commands'
require_relative '../../../cli/runner'
require 'openssl'
require 'tempfile'

module Aspera
  module Plugins
    module Aoc
      RSpec.describe(Commands) do
        # Calls received by the API doubles: [api, method, path, *args]
        let(:calls) { [] }
        # Response of the API doubles, by [method, path], default: empty Hash
        let(:responses) { {} }
        let(:user_info) { {'id' => 'u1', 'organization_id' => 'o1', 'read_only_home_node_id' => 'n1'} }

        # @param name [Symbol] name of API in recorded calls
        # @return [Object] double recording `read`, `create`, `update`, `delete`
        def recording_api(name, klass)
          api = instance_double(klass)
          %i[read create update delete].each do |method|
            allow(api).to(receive(method)) do |path, *args|
              calls.push([name, method, path, *args])
              response = responses.fetch([method, path]) { {} }
              raise response if response.is_a?(Exception)
              response
            end
          end
          api
        end

        let(:aoc_api) do
          api = recording_api(:aoc, Aspera::Plugins::Aoc::Api)
          allow(api).to(receive_messages(current_user_info: user_info, workspace_info: {id: 'w1', name: 'ws'}, default_workspace?: true, private_link: nil))
          allow(api).to(receive(:read_with_paging)) do |path, query|
            calls.push([:aoc, :read_with_paging, path, query])
            responses.fetch([:read_with_paging, path]) { {items: [{'id' => 'i1'}], total: 1} }
          end
          api
        end
        let(:automation_api) { recording_api(:automation, Rest::Client) }
        let(:analytics_api) { recording_api(:analytics, Rest::Client) }

        # Plugin with API doubles
        # @param argv     [Array<String>] command line
        # @param transfer [Object, nil]   transfer agent manager
        # @param stub_aoc [Boolean]       `false` to build the AoC API from options (`Aspera::Plugins::Aoc::Api.new` is then stubbed by caller)
        # @return [Aoc] plugin instance
        def plugin(*argv, transfer: nil, stub_aoc: true)
          context = Cli::Context.new
          context.man_header = false
          context.formatter = double(display_status: nil)
          context.transfer = transfer
          context.options = Cli::Parser.new('test', argv)
          instance = described_class.new(context: context)
          apis = {aoc: aoc_api, automation: automation_api, analytics: analytics_api}
          instance.define_singleton_method(:aoc_api) { apis[:aoc] } if stub_aoc
          instance.define_singleton_method(:build_analytics_api) { apis[:analytics] }
          instance.define_singleton_method(:setup_automation_api) do |**|
            @automation_api = apis[:automation]
            {}
          end
          instance
        end

        # Execute a command line with API doubles (arguments: see `plugin`)
        # @return [Cli::Result::Base] command result
        def execute(*, **) = plugin(*, **).execute_action

        describe 'admin application' do
          it 'shows and modifies settings of an application type' do
            responses[[:read, '/apps/files/settings']] = {'a' => 1}
            expect(execute('admin', 'application', 'settings', 'files', 'show').data).to(eq({'a' => 1}))
            expect(execute('admin', 'application', 'settings', 'packages', 'modify', '@json:{"b":2}').data).to(eq('modified'))
            expect(calls.last).to(eq([:aoc, :update, '/apps/packages/settings', {'b' => 2}]))
          end

          it 'shows and modifies an application instance' do
            execute('admin', 'application', 'instance', 'files', 'show', 'i1')
            expect(execute('admin', 'application', 'instance', 'activity', 'modify', 'i2', '@json:{"c":3}').data).to(eq('modified'))
            expect(calls).to(eq([[:aoc, :read, 'admin/apps_new/files/i1', nil], [:aoc, :update, 'admin/apps_new/activity/i2', {'c' => 3}]]))
          end

          it 'lists application instances of the current workspace' do
            expect(execute('admin', 'application', 'instance', 'list').data).to(eq([{'id' => 'i1'}]))
            expect(calls).to(eq([[:aoc, :read_with_paging, 'admin/apps_new', {workspace_id: 'w1'}]]))
          end

          it 'shows, deletes and creates an application membership' do
            execute('admin', 'application', 'membership', 'show', 'm1')
            expect(execute('admin', 'application', 'membership', 'delete', 'm1').data).to(eq('deleted'))
            execute('admin', 'application', 'membership', 'create', '@json:{"app_type":"files","member_id":"x"}')
            expect(calls).to(eq([
              [:aoc, :read, 'apps/app_memberships/m1', nil],
              [:aoc, :delete, 'apps/app_memberships/m1'],
              [:aoc, :create, 'apps/files/app_memberships', {'member_id' => 'x'}]
            ]))
          end

          it 'refuses a membership of unknown application type' do
            expect { execute('admin', 'application', 'membership', 'create', '@json:{"app_type":"foo"}') }.to(raise_error(/app_type/))
          end
        end

        describe 'admin resources' do
          it 'lists usage reports of the current workspace' do
            execute('admin', 'usage_reports')
            expect(calls).to(eq([[:aoc, :read_with_paging, 'usage_reports', {workspace_id: 'w1'}]]))
          end

          it 'sets the public key of a client from a private key' do
            # Generated at runtime: no key in the repository
            private_key = OpenSSL::PKey::RSA.new(2048)
            Tempfile.create('key') do |file|
              file.write(private_key.to_pem)
              file.close
              expect(execute('admin', 'client', 'set_pub_key', 'c1', "@file:#{file.path}")).to(be_a(Cli::Result::Success))
            end
            expect(calls).to(eq([[:aoc, :update, 'clients/c1', {jwt_grant_enabled: true, public_key: private_key.public_key.to_s}]]))
          end

          it 'shows the update status of a node' do
            responses[[:read, 'nodes/n1/update_status']] = {'status' => 'ok'}
            expect(execute('admin', 'node', 'update_status', 'n1').data).to(eq({'status' => 'ok'}))
          end

          it 'shows and modifies preferences and notifications of a user' do
            execute('admin', 'user', 'preferences', 'u2', 'show')
            execute('admin', 'user', 'notifications', 'u2', 'modify', '@json:{"d":4}')
            expect(calls).to(eq([
              [:aoc, :read, 'users/u2/user_interaction_preferences'],
              [:aoc, :update, 'users/u2/notification_preferences', {'d' => 4}]
            ]))
          end

          it 'creates a client registration token with the path of creation' do
            responses[[:create, 'admin/client_registration/token']] = {'token' => 't1'}
            execute('admin', 'client_registration_token', 'create', '@json:{"data":{"name":"n1"}}')
            expect(calls).to(eq([[:aoc, :create, 'admin/client_registration/token', {'data' => {'name' => 'n1'}}]]))
          end

          it 'shows and modifies an auth provider' do
            execute('admin', 'auth_providers', 'show', 'a1')
            expect(execute('admin', 'auth_providers', 'modify', 'a1', '@json:{"enabled":true}').data).to(eq('modified'))
            expect(calls).to(eq([[:aoc, :read, 'admin/auth_providers/a1'], [:aoc, :update, 'admin/auth_providers/a1', {'enabled' => true}]]))
          end

          # AoC fails with 500 on parameter `q` for this resource: the name is searched in the whole list
          it 'finds a SAML configuration by name without parameter q' do
            responses[[:read_with_paging, 'saml_configurations']] = {items: [{'id' => 's1', 'name' => 'sso'}, {'id' => 's2', 'name' => 'sso2'}], total: 2}
            execute('admin', 'saml_configuration', 'show', '%name:sso')
            expect(calls).to(eq([[:aoc, :read_with_paging, 'saml_configurations', {}], [:aoc, :read, 'saml_configurations/s1', nil]]))
          end

          # `help` as value of the argument reads these schemas: a missing one is an error
          it 'finds the schemas of create and modify in the API description' do
            config = described_class.const_get(:ADMIN_OBJECT_CONFIG)
            schema_of_op = {create: :schema, modify: :modify_schema}
            described_class.const_get(:ADMIN_OBJECTS).reject { |res| config.dig(res, :singleton) }.each do |res|
              cfg = described_class.aoc_res_cfg(res)
              schema_of_op.each do |op, key|
                next unless cfg[:ops].include?(op) && cfg[key]
                expect { Schema::Registry.instance.reader(cfg[key]) }.not_to(raise_error, "#{res} #{op}: #{cfg[key]}")
              end
            end
          end
        end

        describe 'admin analytics' do
          it 'uses the identifier of the current user resource when none is given' do
            responses[[:read, 'nodes/n1/transfers/e1/files']] = {'files' => [{'name' => 'f'}]}
            expect(execute('admin', 'analytics', 'files', 'nodes', '', 'e1').data).to(eq([{'name' => 'f'}]))
            expect(calls).to(eq([[:analytics, :read, 'nodes/n1/transfers/e1/files', {'limit' => 100}]]))
          end
        end

        describe 'admin workspace shared_folder member list' do
          before do
            allow(aoc_api).to(receive(:read_with_paging).and_return({items: [{'id' => 'sf1', 'node_id' => 'n1', 'file_id' => 'f1'}], total: 1}))
          end

          it 'shows members, or the error when a member cannot be read' do
            node_api = recording_api(:node, Node::Api)
            allow(aoc_api).to(receive(:node_api_from).and_return(node_api))
            responses[[:read, 'permissions']] = [
              {'access_type' => 'user', 'access_id' => 'u1'},
              {'access_type' => 'group', 'access_id' => 'g1'}
            ]
            responses[[:read, 'admin/users/u1']] = {'name' => 'john'}
            responses[[:read, 'admin/groups/g1']] = RuntimeError.new('group deleted')
            result = execute('admin', 'workspace', 'shared_folder', 'w1', 'member', 'sf1', 'list')
            expect(result.data.map { |item| item['member'] }).to(eq([{'name' => 'john'}, {'name' => 'group deleted'}]))
          end
        end

        describe 'user notifications' do
          it 'shows and modifies notification preferences of the current user' do
            execute('user', 'notifications', 'show')
            expect(execute('user', 'notifications', 'modify', '@json:{"e":5}').data).to(eq('modified'))
            expect(calls).to(eq([[:aoc, :read, 'users/u1/notification_preferences'], [:aoc, :update, 'users/u1/notification_preferences', {'e' => 5}]]))
          end
        end

        describe 'packages' do
          it 'modifies a package' do
            expect(execute('packages', 'modify', 'p1', '@json:{"name":"n"}').data).to(eq('modified'))
            expect(calls).to(eq([[:aoc, :update, 'packages/p1', {'name' => 'n'}]]))
          end

          it 'deletes several packages' do
            execute('packages', 'delete', '@json:["p1","p2"]', '--bulk=yes')
            expect(calls).to(eq([[:aoc, :delete, 'packages/p1'], [:aoc, :delete, 'packages/p2']]))
          end
        end

        describe 'automation workflows' do
          it 'launches, updates state, cancels and deletes jobs of a workflow' do
            execute('automation', 'workflows', 'launch', 'w1')
            execute('automation', 'workflows', 'update_state', 'w1', '@json:{"state":"enabled"}')
            expect(execute('automation', 'workflows', 'cancel_instances', 'w1').data).to(eq('canceled'))
            expect(execute('automation', 'workflows', 'delete_instances', 'w1').data).to(eq('deleted'))
            execute('automation', 'instances', 'cancel', 'j1')
            expect(calls).to(eq([
              [:automation, :create, 'workflows/w1/launch', {}],
              [:automation, :update, 'workflows/w1/update_state', {'state' => 'enabled'}],
              [:automation, :update, 'workflows/w1/cancel_instances', {}],
              [:automation, :delete, 'workflows/w1/delete_instances'],
              [:automation, :update, 'workflow_instances/j1', {'status' => 'canceled'}]
            ]))
          end

          it 'lists and creates permissions of a workflow' do
            responses[[:read, 'workflow_permissions']] = [{'id' => 'p1'}]
            expect(execute('automation', 'workflows', 'permissions', 'w1', 'list').data).to(eq([{'id' => 'p1'}]))
            execute('automation', 'workflows', 'permissions', 'w1', 'create', '@json:{"user_id":"u1"}')
            expect(calls).to(eq([
              [:automation, :read, 'workflow_permissions', {'workflow_id' => 'w1'}],
              [:automation, :create, 'workflow_permissions', {'user_id' => 'u1', 'workflow_id' => 'w1'}]
            ]))
          end
        end

        # Node API double of a Gen4 node
        # @param name [Symbol] name of API in recorded calls
        def node_api_double(name)
          api = recording_api(name, Node::Api)
          allow(api).to(receive_messages(
            app_info:  double(node_info: {'id' => "#{name}_id", 'access_key' => "#{name}_ak", 'name' => name.to_s}),
            base_url:  "https://#{name}.example.com",
            oauth:     double(authorization: '<TOKEN>')
          ))
          api
        end

        describe 'short links' do
          let(:home_node_api) { node_api_double(:home) }
          let(:shared_node_api) { node_api_double(:shared) }

          before do
            allow(aoc_api).to(receive_messages(home: {node_id: 'n1', file_id: 'f1'}, node_api_from: home_node_api))
            allow(home_node_api).to(receive(:resolve_api_fid).with('f1', '/folder').and_return(double(node_api: shared_node_api, file_id: 'f2')))
            responses[[:read_with_paging, 'short_links']] = {items: [{'id' => 's1', 'resource_id' => 'r1'}], total: 1}
          end

          it 'creates a public link to a shared inbox with a password' do
            responses[[:create, 'short_links']] = {'id' => 's2'}
            expect(execute('packages', 'shared_inboxes', 'short_link', 'public', 'd1', 'create', '@json:{"password":"<PASSWORD>"}').data).to(eq({'id' => 's2'}))
            payload = calls.last[3]
            expect(payload[:password_enabled]).to(be(true))
            expect(payload[:data][:url_token_data][:password]).to(eq('<PASSWORD>'))
          end

          it 'deletes a public link of a folder and its node permission' do
            responses[[:read, 'permissions']] = [{'id' => 'perm1'}]
            expect(execute('files', 'short_link', '/folder', 'public', 'delete', 's1').data).to(eq('deleted'))
            expect(calls).to(include(
              [:shared, :delete, 'permissions/perm1'],
              [:aoc, :delete, 'short_links/s1', {edit_access: true, json_query: {node_id: 'shared_id', file_id: 'f2', workspace_id: 'w1'}.to_json}]
            ))
          end

          it 'fails to delete a public link of a folder without node permission' do
            responses[[:read, 'permissions']] = []
            expect { execute('files', 'short_link', '/folder', 'public', 'delete', 's1') }.to(raise_error(Cli::Error, 'Short link not found: r1'))
          end
        end

        describe 'node to node transfer' do
          let(:top_node_api) { node_api_double(:top) }
          let(:client_node_api) { node_api_double(:client) }
          let(:server_node_api) { node_api_double(:server) }
          let(:transfer) { double('transfer', start: Transfer::Result::Success.new) }

          before do
            allow(aoc_api).to(receive_messages(home: {node_id: 'n1', file_id: 'f1'}, node_api_from: top_node_api))
            allow(transfer).to(receive(:destination_folder).and_return('/dest'))
            allow(transfer).to(receive(:agent_instance=))
            allow(Node::Agent).to(receive(:new).and_return(:node_agent))
            allow(server_node_api).to(receive(:transfer_spec_gen4).and_return({'paths' => []}))
          end

          # @param client [String] client folder
          # @param server [String] server folder
          # @param root   [String] root file id
          def folders(client:, server:, root:)
            allow(top_node_api).to(receive(:resolve_api_fid).with(root, client).and_return(double(node_api: client_node_api, file_id: 'fc')))
            allow(top_node_api).to(receive(:resolve_api_fid).with(root, server).and_return(double(node_api: server_node_api, file_id: 'fs')))
          end

          it 'pulls from the home folder: the client folder is the destination' do
            folders(client: '/dest', server: '/src', root: 'f1')
            expect(execute('files', 'transfer', 'pull', '/src', transfer: transfer)).to(be_a(Cli::Result::Nothing))
            expect(Node::Agent).to(have_received(:new).with(url: 'https://client.example.com', username: 'client_ak', password: '<TOKEN>', root_id: 'fc'))
            expect(server_node_api).to(have_received(:transfer_spec_gen4).with(
              'fs', Transfer::Spec::DIRECTION_RECEIVE, {'remote_access_key' => 'server_ak', 'destination_root_id' => 'fs', 'source_root_id' => 'fc'}
            ))
          end

          it 'pushes from a node of admin: root of the access key' do
            responses[[:read, 'access_keys/top_ak']] = {'root_file_id' => 'root'}
            folders(client: '/src', server: '/dest', root: 'root')
            execute('admin', 'node', 'do', 'n2', 'transfer', 'push', '/src', transfer: transfer)
            expect(server_node_api).to(have_received(:transfer_spec_gen4).with('fs', Transfer::Spec::DIRECTION_SEND, anything))
          end

          it 'pushes from a shared folder of a workspace' do
            responses[[:read_with_paging, 'workspaces/w1/permissions']] = {items: [{'id' => 'sf1', 'node_id' => 'n1', 'file_id' => 'f1'}], total: 1}
            folders(client: '/src', server: '/dest', root: 'f1')
            execute('admin', 'workspace', 'shared_folder', 'w1', 'node', 'sf1', 'transfer', 'push', '/src', transfer: transfer)
            expect(aoc_api).to(have_received(:node_api_from).with(hash_including(node_id: 'n1', scope: Node::Api::Scope::ADMIN)))
          end
        end

        describe 'workspace display' do
          it 'shows the name of the private folder' do
            home_node_api = node_api_double(:home)
            allow(aoc_api).to(receive_messages(private_link: {}, home: {node_id: 'n1', file_id: 'f1'}, node_api_from: home_node_api))
            responses[[:read, 'files/f1']] = {'name' => 'my folder'}
            execute('packages', 'show', 'p1')
            expect(calls).to(include([:home, :read, 'files/f1']))
          end
        end

        describe '#wizard' do
          it 'creates a preset for a public link protected by a password' do
            app_url = 'https://org.example.com/public/files?token=<TOKEN>'
            allow(Aspera::Plugins::Aoc::Api).to(receive(:link_info).with(app_url).and_return({url: 'https://org.example.com/public/files', token: '<TOKEN>'}))
            public_api = instance_double(Rest::Client)
            allow(public_api).to(receive(:read).with('env/url_token_check', {token: '<TOKEN>'}).and_return({'password_protected' => true}))
            allow(Rest::Client).to(receive(:new).with(base_url: 'https://org.example.com/api/v1').and_return(public_api))
            expect(plugin('--password=<PASSWORD>').wizard(nil, app_url)).to(eq({
              preset_value: {link: app_url, password: '<PASSWORD>'},
              preset_ids:   [],
              test_args:    'organization'
            }))
          end
        end

        describe 'API from options' do
          let(:transfer) { double('transfer') }
          let(:callbacks) { [] }

          before do
            allow(aoc_api).to(receive(:ws_ids).and_return({id: nil, name: nil}))
            allow(Aspera::Plugins::Aoc::Api).to(receive(:new).and_return(aoc_api))
            allow(transfer).to(receive(:httpgw_url_cb=)) { |callback| callbacks.push(callback) }
          end

          it 'selects the workspace by name or identifier' do
            execute('user', 'workspaces', 'current', '--url=https://org.example.com', '--workspace=%name:my ws', transfer: transfer, stub_aoc: false)
            expect(aoc_api.ws_ids[:name]).to(eq('my ws'))
            execute('user', 'workspaces', 'current', '--url=https://org.example.com', '--workspace=%id:12', transfer: transfer, stub_aoc: false)
            expect(aoc_api.ws_ids[:id]).to(eq('12'))
            expect { execute('user', 'workspaces', 'current', '--url=https://org.example.com', '--workspace=%foo:x', transfer: transfer, stub_aoc: false) }.to(raise_error(/workspace selector/))
          end

          it 'gets the HTTP Gateway URL from the organization' do
            execute('user', 'workspaces', 'current', '--url=https://org.example.com', transfer: transfer, stub_aoc: false)
            responses[[:read, 'organization']] = {'http_gateway_enabled' => true, 'http_gateway_server_url' => 'https://gw.example.com'}
            expect(callbacks.last.call).to(eq('https://gw.example.com'))
            responses[[:read, 'organization']] = {'http_gateway_enabled' => false}
            expect(callbacks.last.call).to(be_nil)
          end
        end
      end
    end
  end
end
