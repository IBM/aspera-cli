# frozen_string_literal: true

require 'aspera/cli/runner'

module Aspera
  module Cli
    RSpec.describe(Runner) do
      describe '#schema_help_lines' do
        it 'renders the properties of a Hash argument schema' do
          argument = ArgumentSpec.new(
            name: :mcp_options,
            type: [Hash],
            schema: 'opts:components.schemas.McpServerOptions'
          )

          lines = Runner.new([]).send(:schema_help_lines, argument)

          output = lines.join("\n")
          expect(output).to(include('| transport                    | String'))
          expect(output).to(include('Allowed values: stdio, http.'))
        end
      end
    end
  end
end
