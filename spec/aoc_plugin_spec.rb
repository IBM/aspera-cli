# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Cli::Plugins::Aoc: package folders, automation guide and jobs — no AoC server needed.

require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/plugins/aoc'
require 'tmpdir'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Aoc) do
        describe '.unique_folder' do
          let(:package) { {'id' => 'p1', 'name' => 'my package'} }

          around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

          def folder(destination = 'dest', **kwargs) = described_class.unique_folder(package, destination, **kwargs)

          it 'is named after one field' do
            expect(folder(fld: ['id'])).to(eq('dest/p1'))
          end

          it 'adds a sequence number when the folder exists' do
            expect(folder('.', fld: ['id'], seq: true)).to(eq('./p1.1'))
            Dir.mkdir('p1')
            expect(folder('.', fld: ['id'], seq: true, opt: true)).to(eq('./p1.1'))
          end

          it 'is named <name>.<id> with two fields' do
            expect(folder(fld: %w[name id])).to(eq('dest/my package.p1'))
          end

          it 'detects existing folders in the destination folder' do
            Dir.mkdir('dest')
            Dir.mkdir('dest/p1')
            expect(folder(fld: ['id'], seq: true, opt: true)).to(eq('dest/p1.1'))
          end
        end

        context 'with a command line' do
          # @param argv [Array<String>] command line
          # @param automation_api [Object, nil] Automation API, set by `setup_automation_api`
          def execute(*argv, automation_api: nil)
            context = Context.new
            context.man_header = false
            context.options = Parser.new('test', argv)
            instance = described_class.new(context: context)
            instance.define_singleton_method(:setup_automation_api) do |**|
              @automation_api = automation_api
              {}
            end
            instance.execute_action
          end

          describe 'automation guide' do
            let(:guide) { "# Guide\n\nIntro\n\n## Steps\n\nStep text\n\n### Detail\n\nMore\n" }

            before { allow(UriReader).to(receive(:read_first).and_return(guide)) }

            it 'lists sections up to a level' do
              expect(execute('automation', 'guide', 'toc', '2').data.map { |item| item['anchor'] }).to(eq(%w[guide steps]))
            end

            it 'displays the guide and a section' do
              expect(execute('automation', 'guide', 'full').data).to(eq(guide))
              expect(execute('automation', 'guide', 'section', 'steps').data).to(include('Step text', 'More'))
              expect { execute('automation', 'guide', 'section', 'none') }.to(raise_error(Cli::Error, /Section not found: none/))
            end
          end

          describe 'automation instances show' do
            let(:api) { instance_double(Rest::Client) }
            let(:queries) { [] }

            # @param pages [Array<Array<Hash>>] jobs of each page
            def pages(*pages, total: 2000)
              allow(api).to(receive(:read).with('workflow_instances', anything)) do |_path, query|
                queries.push(query)
                {'workflow_instances' => pages.shift || [], 'total_count' => total}
              end
            end

            it 'browses pages to find a numeric identifier' do
              pages([{'id' => '1'}], [{'id' => '42', 'status' => 'done'}])
              expect(execute('automation', 'instances', 'show', '42', automation_api: api).data).to(eq({'id' => '42', 'status' => 'done'}))
              expect(queries.map { |query| query['offset'] }).to(eq([0, 1000]))
            end

            it 'searches a UUID in one call' do
              pages([])
              expect { execute('automation', 'instances', 'show', 'a-b', automation_api: api) }.to(raise_error(BadIdentifier))
              expect(queries).to(eq([{'limit' => 1000, 'offset' => 0, 'sort' => '-state_change_time', 'q' => 'a-b'}]))
            end
          end

          describe 'automation workflows' do
            let(:api) { instance_double(Rest::Client) }

            it 'lists actions in step order' do
              allow(api).to(receive(:read)) do |path|
                {
                  'workflows/w1' => {'step_order' => %w[s1 s2]},
                  'steps/s1'     => {'action_order' => ['a1']},
                  'steps/s2'     => {'action_order' => %w[a2 a3]}
                }.fetch(path) { {'id' => path.split('/').last} }
              end
              expect(execute('automation', 'workflows', 'action', 'w1', 'list', automation_api: api).data.map { |item| item['id'] }).to(eq(%w[a1 a2 a3]))
            end

            it 'warns if the partial workflow of a failed import cannot be deleted' do
              allow(api).to(receive(:create).with('workflows', anything).and_return({'id' => 'w1'}))
              allow(api).to(receive(:create).with('steps', anything).and_raise('step refused'))
              allow(api).to(receive(:delete).and_raise('delete refused'))
              warnings = []
              allow(Log.log).to(receive(:warn)) { |*args, &block| warnings.push(block ? block.call : args.first) }
              expect { execute('automation', 'workflows', 'import', '@json:{"steps":[{"name":"s"}]}', automation_api: api) }.to(raise_error('step refused'))
              expect(warnings).to(include('Could not delete partial workflow w1: delete refused'))
            end

            it 'duplicates with the default name' do
              allow(api).to(receive(:read).with('workflows/w1/default_copy_name').and_return({'default_copy_name' => 'w1 copy'}))
              allow(api).to(receive(:create).and_return({'id' => 'w2'}))
              expect(execute('automation', 'workflows', 'duplicate', 'w1', automation_api: api).data).to(eq({'id' => 'w2'}))
              expect(api).to(have_received(:create).with('workflows/w1/copy', {'name' => 'w1 copy'}))
            end
          end
        end
      end
    end
  end
end
