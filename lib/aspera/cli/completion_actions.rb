# frozen_string_literal: true

require 'aspera/cli/info'
require 'aspera/cli/parser'
require 'aspera/cli/plugins/factory'

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
      private_constant :COMPLETION_SHELLS, :COMPLETION_FOLDER, :Completion

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
        plugin_class, positional, waiting = completion_context(words)
        return Completion.new(candidates: []) if positional.nil?
        result =
          if prefix.empty? && current.start_with?('-')
            Completion.new(candidates: completion_options(options.declared_options.keys))
          elsif !waiting.nil?
            completion_option_values(waiting)
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
      # @return [Array(Class, Array<String>, Option)] plugin class (`nil` at root), positional words, and the last option
      #   if it is waiting for its value; `[]` if the first positional word is not a plugin
      def completion_context(words)
        positional, waiting = completion_split(words)
        return [nil, positional, waiting] if positional.empty?
        plugin_sym = positional.first.to_sym
        return [] unless Plugins::Factory.instance.plugin_list.include?(plugin_sym)
        begin
          plugin_class = Plugins::Factory.instance.plugin_class(plugin_sym)
        rescue StandardError
          return []
        end
        plugin_class.declare_options(options)
        # Options of the plugin may take a value: split again
        [plugin_class, *completion_split(words)]
      end

      # @param plugin_class [Class]         plugin
      # @param words        [Array<String>] positional words after the plugin name
      # @return [Completion] sub-commands, or next argument
      def completion_command(plugin_class, words)
        registry = plugin_class.command_registry
        path, given = registry.command_position(words.map(&:to_sym))
        return Completion.new(candidates: []) if path.nil?
        children = registry.children_of(path)
        arguments = registry.arguments_at(path)
        next_argument =
          if given < arguments.length
            arguments[given]
          elsif children.empty? && arguments.last&.multiple
            arguments.last
          end
        return completion_argument(next_argument) unless next_argument.nil?
        # Source files of an upload follow the declared arguments
        return Completion.new(candidates: [], files: true) if children.empty? && registry[path]&.transfer_paths.eql?(:send)
        candidates = children.map { |id, spec| [id.to_s, completion_description(spec.description)] }
        # Options of plugin only right after the plugin name
        candidates.concat(completion_options(plugin_class.option_sources.each_key.flat_map { |src| src.option_specs.keys }.uniq)) if words.empty?
        Completion.new(candidates: candidates)
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
      # @param words [Array<String>] words typed before the cursor
      # @return [Array(Array<String>, Option)] positional words, and the last option if it is waiting for its value
      def completion_split(words)
        positional = []
        waiting = nil
        stop = false
        words.each do |word|
          if !stop && word.eql?(Option::STOP)
            stop = true
            waiting = nil
          elsif !stop && Option.option?(word)
            tok = Option.parse(word)
            # `--opt=` at end of line (from bash split): value is being typed
            waiting = (tok.inline? && !tok.inline_value.empty?) || completion_option(tok)&.flag? ? nil : tok
          elsif waiting
            waiting = nil
          else
            positional.push(word)
          end
        end
        [positional, waiting]
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
        # No information on the value of a key of a dotted option
        return Completion.new(candidates: []) if option.nil? || tok.dot_path
        return Completion.new(candidates: option.values.map(&:to_s).uniq.map { |v| [v, nil] }) if option.values&.any?
        types = option.types&.reject { |t| t.eql?(NilClass) }
        Completion.new(candidates: [], hint: "<#{types&.any? ? types.map(&:name).join('|') : option.allowed_info || 'String'}>")
      end

      # @param arg_spec [ArgumentSpec] expected argument
      # @return [Completion] allowed values of the argument, or its type as hint
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
        Completion.new(candidates: [], hint: "<#{type_str}>")
      end

      # @param plugin_sym [Symbol] plugin name
      # @return [String, nil] name of the application of the plugin
      def completion_plugin_description(plugin_sym)
        Plugins::Factory.instance.plugin_class(plugin_sym).application_name
      rescue StandardError
        nil
      end

      # @param text [String, nil] description
      # @return [String, nil] first line, as displayed by the shell
      def completion_description(text)
        line = text.to_s.lines.first.to_s.strip.tr("\t", ' ')
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
