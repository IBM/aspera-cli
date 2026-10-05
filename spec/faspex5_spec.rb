# frozen_string_literal: true

# Unit tests for Aspera::Cli::Plugins::Faspex5 — no server needed.

require 'aspera/cli/context'
require 'aspera/cli/parser'
require 'aspera/cli/plugins/faspex5'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Faspex5) do
        # @param argv [Array<String>] command line
        # @param link_context [Hash, nil] context of public link, or nil
        # @return [Faspex5] plugin with an API double
        def plugin(argv, link_context)
          context = Context.new
          context.man_header = false
          context.options = Parser.new('test', argv)
          instance = described_class.new(context: context)
          api = Struct.new(:pub_link_context).new(link_context)
          instance.define_singleton_method(:api_v5) { api }
          instance
        end

        describe '#persistency_user_id' do
          it 'is the username without public link' do
            expect(plugin(['--username=john'], nil).send(:persistency_user_id)).to(eq('john'))
          end

          it 'is specific to each public link, without username' do
            first = plugin([], {'passcode' => 'abc', 'package_id' => '12'}).send(:persistency_user_id)
            second = plugin([], {'passcode' => 'xyz', 'package_id' => '12'}).send(:persistency_user_id)
            expect(first).not_to(eq(second))
            expect(first).not_to(include('abc'))
          end
        end
      end
    end
  end
end
