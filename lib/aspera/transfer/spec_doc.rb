# frozen_string_literal: true

require 'aspera/agent/factory'
require 'aspera/markdown'

module Aspera
  module Transfer
    # Generate documentation from Schema, for Transfer Spec, or async Conf spec
    class SpecDoc
      # @param formatter [Cli::Formatter] Formatter instance with methods: markdown_text, tick, check_row
      # @param include_option [Boolean]        `true`: include CLI options (switches, env vars) in descriptions
      # @param agent_columns  [Boolean]        `true`: add separate columns for each transfer agent compatibility
      def initialize(formatter, schema, include_option: false, agent_columns: false)
        @formatter = formatter
        @schema = schema
        @include_option = include_option
        @agent_columns = agent_columns
        @columns = %i[name type description]
        @columns.insert(-2, *Agent::Factory::ALL.values.map{ |i| i[:short]}.sort) if @agent_columns
        @rows = []
      end

      def rows
        @rows.sort_by{ |i| i[:name]}
      end

      def columns
        @columns.map(&:to_s)
      end

      # Generate a documentation table from a JSON schema for transfer specifications
      #
      # Recursively processes a JSON schema to create a formatted table for manual documentation.
      # Handles nested objects, arrays, and extracts metadata (descriptions, types, enums, deprecations).
      #
      # @param schema [Hash] The JSON schema to process
      # @return [nil]
      def build(schema = nil, prefix = '')
        schema ||= @schema
        schema['properties'].each do |name, info|
          build(info, "#{prefix}#{name}.") if info['type'].eql?('object') && info['properties']
          build(info['items'], "#{prefix}#{name}[].") if info['type'].eql?('array') && info['items'] && info['items']['properties']
          # Manual table
          item = {
            name:        name,
            type:        info['type'],
            description: []
          }
          # Render Markdown formatting and split lines
          item[:description] =
            info['description']
              .gsub(Markdown::FORMATS){@formatter.markdown_text(Regexp.last_match)}
              .split("\n") if info.key?('description')
          item[:description].unshift("DEPRECATED: #{info['x-deprecation']}") if info.key?('x-deprecation')
          # Add flags for supported agents in doc
          agents = []
          Agent::Factory::ALL.each_key do |sym|
            agents.push(sym) if info['x-agents'].nil? || info['x-agents'].include?(sym.to_s)
          end
          Aspera.assert(agents.include?(:direct)){"#{name}: x-cli-option requires agent direct (or nil)"} if info['x-cli-option']
          if @agent_columns
            Agent::Factory::ALL.each do |sym, names|
              item[names[:short]] = @formatter.tick(agents.include?(sym))
            end
          else
            item[:description].push("(#{agents.map{ |i| Agent::Factory::ALL[i][:short].to_s.upcase}.sort.join(', ')})") unless agents.length.eql?(Agent::Factory::ALL.length)
          end
          # Only keep lines that are usable in supported agents
          next false if agents.empty?
          item[:description].push("Allowed values: #{info['enum'].map{ |v| @formatter.markdown_text("`#{v}`")}.join(', ')}.") if info.key?('enum')
          item[:description].push("Default: #{info['default']}.") if info.key?('default')
          if @include_option
            envvar_prefix = ''
            cli_option =
              if info.key?('x-cli-envvar')
                envvar_prefix = 'env:'
                info['x-cli-envvar']
              elsif info['x-cli-switch']
                info['x-cli-option']
              elsif info['x-cli-option']
                arg_type = info.key?('enum') ? '{enum}' : "{#{[info['type']].flatten.join('|')}}"
                # conversion_tag = info['x-cli-convert']
                conversion_tag = info.key?('x-cli-convert') ? 'conversion' : nil
                sep = info['x-cli-option'].start_with?('--') ? '=' : ' '
                "#{info['x-cli-option']}#{sep}#{"(#{conversion_tag})" if conversion_tag}#{arg_type}"
              end
            short = info.key?('x-cli-short') ? "(#{info['x-cli-short']})" : nil
            item[:description].push("(#{'special:' if info['x-cli-special']}#{envvar_prefix}#{@formatter.markdown_text("`#{cli_option}`")})#{short}") if cli_option
          end
          @rows.push(@formatter.check_row(item))
        end
        self
      end
    end
  end
end
