# frozen_string_literal: true

require 'aspera/cli/runner'

module Aspera
  module Cli
    RSpec.describe(Runner) do
      describe '#schema_help_lines' do
        # Fixed rendering, whatever the terminal running the tests: no colors, ASCII borders, no wrapping
        around do |example|
          colors = Rainbow.enabled
          Rainbow.enabled = false
          example.run
        ensure
          Rainbow.enabled = colors
        end

        before do
          allow(Environment).to(receive_messages(terminal_supports_unicode?: false, terminal_columns: nil))
        end

        it 'renders the properties of a Hash argument schema' do
          argument = ArgumentSpec.new(
            name: :mcp_options,
            type: [Hash],
            schema: 'opts:components.schemas.McpServerOptions'
          )

          lines = Runner.new([]).send(:schema_help_lines, argument)

          output = lines.join("\n")
          expect(output).to(include('| transport '))
          expect(output).to(include('Allowed values: '))
          expect(output).to(include('stdio'))
        end

        it 'renders the title of variants without discriminant' do
          argument = ArgumentSpec.new(
            name: :action,
            type: [Hash],
            schema: Schema::Registry.req_body(Schema::Registry::AUTOMATION, 'actions.post')
          )

          output = Runner.new([]).send(:schema_help_lines, argument).join("\n")
          expect(output).to(include('| Creates a new action to send a file or folder '))
          expect(output).to(include('| Creates a new action that calls an API '))
          expect(output).not_to(include('&nbsp;'))
        end
      end
    end
  end
end
