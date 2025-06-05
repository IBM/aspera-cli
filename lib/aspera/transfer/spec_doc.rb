# frozen_string_literal: true

require 'aspera/agent/base'

module Aspera
  module Transfer
    # translate transfer specification to ascp parameter list
    class SpecDoc
      CONVERT_TAGS = %w[x-cli-convert x-cli-enum-convert].freeze
      private_constant :CONVERT_TAGS
      class << self
        # first letter of agent name symbol
        def agent_to_short(agent_sym)
          agent_sym.to_sym.eql?(:direct) ? :a : agent_sym.to_s[0].to_sym
        end

        # @columns formatter [Cli::Formatter] formatter to use, methods: special_format, check_row
        # @columns &block modify parameter info if needed
        # @return a table suitable to display in manual
        def man_table(formatter, cli: true)
          col_local = agent_to_short(:direct)
          Spec::SCHEMA['properties'].filter_map do |name, properties|
            # manual table
            columns = {
              name:        name,
              type:        properties['type'],
              description: []
            }
            # replace "back solidus" HTML entity with its text value and split lines
            columns[:description].concat(properties['description'].gsub('&bsol;', '\\').split("\n")) if properties.key?('description')
            columns[:description].unshift("DEPRECATED: #{properties['x-deprecation']}") if properties.key?('x-deprecation')
            # add flags for supported agents in doc
            AGENT_LIST.each do |agent_info|
              columns[agent_info.last] = Cli::Formatter.tick(properties['x-agents'].nil? || properties['x-agents'].include?(agent_info.first.to_s))
            end
            columns[col_local] = Cli::Formatter.tick(true) if properties['x-cli-option']
            # only keep lines that are usable in supported agents
            next false if AGENT_LIST.map(&:last).inject(true){ |memory, agent_short_sym| memory && columns[agent_short_sym].empty?}
            columns[:description].push("Allowed values: #{properties['enum'].join(', ')}") if properties.key?('enum')
            cli_option =
              if properties['x-cli-switch']
                properties['x-cli-option']
              elsif properties['x-cli-special']
                formatter.special_format('special')
              elsif properties['x-cli-option']
                arg_type = properties.key?('enum') ? '{enum}' : "{#{properties['type']}}"
                arg_type += "|{#{properties['x-type']}}" if properties.key?('x-type')
                conversion_tag = CONVERT_TAGS.any?{ |k| properties.key?(k)} ? '(conversion)' : ''
                sep = properties['x-cli-option'].start_with?('--') ? '=' : ' '
                "#{properties['x-cli-option']}#{sep}#{conversion_tag}#{arg_type}"
              end
            cli_option = 'env:' + properties['x-cli-envvar'] if properties.key?('x-cli-envvar')
            columns[:description].push("(#{cli_option})") if cli && !cli_option.to_s.empty?
            formatter.check_row(columns)
          end.sort_by{ |i| i[:name]}
        end
      end
      # Agents shown in manual for parameters (sub list)
      AGENT_LIST = Agent::Base.agent_list.map do |agent_sym|
        [agent_sym, agent_sym.to_s.capitalize, agent_to_short(agent_sym)]
      end.sort_by(&:last).freeze
      TABLE_COLUMNS = (%i[name type] + AGENT_LIST.map(&:last) + %i[description]).freeze
    end
  end
end
