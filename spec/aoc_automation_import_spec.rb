# frozen_string_literal: true

# Unit tests for the import of an AoC Automation workflow — no server needed.

require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/plugins/aoc'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Aoc) do
        # Fake Automation API: records calls and enforces the rule of the real API,
        # an action is accepted only if its step is already in the `step_order` of the workflow.
        let(:api_class) do
          Class.new do
            attr_reader :calls, :workflow

            def initialize(fail_on_action: nil)
              @calls = []
              @fail_on_action = fail_on_action
              @id = 100
              @workflow = {'id' => '1', 'step_order' => []}
              @steps = {}
              @actions = {}
            end

            def create(resource, body)
              @calls << [:create, resource, body]
              case resource
              when 'workflows' then @workflow.merge!(body)
              when 'steps' then @steps[next_id] = body.merge('id' => @id.to_s, 'action_order' => [])
              when 'actions'
                raise('Step for this action does not belong to a workflow') unless @workflow['step_order'].include?(body['step_id'])
                raise('rejected action') if @fail_on_action && body['type'] == @fail_on_action
                @actions[next_id] = body.merge('id' => @id.to_s)
              end
            end

            def update(resource, body)
              @calls << [:update, resource, body]
              kind, id = resource.split('/')
              case kind
              when 'workflows' then @workflow.merge!(body)
              when 'steps' then @steps.values.find { |s| s['id'] == id }.merge!(body)
              end
            end

            def delete(resource)
              @calls << [:delete, resource]
            end

            def read(resource)
              kind, id = resource.split('/')
              case kind
              when 'workflows' then @workflow
              when 'steps' then @steps.values.find { |s| s['id'] == id }
              when 'actions' then @actions.values.find { |a| a['id'] == id }
              end
            end

            private

            def next_id
              @id += 1
            end
          end
        end

        let(:manifest) do
          {
            'name'  => 'wf',
            'steps' => [
              {'ref_id' => 's1', 'name' => 'Trigger', 'actions' => [{'ref_id' => 'a1', 'type' => 'manual', 'data' => {}}]},
              {
                'ref_id' => 's2', 'name' => 'Next', 'actions' => [
                  {
                    'ref_id' => 'a2', 'type' => 'email_notification',
                    'data'   => {'message' => 'Got {{{step_id_s1.action_id_a1.filename}}}', 'substitutions' => [{'template' => '{{{step_id_s1.action_id_a1.filename}}}'}]}
                  }
                ]
              }
            ]
          }
        end

        # @param api [Object] fake Automation API
        # @return [Aoc] plugin that uses the fake API
        def plugin(api)
          context = Context.new
          context.man_header = false
          context.options = Parser.new('test', [])
          instance = described_class.new(context: context)
          instance.instance_variable_set(:@automation_api, api)
          instance
        end

        describe '#workflow_import_data' do
          it 'adds each step to the workflow before creating its actions' do
            api = api_class.new
            plugin(api).send(:workflow_import_data, manifest)
            expect(api.workflow['step_order']).to(eq(%w[101 103]))
          end

          it 'replaces references in all strings of the action data, not only in substitution templates' do
            api = api_class.new
            plugin(api).send(:workflow_import_data, manifest)
            data = api.calls.reverse.find { |c| c[0] == :create && c[1] == 'actions' }[2]['data']
            expect(data['message']).to(eq('Got {{{step_id_101.action_id_102.filename}}}'))
            expect(data['substitutions'].first['template']).to(eq('{{{step_id_101.action_id_102.filename}}}'))
          end

          it 'deletes the partial workflow when a call fails, and raises the error' do
            api = api_class.new(fail_on_action: 'email_notification')
            expect { plugin(api).send(:workflow_import_data, manifest) }.to(raise_error(RuntimeError, 'rejected action'))
            expect(api.calls.last).to(eq([:delete, 'workflows/1']))
          end
        end

        describe '#remap_references' do
          let(:remap) { ->(data, steps, actions) { plugin(nil).send(:remap_references, data, steps, actions) } }

          it 'replaces identifiers once, even if a new identifier is also an old reference' do
            result = remap.call('{{{step_id_1.action_id_2.out}}}', {'1' => '2'}, {'2' => '1'})
            expect(result).to(eq('{{{step_id_2.action_id_1.out}}}'))
          end

          it 'keeps a reference to an unknown step or action' do
            expect(remap.call('step_id_x.action_id_y', {}, {})).to(eq('step_id_x.action_id_y'))
          end

          it 'does not modify its input and leaves non-string values unchanged' do
            data = {'a' => [{'b' => 'step_id_1.action_id_2'}], 'n' => 3, 'f' => nil}
            copy = Marshal.load(Marshal.dump(data))
            expect(remap.call(data, {'1' => '9'}, {'2' => '8'})).to(eq({'a' => [{'b' => 'step_id_9.action_id_8'}], 'n' => 3, 'f' => nil}))
            expect(data).to(eq(copy))
          end
        end
      end
    end
  end
end
