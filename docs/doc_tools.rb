#!/usr/bin/env ruby
# frozen_string_literal: true

# Tools used in README.erb.md

# get transfer spec parameter description
require 'aspera/fasp/parameters'
require 'aspera/cli/info'
require 'yaml'
require 'erb'

# set values used in ERB
# just command name
def cmd; Aspera::Cli::PROGRAM_NAME; end

# used in text with formatting of command
def tool; '`' + cmd + '`'; end

# prefix for env vars
def evp; cmd.upcase + '_'; end

# just the name for "option preset"
def opprst; 'option preset'; end

# name with link
def prst; '[' + opprst + '](#lprt)'; end

# name with link (plural)
def prsts; '[' + opprst + 's](#lprt)'; end

# Transfer spec name with link
def trspec; '[*transfer-spec*](#transferspec)'; end

# in title
def prstt; opprst.capitalize; end

# container image in dockerhub
def containerimage; 'martinlaurent/ascli'; end

def gemspec; Gem::Specification.load(@env[:GEMSPEC]) || raise("error loading #{@env[:GEMSPEC]}"); end

# if version contains other characters than digit and dot, it is pre-release
def geminstadd; /[^\.0-9]/.match?(gemspec.version.to_s) ? ' --pre' : ''; end

# Generate markdown from the provided table
def markdown_table(table)
  headings = table.shift
  table.unshift(headings.map{|h|'-' * h.length})
  table.unshift(headings)
  return table.map {|l| '| ' + l.join(' | ') + " |\n"}.join.chomp
end

# transfer spec description generation
def spec_table
  # list of fields to display (column titles and key in source table)
  fields = [:name, :type, Aspera::Fasp::Parameters::SUPPORTED_AGENTS_SHORT, :description].flatten.freeze
  # Headings
  table = [fields.map(&:capitalize)]
  table.first[0] = 'Field'
  Aspera::Fasp::Parameters.man_table.each do |p|
    p[:description] += (p[:description].empty? ? '' : "\n") + '(' + p[:cli] + ')' unless p[:cli].to_s.empty?
    p.each_key{|c|p[c] = '&nbsp;' if p[c].to_s.empty?}
    p[:description] = p[:description].gsub("\n", '<br/>')
    p[:type] = p[:type].gsub(',', '<br/>')
    table.push(fields.map{|f|p[f]})
  end
  return markdown_table(table)
end

# @return the minimum ruby version from gemspec
def ruby_minimum_version
  requirement = gemspec.required_ruby_version.to_s
  raise "gemspec version must be generic, i.e. like '>= x.y', not specific like '#{requirement}'" if gemspec.required_ruby_version.specific?
  return requirement.gsub(/^[^0-9]*/, '')
end

def ruby_version
  message = "version: #{gemspec.required_ruby_version}"
  unless ruby_minimum_version.eql?(Aspera::Cli::RUBY_FUTURE_MINIMUM_VERSION)
    message += ".\n\n> **Deprecation notice**: the minimum Ruby version will be #{Aspera::Cli::RUBY_FUTURE_MINIMUM_VERSION} in a future version"
  end
  return message
end

def generate_help(varname)
  raise "missing #{varname}" unless @env.key?(varname)
  return %x(#{@env[varname]} -h 2>&1)
end

def include_usage
  generate_help(:ASCLI).gsub(%r{(current=).*(/.aspera/)}, '\1/usershome\2')
end

def include_asession
  generate_help(:ASESSION)
end

# various replacements from commands in test makefile
REPLACEMENTS = [
  # replace command name
  [/^.*\$\(EXE_MAN.?\) +/, ''],
  # replace makefile macros
  [/\$\(([^)]*)\)/, '\1'],
  # remove multi command mark
  [/\)?&&\\$/, ''],
  # remove redirection
  [/ [>|] .*$/, ''],
  # remove folder macro
  [/DIR_[A-Z]+/, ''],
  # replace shell vars in JSON
  [/'"\$\$\{([a-z_0-9]+)\}"'/, 'my_\1'],
  # replace shell vars in shell
  [/\$\$\{([a-z_0-9]+)\}/, 'my_\1'],
  # de-dup dollar in regex
  ['$$', '$'],
  # hidden parameters to make test work
  [/OPTST_[A-Z0-5]+/, ''],
  ['@preset:misc.', 'my_'],
  ['LOCAL_SAMPLE_FILENAME', 'testfile.bin'],
  ['LOCAL_SAMPLE_FILEPATH', 'testfile.bin'],
  ['HSTS_UPLOADED_FILE', 'testfile.bin'],
  ['HSTS_FOLDER_UPLOAD', 'folder_1'],
  [%q['"CF_LOCAL_SYNC_DIR"'], 'syncdir'],
  ['Test Package TIMESTAMP', 'Important files delivery'],
  ['AOC_EXTERNAL_EMAIL', 'external.user@example.com'],
  ['EMAIL_ADDR', 'internal.user@example.com'],
  ['CF_', ''],
  ['$@', 'test'],
  ['my_f5_meta', '']
].freeze

def all_test_commands_by_plugin
  if @commands.nil?
    commands = {}
    File.open(@env[:TEST_MAKEFILE]) do |f|
      f.each_line do |line|
        next unless line.match?(/\$\(EXE_MAN.?\) +/)
        line = line.chomp
        REPLACEMENTS.each{|r|line = line.gsub(r.first, r.last)}
        # remove special configs
        line = line.gsub(/-P[^ ]+ /, '').gsub('-N ', '')
        # plugin name shall be the first argument: command
        plugin = line.split(/ +/).first
        commands[plugin] ||= []
        commands[plugin].push(line)
      end
    end
    commands.each_key do |plugin|
      commands[plugin] = commands[plugin].sort.uniq
    end
    @commands = commands
  end
  return @commands
end

def include_commands_for_plugin(plugin_name)
  commands = all_test_commands_by_plugin[plugin_name.to_s]
  all_test_commands_by_plugin.delete(plugin_name.to_s)
  return commands.join("\n")
end

def include_commands
  all = []
  all_test_commands_by_plugin.each do |_k, v|
    all.concat(v)
  end
  return all.join("\n")
end

KEPT_GLOBAL_SECTIONS = %w[config default].freeze
REMOVED_OPTIONS = %w[insecure].freeze

# main function to generate template configuration file for tests
def generate_generic_conf
  n = {}
  local_config = ARGV.first
  raise 'missing argument: local config file' if local_config.nil?
  YAML.load_file(local_config).each do |k, v|
    next if k.start_with?('nt_') # no template
    n[k] = KEPT_GLOBAL_SECTIONS.include?(k) ? v : v.keys.reject{|l|REMOVED_OPTIONS.include?(l)}.each_with_object({}){|i, m|m[i] = 'your value here'}
  end
  puts(n.to_yaml)
end

# main function to generate README.md
def generate_doc
  @env = {}
  %i[TEMPLATE ASCLI ASESSION TEST_MAKEFILE GEMSPEC].each do |var|
    @env[var] = ARGV.shift
    raise "Missing arg: #{var}" if @env[var].nil?
  end
  puts ERB.new(File.read(@env[:TEMPLATE])).result(Kernel.binding)
  if !all_test_commands_by_plugin.empty?
    $stderr.puts("those plugins not included in doc #{all_test_commands_by_plugin.keys}".red)
    raise 'Remediate: remove from doc using EXE_NOMAN or add section in doc'
  end
end
