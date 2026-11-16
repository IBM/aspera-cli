# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/markdown'
require_relative '../../lib/aspera/cli/info'

# Stateless text helpers for README.erb.md
# Included in DocHelper (callable without receiver in ERB), or called directly: `DocMarkup.ph(:id)`
module DocMarkup
  # Characters surrounding a placeholder (`b`: begin, `e`: end), see `ph`
  PH_CHARS = {b: '<', e: '>'}.freeze

  module_function

  # Place warning in generated file
  # @param _ [String] Text shown in the template itself (ignored)
  # @return [String] Warning shown in the generated file
  def doc_warn(_)
    'DO NOT EDIT: THIS FILE IS GENERATED, edit docs/README.erb.md.'
  end

  # Line break in tables
  # @return [String] HTML line break
  def br; Aspera::Markdown::HTML_BREAK; end

  # Place Holder
  # @param name [String, Symbol] Name or description of parameter
  # @return [String] `<name.upcase>`
  def ph(name); "#{PH_CHARS[:b]}#{name.upcase}#{PH_CHARS[:e]}"; end

  # To the power of
  # @param value [#to_s] Exponent
  # @return [String] HTML superscript
  def pow(value); "<sup>#{value}</sup>"; end

  # Just command name
  # @return [String] Command name, e.g. `ascli`
  def cmd; Aspera::Cli::Info::CMD_NAME; end

  # Same as `cmd` but marks the command line as not to be checked by DocCommandChecker
  # @return [String] Command name, see {cmd}
  def cmd_skip; cmd; end

  # (Markdown) used in text with formatting of command
  # @return [String] Command name as inline code
  def tool; "`#{cmd}`"; end

  # Env var for option
  # @param option [String, Symbol] Option name, with `_`
  # @return [String] Env var name, e.g. `ASCLI_<OPTION>`
  def opt_env(option); "#{cmd.upcase}_#{option.upcase}"; end

  # Container image in docker hub
  # @return [String] Image name
  def container_image; Aspera::Cli::Info::CONTAINER; end

  # Link to the provided path in repo, relative to readme
  # @param path [String] Path relative to repository root
  # @return [String] Path relative to `docs/`
  def link_repo(path)
    "../#{path}".gsub('../docs/', '')
  end

  # Title of section with tested commands of a plugin
  # @param plugin_name_sym [Symbol] Plugin name
  # @return [String] Section title
  def sample_commands_title(plugin_name_sym)
    "Tested commands for `#{plugin_name_sym}`"
  end
end
