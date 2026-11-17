# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/environment'
require_relative '../../lib/aspera/log'
require_relative '../../lib/aspera/cli/plugins/factory'
require_relative '../../lib/aspera/cli/plugins/config'
require_relative '../../lib/aspera/cli/info'
require_relative 'paths'
require_relative 'doc_markup'
require 'json'
require 'shellwords'
require 'tmpdir'

# Check hand-written command examples of the manual template, and of plain Markdown files (e.g. `README.md`),
# against the commands and options of plugins.
# In the ERB template, the command is `<%=cmd%>`; in a plain Markdown file, it is the command name (`ascli`).
# Checked: code lines starting with the command (after an optional prompt), commands after a pipe or in `$(...)`,
# and inline code spans starting with the command.
# Placeholders (`<...>`, `[...]`, `...`, `a|b`) stop the check of the rest of a command.
# A line with only `SKIP_MARKER` excludes the next code block, or the next line of text.
class DocCommandChecker
  # ERB comment (no output): place alone on the line before an example that shall not be checked
  SKIP_MARKER = '<%# check_commands: skip -%>'
  # Command in the ERB template
  CMD_ERB = '<%=cmd%>'
  # Same as CMD_ERB but marks the line as not to be checked (use instead of CMD_ERB on the line)
  NOCHECK_ERB = '<%=cmd_skip%>'
  # Pipe to a command
  PIPE = /\s*\|\s*(?=#{Regexp.escape(CMD_ERB)} )/
  # Command in `$(...)`
  SUBSHELL = /\$\((#{Regexp.escape(CMD_ERB)} [^)]*)\)/
  # Command in inline code of text
  INLINE = /`(#{Regexp.escape(CMD_ERB)} [^`]+)`/
  # Shell prompt before a command
  PROMPT = /\A(?:\$|PS[^>]*>|C:[^>]*>)\s+/
  # Command name in a plain Markdown file, replaced with CMD_ERB
  CMD_LITERAL = %r{(?<![\w/.-])#{Regexp.escape(Aspera::Cli::Info::CMD_NAME)}(?= )}
  private_constant :CMD_ERB, :NOCHECK_ERB, :PIPE, :SUBSHELL, :INLINE, :PROMPT, :CMD_LITERAL

  # Load plugins and collect the commands and options they declare.
  # @param files [Array<Pathname>] ERB template of the manual (`.erb.md`) or plain Markdown files
  # @param ascli [Pathname] executable of the CLI
  def initialize(files:, ascli:)
    @files = files
    @ascli = ascli
    factory = Aspera::Cli::Plugins::Factory.instance
    factory.add_lookup_folder(Aspera::Cli::Plugins::Config.gem_plugins_folder)
    factory.add_plugins_from_lookup_folders
    # Command registry of each plugin
    @registries = factory.plugin_list.to_h { |p| [p, factory.plugin_class(p).command_registry] }
    # Option name => replacement message if deprecated, else nil
    @options = declared_options
  end

  # Check all command examples of the files, log each error, and fail if there is at least one.
  # @return [void]
  # @raise [RuntimeError] if an example uses an unknown command or option
  def check
    errors = @files.flat_map do |file|
      file_errors = examples(file).flat_map do |example|
        check_command(example[:text]).map { |e| "#{file.basename}:#{example[:line]}: #{e}: #{example[:text]}" }
      end
      Aspera::Log.log.info { "#{file.basename}: command examples OK" } if file_errors.empty?
      file_errors
    end
    errors.each { |e| Aspera::Log.log.error(e) }
    raise "#{errors.length} invalid command example(s), fix or place #{SKIP_MARKER} before or use #{NOCHECK_ERB} instead of #{CMD_ERB}" unless errors.empty?
  end

  private

  # Options declared for all plugins (including global options), from `config options <plugin>`.
  # The CLI is run once per plugin, in parallel threads, with a temporary home folder.
  # @return [Hash{String => String, nil}] option name with `_` => replacement if deprecated
  def declared_options
    Dir.mktmpdir do |home|
      @registries.keys.map do |plugin|
        Thread.new do
          out = Aspera::Environment.secure_execute(
            'ruby', '-I', Paths::LIB, @ascli, 'config', 'options', plugin, '--format=json', '--fields=option,replacement',
            mode: :capture, env: {'ASCLI_HOME' => home}
          ).first
          JSON.parse(out).to_h { |o| [o['option'].delete_prefix('--').tr('-', '_'), o['replacement']] }
        end
      end.map(&:value).reduce({}, :merge)
    end
  end

  # Extract command examples from a file: lines of code blocks (continued lines are joined)
  # and inline code spans, except those excluded by `SKIP_MARKER` or containing `NOCHECK_ERB`.
  # @param file [Pathname] ERB template (`.erb.md`) or plain Markdown file
  # @return [Array<Hash>] command examples: `{line:, text:}`
  def examples(file)
    result = []
    skip = false
    fence = nil
    # logical line of code: lines ending with `\` are continued
    logical = nil
    # In a plain Markdown file, the command name is used instead of `CMD_ERB`
    literal = file.basename.to_s.end_with?('.erb.md') ? nil : CMD_LITERAL
    File.readlines(file, chomp: true).each_with_index do |raw, index|
      line = raw.sub(/\A\s*(?:>\s?)+/, '')
      line = line.gsub(literal, CMD_ERB) unless literal.nil?
      if line.strip.eql?(SKIP_MARKER)
        skip = true
      elsif fence.nil? && line.match?(/\A\s*```+\S*\s*\z/)
        fence = {skip: skip}
        skip = false
      elsif fence && line.match?(/\A\s*```+\s*\z/)
        fence = nil
      elsif fence
        next if fence[:skip]
        code = line.strip
        next if code.include?(NOCHECK_ERB)
        logical = logical.nil? ? {line: index + 1, text: code} : logical.merge(text: "#{logical[:text]} #{code}")
        next if logical[:text].end_with?('\\') && logical[:text].chop!
        result.concat(code_commands(logical[:text]).map { |c| {line: logical[:line], text: c} })
        logical = nil
      elsif !line.strip.empty?
        line.scan(INLINE).flatten.each { |c| result.push({line: index + 1, text: c}) } unless skip
        skip = false
      end
    end
    result
  end

  # Find the commands in a logical line of code.
  # @param code [String] logical line of code
  # @return [Array<String>] commands: at beginning of line (after optional prompt), after a pipe, or in `$(...)`
  def code_commands(code)
    code.scan(SUBSHELL).flatten + code.sub(PROMPT, '').split(PIPE).select { |c| c.start_with?("#{CMD_ERB} ") }
  end

  # Tell if a word is a placeholder (e.g. `<id>`, `[opt]`, `...`, `a|b`) that can not be checked.
  # @param word [String] command line word
  # @return [Boolean] `true` if word is a placeholder, not an actual value
  def placeholder?(word)
    word.match?(/\A[<\[#{Regexp.escape(DocMarkup::PH_CHARS[:b])}]|\.\.\.|\||\AX\z/)
  end

  # Split a command line into words: remove trailing comment, replace ERB expressions
  # (`ph` placeholders keep their name, others become `X`), then split like a shell.
  # @param text [String] command line from the template
  # @return [Array<String>] words, after rendering ERB placeholders
  def words(text)
    text = text.sub(/\s+#\s.*\z/, '')
      .gsub(/<%=\s*ph\s+:(\w+)\s*%>/) { DocMarkup.ph(Regexp.last_match(1)) }
      .gsub(/<%=[^%]*%>/, 'X')
    Shellwords.split(text)
  rescue ArgumentError
    text.split
  end

  # Check options and positional arguments (plugin and commands) of one command line.
  # @param text [String] command line from the template
  # @return [Array<String>] errors
  def check_command(text)
    positional = []
    errors = []
    options_ended = false
    words(text).drop(1).each do |word|
      if options_ended || !word.start_with?('--')
        # short options (e.g. `-N`, `-Pname`) are not checked
        positional.push(word) unless word.match?(/\A-[A-Za-z]/) && !options_ended
      elsif word.eql?('--')
        options_ended = true
      else
        errors.concat(check_option(word))
      end
    end
    errors.concat(check_positional(positional))
  end

  # Check that an option is declared and not deprecated.
  # @param word [String] option on command line, e.g. `--out.level=data`
  # @return [Array<String>] errors
  def check_option(word)
    name = word.delete_prefix('--').split('=', 2).first.split('.').first.to_s.tr('-', '_')
    return [] if name.empty? || name.eql?('%') || placeholder?(name)
    return ["unknown option: --#{name}"] unless @options.key?(name)
    return ["deprecated option: --#{name} (#{@options[name]})"] unless @options[name].nil?
    []
  end

  # Check that the plugin exists and that following words are valid commands of its command tree.
  # Stops at the first placeholder or when the command has no sub-command.
  # @param positional [Array<String>] positional arguments: plugin, commands and arguments
  # @return [Array<String>] errors
  def check_positional(positional)
    plugin = positional.shift
    return [] if plugin.nil? || placeholder?(plugin)
    return ["unknown plugin: #{plugin}"] unless @registries.key?(plugin.to_sym)
    registry = @registries[plugin.to_sym]
    path = []
    loop do
      children = registry.children_of(path)
      return [] if children.empty?
      # arguments of intermediate command, e.g. identifier
      positional.shift(registry.arguments_at(path).count(&:mandatory)) unless path.empty?
      word = positional.shift
      return [] if word.nil? || placeholder?(word)
      id = child_id(children, word)
      return ["unknown command: #{([plugin] + path).join(' ')} #{word}, expecting: #{children.keys.join(', ')}"] if id.nil?
      path.push(id)
    end
  end

  # Find the identifier of a command from its name or one of its aliases.
  # @param children [Hash{Symbol => CommandSpec}] commands
  # @param word     [String] command on command line
  # @return [Symbol, nil] command identifier, if word is the command or one of its aliases
  def child_id(children, word)
    sym = word.to_sym
    return sym if children.key?(sym)
    children.each_value { |c| return c.id if Array(c.aliases).include?(sym) }
    nil
  end
end
