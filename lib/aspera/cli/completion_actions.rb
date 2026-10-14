# frozen_string_literal: true

require 'aspera/cli/info'
require 'aspera/cli/parser'
require 'aspera/cli/plugins/factory'
require 'aspera/cli/special_values'
require 'aspera/schema/documentation'
require 'aspera/schema/registry'

module Aspera
  module Cli
    # Mixin for Config plugin: shell completion scripts, and the words they propose
    module CompletionActions
      # Shells with a completion script in COMPLETION_FOLDER: shell => extension of script
      COMPLETION_SHELLS = {bash: 'bash', zsh: 'zsh', fish: 'fish', powershell: 'ps1'}.freeze
      COMPLETION_FOLDER = File.expand_path('completion', __dir__)
      # Completion of the word at cursor
      # @!attribute candidates [Array<Array(String, String)>] words, with their description (or `nil`)
      # @!attribute hint       [String, nil] displayed when a value is expected, but cannot be proposed (e.g. `<String>`)
      # @!attribute files      [Boolean] local files can be completed
      Completion = Struct.new(:candidates, :hint, :files, keyword_init: true)
      # Structure built with `@:` (see `Parser#args_as_extended`) being typed
      # @!attribute marker      [String]      end marker
      # @!attribute assignments [Integer]     number of assignments given
      # @!attribute option      [Option, nil] option token whose value is built, `nil` for a positional argument
      Collecting = Struct.new(:marker, :assignments, :option, keyword_init: true)
      # Value starting a structure built with `@:`: the optional text after `:` is the end marker
      REGEX_EXTEND_ARGS = /\A@:(.*)\z/
      # Maximum length of a hint listing the keys of a structure
      HINT_MAX_LENGTH = 72
      private_constant :COMPLETION_SHELLS, :COMPLETION_FOLDER, :Completion, :Collecting, :REGEX_EXTEND_ARGS, :HINT_MAX_LENGTH

      # List words that can follow the given words, one per line.
      # When a value is expected but cannot be proposed, its type is listed (e.g. `<String>`).
      # @param words [Array<String>, nil] words typed before the cursor, after the command name
      def action_completion_words(words: nil, **)
        completion = completion(Array(words), '')
        completion.candidates.each { |candidate| puts candidate.first }
        puts completion.hint unless completion.hint.nil?
        Process.exit(0)
      end

      # Complete the word at cursor, for completion scripts: candidates, one per line: `word`, or `word<TAB>description`,
      # not filtered by the word at cursor. Then a directive for the shell: `:files` (also complete local files),
      # `:hint <text>` (display text, nothing to insert), or `:`.
      # @param words [Array<String>, nil] words typed before the cursor, after the command name, then the word at cursor
      def action_completion_candidates(words: nil, **)
        words = Array(words)
        completion = completion(words[0..-2], words.last.to_s)
        completion.candidates.each { |word, description| puts description.nil? ? word : "#{word}\t#{description}" }
        directive =
          if completion.files then 'files'
          elsif completion.hint then "hint #{completion.hint}"
          end
        puts ":#{directive}"
        Process.exit(0)
      end

      private

      # @param words   [Array<String>] words typed before the cursor, after the command name
      # @param current [String]        word at cursor, up to the cursor
      # @return [Completion]
      def completion(words, current)
        words = completion_join_bash_split(words)
        # `--opt=value`: complete the value of the option, with this prefix
        prefix = current.start_with?(Option::PREFIX) && current.include?(Option::VALUE_SEP) ? current[0..current.index(Option::VALUE_SEP)] : ''
        words += [prefix] unless prefix.empty?
        plugin_class, positional, waiting, collecting = completion_context(words)
        return Completion.new(candidates: []) if positional.nil?
        result =
          if prefix.empty? && (keys = completion_option_keys(current))
            keys
          elsif prefix.empty? && current.start_with?('-')
            Completion.new(candidates: completion_options(options.declared_options.keys))
          elsif !waiting.nil?
            completion_option_values(waiting)
          elsif !collecting.nil?
            completion_collecting(collecting, plugin_class, positional)
          elsif plugin_class.nil?
            # Level 0: plugin names and global options
            Completion.new(candidates: Plugins::Factory.instance.plugin_list.map { |p| [p.to_s, completion_plugin_description(p)] } + completion_options(options.declared_options.keys))
          else
            completion_command(plugin_class, positional[1..])
          end
        result.candidates = result.candidates.map { |word, description| ["#{prefix}#{word}", description] }
        result
      end

      # @param words [Array<String>] words typed before the cursor
      # @return [Array(Class, Array<String>, Option, Collecting)] plugin class (`nil` at root), and result of `completion_split`;
      #   `[]` if the first positional word is not a plugin
      def completion_context(words)
        positional, waiting, collecting = completion_split(words)
        return [nil, positional, waiting, collecting] if positional.empty?
        plugin_sym = completion_plugin(positional.first)
        return [] if plugin_sym.nil?
        begin
          plugin_class = Plugins::Factory.instance.plugin_class(plugin_sym)
        rescue StandardError
          return []
        end
        plugin_class.declare_options(options)
        # Options of the plugin may take a value: split again
        [plugin_class, *completion_split(words)]
      end

      # As the runner: an exact name, else the unique plugin name starting with word
      # @param word [String] first positional word
      # @return [Symbol, nil] plugin designated by word
      def completion_plugin(word)
        plugins = Plugins::Factory.instance.plugin_list
        return word.to_sym if plugins.include?(word.to_sym)
        matching = plugins.select { |p| p.to_s.start_with?(word) }
        matching.first if matching.length.eql?(1)
      end

      # @param plugin_class [Class]         plugin
      # @param words        [Array<String>] positional words after the plugin name
      # @return [Completion] sub-commands, or next argument
      def completion_command(plugin_class, words)
        registry = plugin_class.command_registry
        path, given = registry.command_position(words.map(&:to_sym))
        return Completion.new(candidates: []) if path.nil?
        children = registry.children_of(path)
        next_argument = completion_next_argument(registry, path, given)
        return completion_argument(next_argument) unless next_argument.nil?
        # Source files of an upload follow the declared arguments
        return Completion.new(candidates: [], files: true) if children.empty? && registry[path]&.transfer_paths.eql?(:send)
        # Commands, each followed by its aliases, with the same description
        candidates = children.flat_map do |id, spec|
          description = completion_description(spec.description)
          [id, *Array(spec.aliases)].map { |name| [name.to_s, description] }
        end
        # Options of plugin only right after the plugin name
        candidates.concat(completion_options(plugin_class.option_sources.each_key.flat_map { |src| src.option_specs.keys }.uniq)) if words.empty?
        Completion.new(candidates: candidates)
      end

      # @param registry [CommandRegistry] registry of plugin
      # @param path     [Array<Symbol>]   command path
      # @param given    [Integer]         number of arguments given to the command
      # @return [ArgumentSpec, nil] argument expected after the given ones
      def completion_next_argument(registry, path, given)
        arguments = registry.arguments_at(path)
        return arguments[given] if given < arguments.length
        arguments.last if registry.children_of(path).empty? && arguments.last&.multiple
      end

      # In a structure built with `@:`: its end marker once an assignment is given, else the expected keys
      # @param collecting   [Collecting]    structure being typed
      # @param plugin_class [Class, nil]    plugin
      # @param positional   [Array<String>] positional words, the plugin name first
      # @return [Completion]
      def completion_collecting(collecting, plugin_class, positional)
        return Completion.new(candidates: [[collecting.marker, 'End of structure built with @:']]) if collecting.assignments.positive?
        schema =
          if collecting.option
            completion_option(collecting.option)&.schema
          elsif plugin_class
            # The positional argument built is the last positional word: `@:`
            registry = plugin_class.command_registry
            path, given = registry.command_position(positional[1..-2].map(&:to_sym))
            completion_next_argument(registry, path, given)&.schema unless path.nil?
          end
        Completion.new(candidates: [], hint: completion_hint('path=value', schema))
      end

      # Bash splits `--opt=value` in words `--opt`, `=` and `value`: join them back.
      # @param words [Array<String>] words typed before the cursor
      # @return [Array<String>] words, with options and their value joined
      def completion_join_bash_split(words)
        result = []
        join_next = false
        words.each do |word|
          if join_next
            result[-1] += word
            join_next = false
          elsif word.eql?(Option::VALUE_SEP) && result.last&.start_with?(Option::PREFIX) && !result.last.include?(Option::VALUE_SEP)
            result[-1] += word
            join_next = true
          else
            result.push(word)
          end
        end
        result
      end

      # Split words as the command line parser does: an option without inline value takes the next word as value,
      # unless it is a flag. An option not declared yet (e.g. of a plugin) takes a value.
      # A value `@:` (of option, or of positional argument) collects the next positional words, up to its end marker.
      # @param words [Array<String>] words typed before the cursor
      # @return [Array(Array<String>, Option, Collecting)] positional words, the last option if it is waiting for its value,
      #   and the structure built with `@:` if its end marker is not given
      def completion_split(words)
        positional = []
        waiting = nil
        collecting = nil
        stop = false
        words.each do |word|
          if !stop && word.eql?(Option::STOP)
            stop = true
            waiting = nil
          elsif !stop && Option.option?(word)
            tok = Option.parse(word)
            # `--opt=` at end of line (from bash split): value is being typed
            waiting = (tok.inline? && !tok.inline_value.empty?) || completion_option(tok)&.flag? ? nil : tok
            collecting = completion_collecting_start(tok.inline_value, tok) || collecting
          elsif waiting
            collecting = completion_collecting_start(word, waiting) || collecting
            waiting = nil
          elsif collecting
            # Assignment, or end marker
            collecting.assignments += 1
            collecting = nil if word.eql?(collecting.marker)
          else
            positional.push(word)
            collecting = completion_collecting_start(word, nil)
          end
        end
        [positional, waiting, collecting]
      end

      # @param value  [String, nil] value of option or argument
      # @param option [Option, nil] option token, `nil` for a positional argument
      # @return [Collecting, nil] structure started by the value, if it is `@:`
      def completion_collecting_start(value, option)
        match = REGEX_EXTEND_ARGS.match(value.to_s)
        return if match.nil?
        Collecting.new(marker: match[1].empty? ? SpecialValues::EOA : match[1], assignments: 0, option: option)
      end

      # @param tok [Option] option token
      # @return [OptionValue, nil] declared option designated by the token
      def completion_option(tok)
        return options.declared_options.values.find { |o| o.short.eql?(tok.short_char) } if tok.short_char
        options.declared_options[tok.name.to_sym]
      end

      # @param names [Array<Symbol>] names of declared options
      # @return [Array<Array(String, String)>] command line names of options, except deprecated ones, and their description
      def completion_options(names)
        names.filter_map do |name|
          option = options.declared_options[name]
          next if option.nil? || option.deprecation
          [Parser.option_name_to_line(name), completion_description(option.description)]
        end
      end

      # @param tok [Option] option token waiting for its value
      # @return [Completion] allowed values of the option, or its type as hint
      def completion_option_values(tok)
        option = completion_option(tok)
        return Completion.new(candidates: []) if option.nil?
        return completion_key_value(option.schema, tok.dot_path) unless tok.dot_path.nil?
        return Completion.new(candidates: option.values.map(&:to_s).uniq.map { |v| [v, nil] }) if option.values&.any?
        types = option.types&.reject { |t| t.eql?(NilClass) }
        Completion.new(candidates: [], hint: completion_hint(types&.any? ? types.map(&:name).join('|') : option.allowed_info || 'String', option.schema))
      end

      # Keys of an option with dotted notation, from its schema, e.g. `--ts.ta` gives `--ts.target_rate_kbps`
      # @param current [String] word at cursor
      # @return [Completion, nil] keys at the level of the word, `nil` if the word is not a dotted option
      def completion_option_keys(current)
        match = current.match(/\A--([^=.]+)\.([^=]*)\z/)
        return if match.nil?
        option = options.declared_options[Parser.option_line_to_name(match[1]).to_sym]
        parents = match[2].split(DotContainer::SEPARATOR, -1)[0..-2]
        candidates = completion_schema_rows(option&.schema).filter_map do |row|
          path = row['name'].split(DotContainer::SEPARATOR)
          next if row['name'].include?('[]') || !path[0..-2].eql?(parents)
          ["--#{match[1]}.#{row['name']}", completion_description(row['description']) || completion_type(row['type'])]
        end
        Completion.new(candidates: candidates)
      end

      # @param schema   [String, nil]   schema of structure
      # @param dot_path [Array<String>] key in structure
      # @return [Completion] allowed values of the key, or its type as hint
      def completion_key_value(schema, dot_path)
        row = completion_schema_rows(schema).find { |r| r['name'].eql?(dot_path.join(DotContainer::SEPARATOR)) }
        return Completion.new(candidates: []) if row.nil?
        return Completion.new(candidates: row['enum'].compact.map { |v| [v.to_s, nil] }) if row['enum']
        return Completion.new(candidates: [['true', nil], ['false', nil]]) if row['type'].eql?('boolean')
        Completion.new(candidates: [], hint: ["<#{completion_type(row['type'])}>", completion_description(row['description'])].compact.join(' '))
      end

      # @param type   [String]      expected type, e.g. `Hash`
      # @param schema [String, nil] schema of value
      # @return [String] type, followed by the top level keys of the schema, if any: required ones first, followed by `*`
      def completion_hint(type, schema)
        hint = "<#{type}>"
        top = completion_schema_rows(schema).reject { |r| r['name'].match?(/[.\[]/) }
        required, optional = top.partition { |r| r['required'] }
        names = required.map { |r| "#{r['name']}*" } + optional.map { |r| r['name'] }
        names.each_with_index do |name, index|
          separator = index.zero? ? ' ' : ', '
          return "#{hint}#{separator}…" if hint.length + separator.length + name.length > HINT_MAX_LENGTH
          hint = "#{hint}#{separator}#{name}"
        end
        hint
      end

      # @param schema [String, nil] name of schema in registry
      # @return [Array<Hash>] fields of the schema (see `Schema::Reader#to_rows`), empty if none
      def completion_schema_rows(schema)
        return [] if schema.nil?
        Schema::Registry.instance.reader(schema).to_rows
      rescue StandardError
        []
      end

      # @param type [String] JSON type(s) of a schema field, e.g. `integer` or `string, null`
      # @return [String] type, as displayed in help, e.g. `Integer`
      def completion_type(type)
        type.to_s.split(', ').reject { |t| t.eql?('null') }.map { |t| Schema::Documentation::JSON_TYPE_TO_DOC.fetch(t, t) }.join('|')
      end

      # @param arg_spec [ArgumentSpec] expected argument
      # @return [Completion] allowed values of the argument, or its type (and keys of its schema) as hint
      def completion_argument(arg_spec)
        return Completion.new(candidates: arg_spec.allowed.map { |v| [v.to_s, nil] }) if arg_spec.allowed
        type_str =
          case arg_spec.type
          when :identifier then 'identifier'
          when Array       then arg_spec.type.map(&:name).join('|')
          when Class       then arg_spec.type.name
          when nil         then 'String'
          else arg_spec.type.to_s
          end
        Completion.new(candidates: [], hint: completion_hint(type_str, arg_spec.schema))
      end

      # @param plugin_sym [Symbol] plugin name
      # @return [String, nil] name of the application of the plugin
      def completion_plugin_description(plugin_sym)
        Plugins::Factory.instance.plugin_class(plugin_sym).application_name
      rescue StandardError
        nil
      end

      # @param text [String, nil] description
      # @return [String, nil] first line, without final period, as displayed by the shell
      def completion_description(text)
        line = text.to_s.lines.first.to_s.strip.tr("\t", ' ').delete_suffix('.')
        line.empty? ? nil : line
      end

      # Display the completion script for the given shell.
      # Raw output, not formatted, so that it can be evaluated by the shell.
      # @param shell [Symbol] One of `COMPLETION_SHELLS`
      def completion_script(shell)
        $stdout.write(File.read(File.join(COMPLETION_FOLDER, "#{Info::CMD_NAME}.#{COMPLETION_SHELLS[shell]}")))
        Process.exit(0)
      end
    end
  end
end
