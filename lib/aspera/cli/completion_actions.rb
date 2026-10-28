# frozen_string_literal: true

require 'aspera/cli/info'
require 'aspera/cli/parser'
require 'aspera/cli/plugins/factory'
require 'aspera/cli/preset_manager'
require 'aspera/cli/special_values'
require 'aspera/environment'
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
      # @!attribute candidates   [Array<Array(String, String)>] words, with their description (or `nil`)
      # @!attribute hint         [String, nil] displayed when a value is expected, but cannot be proposed (e.g. `<String>`)
      # @!attribute files        [Symbol, nil] local paths are completed: `:file` (files and folders) or `:folder`
      # @!attribute files_prefix [String, nil] beginning of the word at cursor that is not part of the path (e.g. `@file:`)
      Completion = Struct.new(:candidates, :hint, :files, :files_prefix, keyword_init: true) do
        # Completion of a value that follows the given text in the word at cursor
        # @param prefix [String] beginning of the word at cursor
        # @return [self]
        def prefixed(prefix)
          self.candidates = candidates.map { |word, description| ["#{prefix}#{word}", description] }
          self.files_prefix = "#{prefix}#{files_prefix}"
          self
        end
      end
      # Structure built with `@:` (see `Parser#args_as_extended`) being typed
      # @!attribute marker   [String]        end marker
      # @!attribute assigned [Array<String>] paths assigned
      # @!attribute option   [Option, nil]   option token whose value is built, `nil` for a positional argument
      Collecting = Struct.new(:marker, :assigned, :option, keyword_init: true)
      # Command reached by the positional words
      # @!attribute registry  [CommandRegistry, nil] registry of plugin, `nil` at root
      # @!attribute path      [Array<Symbol>, nil]   command path, `nil` if words are not a command
      # @!attribute arguments [Array<String>]        arguments given to the command
      Position = Struct.new(:registry, :path, :arguments, keyword_init: true) do
        # @return [CommandSpec, nil] command reached
        def spec = path && registry[path]
      end
      # Value starting a structure built with `@:`: the optional text after `:` is the end marker
      REGEX_EXTEND_ARGS = /\A@:(.*)\z/
      # Extended value modifier at the beginning of a value, e.g. `@file:`
      REGEX_MODIFIER = /\A@([a-z0-9_]*):/
      # Beginning of extended value
      MARKER_MODIFIER = '@'
      # Modifiers whose value is usually given by another modifier, e.g. `@json:@file:`
      MODIFIERS_DECODING = %i[base64 csvt json lines list re ruby s yaml zlib].freeze
      # Modifiers whose value is not evaluated
      MODIFIERS_LITERAL = %i[val extend].freeze
      # Modes of `@stdin:`
      STDIN_MODES = ['', 'bin', 'chomp'].freeze
      # End of sentence in a description: a period, not of `e.g.` or `i.e.`, followed by a word not in lower case
      REGEX_SENTENCE_END = /(?<!\be\.g|\bi\.e)\.\s+(?=[^a-z])/
      # Maximum length of a hint listing the keys of a structure
      HINT_MAX_LENGTH = 72
      private_constant :COMPLETION_SHELLS, :COMPLETION_FOLDER, :Completion, :Collecting, :Position, :REGEX_EXTEND_ARGS, :REGEX_MODIFIER,
        :MARKER_MODIFIER, :MODIFIERS_DECODING, :MODIFIERS_LITERAL, :STDIN_MODES, :REGEX_SENTENCE_END, :HINT_MAX_LENGTH

      # List words that can follow the given words, one per line.
      # When a value is expected but cannot be proposed, its type is listed (e.g. `<String>`), or `<file>` (or `<folder>`) for a local path.
      # @param words [Array<String>, nil] words typed before the cursor, after the command name
      def action_completion_words(words: nil, **)
        completion = completion(Array(words), '')
        completion.candidates.each { |candidate| puts candidate.first }
        puts completion.hint unless completion.hint.nil?
        puts "<#{completion.files}>" unless completion.files.nil?
        Process.exit(0)
      end

      # Complete the word at cursor, for completion scripts: candidates, one per line: `word`, or `word<TAB>description`,
      # not filtered by the word at cursor. Then a directive for the shell: `:files` or `:folders` (complete local paths),
      # followed by a space and the beginning of the word at cursor that is not part of the path, if any (e.g. `--key=@file:`),
      # `:hint <text>` (display text, nothing to insert), or `:`.
      # @param words [Array<String>, nil] words typed before the cursor, after the command name, then the word at cursor
      def action_completion_candidates(words: nil, **)
        words = Array(words)
        completion = completion(words[0..-2], words.last.to_s)
        completion.candidates.each { |word, description| puts description.nil? ? word : "#{word}\t#{description}" }
        directive =
          if completion.files then [completion.files.eql?(:folder) ? 'folders' : 'files', completion.files_prefix].reject { |w| w.to_s.empty? }.join(' ')
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
        position = completion_position(plugin_class, positional)
        value = current[prefix.length..]
        result =
          if prefix.empty? && (keys = completion_option_keys(current, position))
            keys
          elsif prefix.empty? && current.start_with?('-')
            Completion.new(candidates: completion_options(options.declared_options.keys))
          elsif !waiting.nil?
            completion_option_values(waiting, value, position)
          elsif !collecting.nil?
            completion_collecting(collecting, value, plugin_class, positional, position)
          elsif plugin_class.nil?
            # Level 0: plugin names and global options
            Completion.new(candidates: Plugins::Factory.instance.plugin_list.map { |p| [p.to_s, completion_plugin_description(p)] } + completion_options(options.declared_options.keys))
          else
            completion_command(plugin_class, positional[1..], value, position)
          end
        result.prefixed(prefix)
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

      # @param plugin_class [Class, nil]    plugin
      # @param positional   [Array<String>] positional words, the plugin name first
      # @return [Position] command reached by the positional words
      def completion_position(plugin_class, positional)
        return Position.new(arguments: []) if plugin_class.nil?
        registry = plugin_class.command_registry
        path, given = registry.command_position(positional[1..].map(&:to_sym))
        Position.new(registry: registry, path: path, arguments: path.nil? || given.zero? ? [] : positional.last(given))
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
      # @param value        [String]        word at cursor
      # @param position     [Position]      command reached
      # @return [Completion] sub-commands, or next argument
      def completion_command(plugin_class, words, value, position)
        registry = plugin_class.command_registry
        path = position.path
        return Completion.new(candidates: []) if path.nil?
        children = registry.children_of(path)
        next_argument = completion_next_argument(registry, path, position.arguments.length)
        return completion_argument(next_argument, value, position) unless next_argument.nil?
        # Source files of an upload follow the declared arguments
        return Completion.new(candidates: [], files: :file) if children.empty? && registry[path]&.transfer_paths.eql?(:send)
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

      # In a structure built with `@:`: the keys of its schema, and its end marker once an assignment is given, or the value of a key
      # @param collecting   [Collecting]    structure being typed
      # @param value        [String]        word at cursor: `path`, or `path=value`
      # @param plugin_class [Class, nil]    plugin
      # @param positional   [Array<String>] positional words, the plugin name first
      # @param position     [Position]      command reached
      # @return [Completion]
      def completion_collecting(collecting, value, plugin_class, positional, position)
        schema =
          if collecting.option
            option = completion_option(collecting.option)
            completion_option_schema(option, position) unless option.nil?
          elsif plugin_class
            # The positional argument built is the last positional word: `@:`
            registry = plugin_class.command_registry
            path, given = registry.command_position(positional[1..-2].map(&:to_sym))
            completion_next_argument(registry, path, given)&.schema unless path.nil?
          end
        if (index = value.index(Option::VALUE_SEP))
          return completion_key_value(schema, value[0...index].split(DotContainer::SEPARATOR), value[(index + 1)..], position).prefixed(value[0..index])
        end
        end_marker = collecting.assigned.empty? ? [] : [[collecting.marker, 'End of structure built with @:']]
        # The value of an option may be partial (completed by other sources): required keys apply to an argument only
        keys = completion_schema_keys(completion_schema_rows(schema), value, assigned: collecting.assigned, required: collecting.option.nil?)
        return Completion.new(candidates: [], hint: completion_hint('path=value', nil)) if end_marker.empty? && keys.empty?
        Completion.new(candidates: end_marker + keys)
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
            if word.eql?(collecting.marker)
              collecting = nil
            else
              collecting.assigned.push(word.split(Option::VALUE_SEP, 2).first)
            end
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
        Collecting.new(marker: match[1].empty? ? SpecialValues::EOA : match[1], assigned: [], option: option)
      end

      # @param tok [Option] option token
      # @return [OptionValue, nil] declared option designated by the token
      def completion_option(tok)
        return options.declared_options.values.find { |o| o.short.eql?(tok.short_char) } if tok.short_char
        options.declared_options[tok.name.to_sym]
      end

      # @param option   [OptionValue] declared option
      # @param position [Position]    command reached
      # @return [String, nil] schema of the value of option: the one of option `query` depends on the command
      def completion_option_schema(option, position)
        return option.schema unless option.schema.nil? && option.option.eql?(:query)
        position.spec&.query_schema
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

      # @param tok      [Option]   option token waiting for its value
      # @param value    [String]   value typed
      # @param position [Position] command reached
      # @return [Completion] allowed values of the option, or its type as hint
      def completion_option_values(tok, value, position)
        option = completion_option(tok)
        # Option not declared yet (e.g. of a plugin): its value may still be an extended value
        return completion_value(value, position, hint: nil) if option.nil?
        schema = completion_option_schema(option, position)
        return completion_key_value(schema, tok.dot_path, value, position) unless tok.dot_path.nil?
        allowed = option.values&.map(&:to_s)&.uniq
        complete = option.complete
        # A String value is the value of a key of the structure
        allowed, complete = completion_shorthand(schema, option.shorthand) if allowed.nil? && complete.nil? && option.shorthand
        types = option.types&.reject { |t| t.eql?(NilClass) }
        hint = completion_hint(types&.any? ? types.map(&:name).join('|') : option.allowed_info || 'String', schema)
        completion_value(value, position, hint: hint, allowed: allowed, complete: complete)
      end

      # @param schema [String, nil] schema of structure
      # @param key    [String]      key of a `String` value
      # @return [Array(Array<String>, Symbol)] allowed values of the key, from its schema or the discriminator of its variants, and kind of value
      def completion_shorthand(schema, key)
        row = completion_schema_row(schema, [key])
        return [completion_row_values(row), row['complete']&.to_sym] unless row.nil?
        node = Schema::Registry.instance.reader(schema).current
        [(node.dig('discriminator', 'mapping')&.keys if node.dig('discriminator', 'propertyName').eql?(key)), nil]
      rescue StandardError
        [nil, nil]
      end

      # Keys of an option with dotted notation, from its schema, e.g. `--ts.ta` gives `--ts.target_rate_kbps=`
      # @param current  [String]   word at cursor
      # @param position [Position] command reached
      # @return [Completion, nil] keys at the level of the word, `nil` if the word is not a dotted option
      def completion_option_keys(current, position)
        match = current.match(/\A--([^=.]+)\.([^=]*)\z/)
        return if match.nil?
        option = options.declared_options[Parser.option_line_to_name(match[1]).to_sym]
        return Completion.new(candidates: []) if option.nil?
        rows = completion_schema_rows(completion_option_schema(option, position))
        Completion.new(candidates: completion_schema_keys(rows, match[2])).prefixed("#{Option::PREFIX}#{match[1]}#{DotContainer::SEPARATOR}")
      end

      # Keys of a structure at the level of the path typed: `key=` for a value, `key.` for a structure, `key.0.` for a list of structures.
      # @param rows     [Array<Hash>]   fields of schema
      # @param typed    [String]        path typed: dot-separated keys, the last one being typed
      # @param assigned [Array<String>] paths already assigned, not proposed again
      # @param required [Boolean]       required keys are marked, and listed first
      # @return [Array<Array(String, String)>] path of key, and its description
      def completion_schema_keys(rows, typed, assigned: [], required: false)
        # Keys of parents, as typed, e.g. `recipients.0.`
        parents = typed[0, (typed.rindex(DotContainer::SEPARATOR) || -1) + 1]
        parent_path = completion_row_path(parents.split(DotContainer::SEPARATOR))
        names = rows.map { |r| r['name'] }
        keys = rows.filter_map do |row|
          path = row['name'].split(DotContainer::SEPARATOR)
          next unless path[0..-2].eql?(parent_path)
          suffix =
            if names.any? { |n| n.start_with?("#{row['name']}#{DotContainer::SEPARATOR}") } then DotContainer::SEPARATOR
            elsif names.any? { |n| n.start_with?("#{row['name']}[]#{DotContainer::SEPARATOR}") } then "#{DotContainer::SEPARATOR}0#{DotContainer::SEPARATOR}"
            else Option::VALUE_SEP
            end
          key = "#{parents}#{path.last}"
          next if suffix.eql?(Option::VALUE_SEP) && assigned.include?(key)
          description = completion_description(row['description']) || completion_type(row['type'])
          description = [description, '(required)'].compact.join(' ') if required && row['required']
          ["#{key}#{suffix}", description, required && row['required']]
        end
        keys.partition(&:last).flatten(1).map { |key, description, _| [key, description] }
      end

      # @param keys [Array<String>] keys of a path, as typed, e.g. `recipients`, `0`, `name`
      # @return [Array<String>] keys of the path, as in schema rows, e.g. `recipients[]`, `name`
      def completion_row_path(keys)
        keys.each_with_object([]) do |key, path|
          if !path.empty? && key.match?(/\A\d+\z/)
            path[-1] = "#{path.last}[]"
          else
            path.push(key)
          end
        end
      end

      # @param schema [String, nil]   schema of structure
      # @param keys   [Array<String>] path of key in structure, as typed
      # @return [Hash, nil] field of the schema at path
      def completion_schema_row(schema, keys)
        name = completion_row_path(keys).join(DotContainer::SEPARATOR)
        completion_schema_rows(schema).find { |r| r['name'].eql?(name) }
      end

      # @param row [Hash] field of schema
      # @return [Array<String>, nil] allowed values of the field
      def completion_row_values(row)
        return row['enum'].compact.map(&:to_s) if row['enum']
        %w[true false] if row['type'].eql?('boolean')
      end

      # @param schema   [String, nil]   schema of structure
      # @param keys     [Array<String>] path of key in structure, as typed
      # @param value    [String]        value typed
      # @param position [Position]      command reached
      # @return [Completion] allowed values of the key, or its type as hint
      def completion_key_value(schema, keys, value, position)
        row = completion_schema_row(schema, keys)
        return completion_value(value, position, hint: nil) if row.nil?
        type = completion_type(row['type'])
        hint = ["<#{type.empty? ? 'value' : type}>", completion_description(row['description'])].compact.join(' ')
        completion_value(value, position, hint: hint, allowed: completion_row_values(row), complete: row['complete']&.to_sym)
      end

      # @param value    [String]             value typed
      # @param position [Position]           command reached
      # @param hint     [String, nil]        hint, when nothing can be proposed
      # @param allowed  [Array<String>, nil] allowed values
      # @param complete [Symbol, nil]        kind of value, one of `Complete::KINDS`
      # @param extended [Boolean]            the value is evaluated as extended value
      # @return [Completion] values: extended value modifiers, allowed values, local values, or hint
      def completion_value(value, position, hint:, allowed: nil, complete: nil, extended: true)
        return completion_extended(value, position, complete) if extended && value.start_with?(MARKER_MODIFIER)
        return Completion.new(candidates: allowed.map { |v| [v, nil] }) unless allowed.nil? || allowed.empty?
        (completion_kind(complete, value, position) unless complete.nil?) || Completion.new(candidates: [], hint: hint)
      end

      # @param kind     [Symbol]   kind of value, one of `Complete::KINDS`
      # @param value    [String]   value typed
      # @param position [Position] command reached
      # @return [Completion, nil] values of this kind, `nil` if none applies
      def completion_kind(kind, value, position)
        case kind
        when :file, :folder then Completion.new(candidates: [], files: kind)
        when :destination_folder then Completion.new(candidates: [], files: :folder) unless position.spec&.transfer_paths.eql?(:send)
        when :preset then Completion.new(candidates: completion_preset_names(value))
        when :preset_parameter then Completion.new(candidates: completion_preset_parameters(position.arguments.first))
        when :transfer_job then Completion.new(candidates: async_transfer_store.list.map { |job| [job['job_id'].to_s, job['status']] })
        else Aspera.error_unexpected_value(kind) { 'complete' }
        end
      end

      # Value starting with `@`: modifiers, or the value of the last modifier, e.g. a local file for `@file:`
      # @param value    [String]      value typed, starting with `@`
      # @param position [Position]    command reached
      # @param complete [Symbol, nil] kind of value, one of `Complete::KINDS`
      # @return [Completion]
      def completion_extended(value, position, complete)
        modifiers = ExtendedValue.instance.modifiers
        last = nil
        rest = value
        while !MODIFIERS_LITERAL.include?(last) && (match = REGEX_MODIFIER.match(rest)) && modifiers.include?(match[1].to_sym)
          last = match[1].to_sym
          rest = match.post_match
        end
        prefix = value[0, value.length - rest.length]
        propose_modifiers = rest.start_with?(MARKER_MODIFIER) ? !MODIFIERS_LITERAL.include?(last) : rest.empty? && MODIFIERS_DECODING.include?(last)
        completion =
          if propose_modifiers then Completion.new(candidates: modifiers.map { |m| ["#{MARKER_MODIFIER}#{m}:", ExtendedValue.instance.description(m)] })
          else
            case last
            when :file, :path then Completion.new(candidates: [], files: complete.eql?(:folder) ? :folder : :file)
            when :preset then Completion.new(candidates: completion_preset_names(rest))
            when :env then Completion.new(candidates: ENV.keys.sort.map { |k| [k, nil] })
            when :stdin then Completion.new(candidates: STDIN_MODES.map { |m| [m, nil] })
            when *MODIFIERS_DECODING then Completion.new(candidates: [])
            else Completion.new(candidates: [], hint: ExtendedValue.instance.description(last))
            end
          end
        completion.prefixed(prefix)
      end

      # Names of presets, and parameters of the preset typed (`@preset:` takes a dot path)
      # @param value [String] value typed
      # @return [Array<Array(String, nil)>]
      def completion_preset_names(value)
        presets.config_presets.each_key.flat_map do |name|
          parameters = value.start_with?("#{name}#{DotContainer::SEPARATOR}") ? completion_preset_parameters(name) : []
          [[name, nil]] + parameters.map { |parameter, _| ["#{name}#{DotContainer::SEPARATOR}#{parameter}", nil] }
        end
      end

      # @param name [String, nil] name of preset
      # @return [Array<Array(String, nil)>] parameters of the preset, empty if it is not a preset
      def completion_preset_parameters(name)
        preset = presets.config_presets[name]
        return [] unless preset.is_a?(Hash)
        preset.keys.map(&:to_s).reject { |k| k.start_with?(PresetManager::Key::META_PREFIX) }.map { |k| [k, nil] }
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
          # stdout is read by the shell, not a terminal, but the hint is displayed on the terminal: check the locale only
          return "#{hint}#{separator}#{Environment.char('…', unicode: Environment.unicode_environment?)}" if hint.length + separator.length + name.length > HINT_MAX_LENGTH
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
      # @param value    [String]       value typed
      # @param position [Position]     command reached
      # @return [Completion] allowed values of the argument, or its type (and keys of its schema) as hint
      def completion_argument(arg_spec, value, position)
        type_str =
          case arg_spec.type
          when :identifier then 'identifier'
          when Array       then arg_spec.type.map(&:name).join('|')
          when Class       then arg_spec.type.name
          when nil         then 'String'
          else arg_spec.type.to_s
          end
        hint = completion_hint(type_str, arg_spec.schema)
        # Percent selector: lookup of the identifier by a field
        hint = "#{hint} or %<field>:<value>" if arg_spec.type.eql?(:identifier) && !arg_spec.lookup.nil?
        completion_value(value, position, hint: hint, allowed: arg_spec.allowed&.map(&:to_s), complete: arg_spec.complete, extended: !arg_spec.raw)
      end

      # @param plugin_sym [Symbol] plugin name
      # @return [String, nil] name of the application of the plugin
      def completion_plugin_description(plugin_sym)
        Plugins::Factory.instance.plugin_class(plugin_sym).application_name
      rescue StandardError
        nil
      end

      # @param text [String, nil] description
      # @return [String, nil] first sentence of first line, without final period, as displayed by the shell
      def completion_description(text)
        line = text.to_s.lines.first.to_s.strip.tr("\t", ' ').split(REGEX_SENTENCE_END).first.to_s.delete_suffix('.')
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
