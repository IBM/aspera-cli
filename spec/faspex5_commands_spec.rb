# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Cli::Plugins::Faspex5: commands with an API double — no Faspex server needed.

require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/plugins/faspex5'
require_relative '../lib/aspera/cli/runner'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Faspex5) do
        # Calls received by the API double: [method, path, *args]
        let(:calls) { [] }
        # Response of the API double, by [method, path], default: empty Hash
        let(:responses) { {} }
        let(:progress_bar) { double('progress', event: nil) }

        let(:api) do
          api = instance_double(Api::Faspex, pub_link_context: nil)
          %i[read create update delete].each do |method|
            allow(api).to(receive(method)) do |path, *args|
              calls.push([method, path, *args])
              response = responses.fetch([method, path]) { {} }
              response.is_a?(Proc) ? response.call : response
            end
          end
          allow(api).to(receive(:list_entities_limit_offset_total_count)) do |**kwargs|
            calls.push([:list, kwargs])
            [[{'id' => 'f1'}], 1]
          end
          allow(api).to(receive(:lookup_entity_by_field)) do |**kwargs|
            calls.push([:lookup, kwargs])
            {'id' => "id_of_#{kwargs[:value]}", 'user_id' => "user_id_of_#{kwargs[:value]}"}
          end
          api
        end

        # @param argv [Array<String>] command line
        # @return [Result::Base] command result
        def execute(*argv)
          context = Context.new
          context.man_header = false
          context.formatter = double(display_status: nil)
          context.progress_bar = progress_bar
          context.options = Parser.new('test', argv)
          instance = described_class.new(context: context)
          api_double = api
          instance.define_singleton_method(:api_v5) { api_double }
          instance.define_singleton_method(:sleep) { |_| nil }
          instance.execute_action
        end

        describe 'admin' do
          it 'deletes the SMTP configuration' do
            expect(execute('admin', 'smtp', 'delete').data).to(eq('SMTP configuration deleted'))
            expect(calls).to(eq([[:delete, 'configuration/smtp']]))
          end

          it 'sends a password reset email to an account' do
            expect(execute('admin', 'accounts', 'reset_password', 'a1').data).to(eq('password reset, user shall check email'))
            expect(calls).to(eq([[:create, 'accounts/a1/reset_password', {}]]))
          end

          it 'lists the next files to process' do
            expect(execute('admin', 'file_processing', 'next').data).to(eq([{'id' => 'f1'}]))
            expect(calls).to(eq([[:list, {entity: 'file_processing', operation: 'POST', items_key: 'files'}]]))
          end

          it 'modifies a member of a shared inbox' do
            expect(execute('admin', 'shared_inboxes', 'members', 's1', 'modify', '%name:john', '@json:{"access":"standard"}').data).to(eq('modified'))
            expect(calls.last).to(eq([:update, 'shared_inboxes/s1/members/user_id_of_john', {'access' => 'standard'}]))
          end

          it 'finds a custom access user of a shared folder by name' do
            execute('admin', 'nodes', 'shared_folders', 'n1', 'user', 'sf1', 'show', '%name:john')
            expect(calls.first).to(eq([:lookup, {entity: 'nodes/n1/shared_folders/sf1/custom_access_users', items_key: 'users', field: 'name', value: 'john'}]))
            expect(calls.last).to(eq([:read, 'nodes/n1/shared_folders/sf1/custom_access_users/id_of_john']))
          end
        end

        describe 'packages' do
          it 'shows the file processing status of a package' do
            expect(execute('packages', 'file_processing', 'p1').data).to(eq([{'id' => 'f1'}]))
            expect(calls).to(eq([[:list, {entity: 'packages/p1/file_statuses', items_key: 'files'}]]))
          end

          it 'waits for the status of a package and shows progress' do
            statuses = [
              {'upload_status' => 'submitted'},
              {'upload_status' => 'transferring', 'bytes_total' => '10'},
              {'upload_status' => 'transferring', 'bytes_written' => '5'},
              {'upload_status' => 'completed'}
            ]
            responses[[:read, 'packages/p1/upload_details']] = -> { statuses.shift }
            expect(execute('packages', 'status', 'p1', '@json:["completed"]').data).to(eq({'upload_status' => 'completed', 'id' => 'p1'}))
            expect(progress_bar).to(have_received(:event).with(:sessions_init, session_id: nil, info: 'submitted'))
            expect(progress_bar).to(have_received(:event).with(:session_size, session_id: 'p1', info: 10))
            expect(progress_bar).to(have_received(:event).with(:transfer, session_id: 'p1', info: 5))
            expect(progress_bar).to(have_received(:event).with(:end, info: true))
          end
        end

        describe 'browse' do
          let(:browse_calls) { [] }

          # @param pages [Array<Array(Hash, Hash)>] body and headers of each response
          def pages(*pages)
            allow(api).to(receive(:call)) do |**kwargs|
              # copy: the query is modified between calls
              browse_calls.push({subpath: kwargs[:subpath], query: kwargs[:query].dup})
              pages.shift
            end
          end

          it 'browses pages with the iteration token' do
            pages(
              [{'items' => [{'path' => '/a'}]}, {Api::Faspex::HEADER_X_NEXT_ITER_TOKEN => 'next'}],
              [{'items' => [{'path' => '/b'}]}, {}]
            )
            expect(execute('admin', 'nodes', 'browse', 'n1', '/').data).to(eq([{'path' => '/a'}, {'path' => '/b'}]))
            expect(browse_calls.map { |call| call[:query] }).to(eq([{'per_page' => 500}, {'per_page' => 500, 'iteration_token' => 'next'}]))
            expect(browse_calls.first[:subpath]).to(eq('nodes/n1/browse/page'))
          end

          it 'browses with offset and limit without paging' do
            pages(
              [{'items' => [{'path' => '/a'}], 'item_count' => 1, 'total_count' => 1}, {}],
              [{'items' => [], 'item_count' => 0}, {}]
            )
            result = execute('admin', 'nodes', 'browse', 'n1', '/', '--query=@json:{"paging":false}')
            expect(result.data).to(eq([{'path' => '/a'}]))
            expect(result.total).to(eq(1))
            expect(browse_calls.map { |call| call[:query] }).to(eq([{'offset' => 0, 'limit' => 500}, {'offset' => 1, 'limit' => 500}]))
          end
        end
      end
    end
  end
end
