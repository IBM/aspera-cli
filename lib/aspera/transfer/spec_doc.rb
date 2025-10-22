# frozen_string_literal: true

require 'aspera/agent/factory'

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
          rows = []
          schema['properties'].each do |name, info|
            if info['type'].eql?('object') && info['properties']
              rows.concat(man_table(formatter, include_option: include_option, agent_columns: agent_columns, schema: info).last.map { |h| h.merge(name: "#{name}.#{h[:name]}") })
            end
            # manual table
            columns = {
              name:        name,
              type:        info['type'],
              description: []
            }
            # replace "back solidus" HTML entity with its text value, highlight keywords, and split lines
            columns[:description] =
              info['description']
                .gsub('&bsol;', '\\')
                .gsub(/`([a-z0-9_.+-]+)`/){formatter.keyword_highlight(Regexp.last_match(1))}
                .split("\n") if info.key?('description')
            columns[:description].unshift("DEPRECATED: #{info['x-deprecation']}") if info.key?('x-deprecation')
            # add flags for supported agents in doc
            agents = []
            AGENT_LIST.each do |agent_info|
              agents.push(agent_info.last) if info['x-agents'].nil? || info['x-agents'].include?(agent_info.first.to_s)
            end
            Aspera.assert(agents.include?(col_local)){"#{name}: x-cli-option requires agent direct (or nil)"} if info['x-cli-option']
            if agent_columns
              AGENT_LIST.each do |agent_info|
                columns[agent_info.last] = formatter.tick(agents.include?(agent_info.last))
              end
            else
              columns[:description].push("(#{agents.map(&:upcase).join(', ')})") unless agents.length.eql?(AGENT_LIST.length)
            end
            # only keep lines that are usable in supported agents
            next false if agents.empty?
            columns[:description].push("Allowed values: #{info['enum'].map{ |v| formatter.keyword_highlight(v)}.join(', ')}") if info.key?('enum')
            if include_option
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
              columns[:description].push("(#{'special:' if info['x-cli-special']}#{envvar_prefix}#{formatter.keyword_highlight(cli_option)})") if cli_option
            end
            rows.push(formatter.check_row(columns))
          end
          [cols, rows.sort_by{ |i| i[:name]}]
        end
      end
      # Agents shown in manual for parameters (sub list)
      AGENT_LIST = Agent::Factory.instance.list.map do |agent_sym|
        [agent_sym, agent_sym.to_s.capitalize, agent_to_short(agent_sym)]
      end.sort_by(&:last).freeze
    end
  end
end
