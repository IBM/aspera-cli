# frozen_string_literal: true

require 'aspera/agent/base'

module Aspera
  module Transfer
    # translate transfer specification to ascp parameter list
    class SpecDoc
      class << self
        # first letter of agent name symbol
        def agent_to_short(agent_sym)
          agent_sym.to_sym.eql?(:direct) ? :a : agent_sym.to_s[0].to_sym
        end

        # @param formatter      [Cli::Formatter] Formatter to use, methods: special_format, check_row
        # @param include_option [Boolean]        `true` : include CLI options
        # @param agent_columns  [Boolean]        `true` : include agents columns
        # @param schema         [Hash]           The JSON spec
        # @return [Array] a table suitable to display in manual
        def man_table(formatter, include_option: false, agent_columns: true, schema: Spec::SCHEMA)
          col_local = agent_to_short(:direct)
          cols = %i[name type description]
          cols.insert(-2, *AGENT_LIST.map(&:last)) if agent_columns
          rows = schema['properties'].filter_map do |name, properties|
            # manual table
            columns = {
              name:        name,
              type:        properties['type'],
              description: []
            }
            # replace "back solidus" HTML entity with its text value, highlight keywords, and split lines
            columns[:description] =
              properties['description']
                .gsub('&bsol;', '\\')
                .gsub(/`([a-z0-9_.+-]+)`/){formatter.keyword_highlight(Regexp.last_match(1))}
                .split("\n") if properties.key?('description')
            columns[:description].unshift("DEPRECATED: #{properties['x-deprecation']}") if properties.key?('x-deprecation')
            # add flags for supported agents in doc
            agents = []
            AGENT_LIST.each do |agent_info|
              agents.push(agent_info.last) if properties['x-agents'].nil? || properties['x-agents'].include?(agent_info.first.to_s)
            end
            Aspera.assert(agents.include?(col_local)){"#{name}: x-cli-option requires agent direct (or nil)"} if properties['x-cli-option']
            if agent_columns
              AGENT_LIST.each do |agent_info|
                columns[agent_info.last] = formatter.tick(agents.include?(agent_info.last))
              end
            else
              columns[:description].push("(#{agents.map(&:upcase).join(', ')})") unless agents.length.eql?(AGENT_LIST.length)
            end
            # only keep lines that are usable in supported agents
            next false if agents.empty?
            columns[:description].push("Allowed values: #{properties['enum'].map{ |v| formatter.keyword_highlight(v)}.join(', ')}") if properties.key?('enum')
            if include_option
              envvar_prefix = ''
              cli_option =
                if properties.key?('x-cli-envvar')
                  envvar_prefix = 'env:'
                  properties['x-cli-envvar']
                elsif properties['x-cli-switch']
                  properties['x-cli-option']
                elsif properties['x-cli-option']
                  arg_type = properties.key?('enum') ? '{enum}' : "{#{[properties['type']].flatten.join('|')}}"
                  # conversion_tag = properties['x-cli-convert']
                  conversion_tag = properties.key?('x-cli-convert') ? 'conversion' : nil
                  sep = properties['x-cli-option'].start_with?('--') ? '=' : ' '
                  "#{properties['x-cli-option']}#{sep}#{"(#{conversion_tag})" if conversion_tag}#{arg_type}"
                end
              columns[:description].push("(#{'special:' if properties['x-cli-special']}#{envvar_prefix}#{formatter.keyword_highlight(cli_option)})") if cli_option
            end
            formatter.check_row(columns)
          end.sort_by{ |i| i[:name]}
          [cols, rows]
        end
      end
      # Agents shown in manual for parameters (sub list)
      AGENT_LIST = Agent::Base.agent_list.map do |agent_sym|
        [agent_sym, agent_sym.to_s.capitalize, agent_to_short(agent_sym)]
      end.sort_by(&:last).freeze
    end
  end
end
