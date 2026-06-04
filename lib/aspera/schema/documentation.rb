# frozen_string_literal: true

require 'aspera/agent/factory'
require 'aspera/markdown'

module Aspera
  module Schema
    # Generate documentation from Schema, for Transfer Spec, or async Conf spec
    class Documentation
      # @param formatter [Cli::Formatter] Formatter instance with methods: markdown_text, tick, check_row
      # @param schema [Reader]
      # @param include_option [Boolean] `true`: include CLI options (switches, env vars) in descriptions
      # @param agent_columns  [Boolean] `true`: add separate columns for each transfer agent compatibility
      # @param code_highlight [Boolean] `true`: format name and type as code
      def initialize(formatter, schema, include_option: false, agent_columns: false, code_highlight: false)
        @formatter = formatter
        @schema = schema
        @include_option = include_option
        @agent_columns = agent_columns
        @code_highlight = code_highlight
        @columns = %i[name type description]
        @columns.insert(-2, *Agent::Factory::ALL.values.map{ |i| i[:short]}.sort) if @agent_columns
        # @type [Array<Hash<Symbol,String>>]
        @rows = []
      end

      def rows
        @rows.sort_by{ |i| i[:name]}
      end

      # @return [Array<String>]
      def columns
        @columns.map(&:to_s)
      end

      # First row is the titles
      # @return [Array<Array<String>>]
      def table
        [@columns.map(&:to_s)] + @rows.sort_by{ |i| i[:name]}.map{ |row| @columns.map{ |field| row[field]}}
      end

      # Generate a documentation table from a JSON schema for transfer specifications
      #
      # Recursively processes a JSON schema to create a formatted table for manual documentation.
      # Handles nested objects, arrays, and extracts metadata (descriptions, types, enums, deprecations).
      #
      # @param schema [Reader] The JSON schema to process
      # @return [Documentation]
      def build(schema = nil)
        code = @code_highlight ? ->(c){"`#{c}`"} : ->(c){c}
        schema ||= @schema
        schema.each_property do |property_schema, _name, property_full_name|
          node = property_schema.current
          # Manual table
          item = {
            name:        code.call(property_full_name),
            type:        code.call(node['type']),
            description: []
          }
          # Render Markdown formatting and split lines
          item[:description] =
            node['description']
              .gsub(Markdown::FORMATS){@formatter.markdown_text(Regexp.last_match)}
              .split("\n") if node.key?('description')
          item[:description].unshift("DEPRECATED: #{node['x-deprecation']}") if node.key?('x-deprecation')
          # Add flags for supported agents in doc
          agents = []
          Agent::Factory::ALL.each_key do |sym|
            agents.push(sym) if node['x-agents'].nil? || node['x-agents'].include?(sym.to_s)
          end
          Aspera.assert(agents.include?(:direct)){"#{name}: x-cli-option requires agent direct (or nil)"} if node['x-cli-option']
          if @agent_columns
            Agent::Factory::ALL.each do |sym, names|
              item[names[:short]] = @formatter.tick(agents.include?(sym))
            end
          else
            item[:description].push("(#{agents.map{ |i| Agent::Factory::ALL[i][:short].to_s.upcase}.sort.join(', ')})") unless agents.length.eql?(Agent::Factory::ALL.length)
          end
          # Only keep lines that are usable in supported agents
          next false if agents.empty?
          item[:description].push("Allowed values: #{node['enum'].map{ |v| @formatter.markdown_text("`#{v}`")}.join(', ')}.") if node.key?('enum')
          item[:description].push("Default: #{code.call(node['default'])}.") if node.key?('default')
          if @include_option
            envvar_prefix = ''
            cli_option =
              if node.key?('x-cli-envvar')
                envvar_prefix = 'env:'
                node['x-cli-envvar']
              elsif node['x-cli-switch']
                node['x-cli-option']
              elsif node['x-cli-option']
                arg_type = node.key?('enum') ? '{enum}' : "{#{[node['type']].flatten.join('|')}}"
                # conversion_tag = node['x-cli-convert']
                conversion_tag = node.key?('x-cli-convert') ? 'conversion' : nil
                sep = node['x-cli-option'].start_with?('--') ? '=' : ' '
                "#{node['x-cli-option']}#{sep}#{"(#{conversion_tag})" if conversion_tag}#{arg_type}"
              end
            short = node.key?('x-cli-short') ? "(#{node['x-cli-short']})" : nil
            item[:description].push("(#{'special:' if node['x-cli-special']}#{envvar_prefix}#{@formatter.markdown_text("`#{cli_option}`")})#{short}") if cli_option
          end
          @rows.push(@formatter.check_row(item))
        end
        self
      end
    end
  end
end
