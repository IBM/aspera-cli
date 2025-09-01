#!/usr/bin/env ruby
# frozen_string_literal: true

# cspell:ignore geminstadd transferspec passcode emea

# Tools used in README.erb.md

# get transfer spec parameter description
require 'aspera/environment'
require 'aspera/cli/info'
require 'aspera/cli/plugin_factory'
require 'aspera/cli/plugins/config'
require 'aspera/sync/operations'
require 'aspera/transfer/spec_doc'
require 'aspera/log'
require 'yaml'
require 'erb'
require 'English'

Aspera::Log.instance.level = :info
Aspera::Log.instance.level = ENV['ASPERA_CLI_DOC_DEBUG'].to_sym if ENV['ASPERA_CLI_DOC_DEBUG']
Aspera::RestParameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}

# format special value depending on context
class HtmlFormatter
  class << self
    def special_format(special)
      "&lt;#{special}&gt;"
    end

    def check_row(row)
      row.each_key do |k|
        row[k] = row[k].join('<br/>') if row[k].is_a?(Array)
        row[k] = '&nbsp;' if row[k].to_s.strip.empty?
      end
    end
  end
end

# place warning in generated file
def doc_warn(_)
  'DO NOT EDIT: THIS FILE IS GENERATED, edit docs/README.erb.md, for details, read docs/README.md'
end

# line break in tables
def br; '<br/>'; end

# to the power of
def pow(value); "<sup>#{value}</sup>"; end

# set values used in ERB
# just command name
def cmd; Aspera::Cli::Info::CMD_NAME; end

# (Markdown) used in text with formatting of command
def tool; "`#{cmd}`"; end

# env var for option
def opt_env(option); "#{cmd.upcase}_#{option.to_s.upcase}"; end

# container image in docker hub
def container_image; Aspera::Cli::Info::CONTAINER; end

def sync_arguments_list(format: nil, admin: false)
  params = admin ? Aspera::Sync::Operations::ADMIN_PARAMETERS : Aspera::Sync::Operations::SYNC_PARAMETERS
  markdown_list(case format
  when nil
    params.map{ |i| i[:name]}
  else
    params.map{ |i| i[format].split('.').map{ |j| "`#{j}`"}.join('->')}
  end)
end

def gemspec; Gem::Specification.load(@param[:gemspec]) || raise("error loading #{@param[:gemspec]}"); end

# if version contains other characters than digit and dot, it is pre-release
def geminstadd; /[^\.0-9]/.match?(gemspec.version.to_s) ? ' --pre' : ''; end

def gem_opt_md_list
  columns = %i[name version comment].freeze
  data = gem_opt_list.map do |g|
    columns.map{ |c| g[c]}
  end
  data.unshift(columns)
  markdown_table(data)
end

def gem_opt_cmd
  gem_opt_list.map do |g|
    "gem install #{g[:name]} -v '#{g[:version]}'"
  end.join("\n")
end

# not very reliable
def gem_opt_list
  File.read(@param[:gemfile]).lines.filter_map do |l|
    m = l.match(/^ *gem\('([^']+)', '([^']+)'\)(.*)/)
    next nil unless m
    {
      name:    m[1],
      version: m[2],
      comment: m[3].gsub('# ', '').strip
    }
  end
end

# more reliable but missing comments
def gem_opt_list_unused
  require 'bundler'
  # Load the definition from the Gemfile and Gemfile.lock
  definition = Bundler::Definition.build(@param[:gemfile], "#{@param[:gemfile]}.lock", nil)
  # Filter specs in the optional group
  optional_specs = definition.dependencies.select do |dep|
    dep.groups.include?(:optional)
  end
  # Print gem names and version requirements
  optional_specs.map do |dep|
    {
      name:    dep.name,
      version: dep.requirement,
      comment: '-'
    }
  end
end

# Generate markdown from the provided table
def markdown_table(table)
  headings = table.shift
  table.unshift(headings.map{ |col_name| '-' * col_name.length})
  table.unshift(headings)
  return table.map{ |line| "| #{line.map{ |i| i.to_s.gsub('|', '\|')}.join(' | ')} |\n"}.join.chomp
end

def markdown_list(items)
  items.map{ |i| "- #{i}"}.join("\n")
end

# Transfer spec description generation for markdown manual
def spec_table
  agents = Aspera::Transfer::SpecDoc::AGENT_LIST.map{ |i| [i.last.upcase, i[1]]}
  agents.unshift(%w[ID Name])
  props = Aspera::Transfer::SpecDoc.man_table(HtmlFormatter, color: false).map do |param|
    Aspera::Transfer::SpecDoc::TABLE_COLUMNS.map{ |field_name| param[field_name]}
  end
  # Column titles
  props.unshift(Aspera::Transfer::SpecDoc::TABLE_COLUMNS.map(&:capitalize))
  props.first[0] = 'Field'
  [markdown_table(agents), markdown_table(props)].join("\n\n")
end

# @return the minimum ruby version from gemspec
def ruby_minimum_version
  requirement = gemspec.required_ruby_version.to_s
  raise "gemspec version must be generic, i.e. like '>= x.y', not specific like '#{requirement}'" if gemspec.required_ruby_version.specific?
  return requirement.gsub(/^[^0-9]*/, '')
end

def ruby_version
  message = "version: #{gemspec.required_ruby_version}"
  unless ruby_minimum_version.eql?(Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION)
    message += ".\n\n> **Deprecation notice**: the minimum Ruby version will be #{Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION} in a future version"
  end
  return message
end

# generate help for the given command
def generate_help(varname)
  raise "missing #{varname}" unless @param.key?(varname)
  exec_path = @param[varname]
  # Add library path for Ruby CLI execution
  lib_path = File.expand_path('../lib', File.dirname(exec_path))
  output = %x(ruby -I #{lib_path} #{exec_path} -h 2>&1)
  raise "Error executing: ruby -I #{lib_path} #{exec_path} -h" unless $CHILD_STATUS.success?
  return output
end

def include_usage
  generate_help(:ascli).gsub(%r{(current=).*(/.aspera/)}, '\1/user_home\2')
end

def include_asession
  generate_help(:asession)
end

# various replacements from commands in test makefile
REPLACEMENTS = [
  # replace command name
  [/^.*\$\(INCMAN\)/, ''],
  [/\$\((CLI|BEG|END)_[A-Z_]+\)/, ''],
  # replace file_vars
  [/\$\$\((cat|basename) ([^)]+)\)/, '\2'],
  # replace makefile macros
  [/\$\(([^) ]*)\)/, '\1'],
  # remove multi command mark
  [/\)?&&\\$/, ''],
  [/ & sleep .*/, ''],
  # remove redirection to file
  [/ *> *[^(}][^ ]*$/, ''],
  # remove folder macro
  [/DIR_[A-Z]+/, ''],
  [/STATE/, ''],
  # de-dup dollar in regex
  ['$$', '$'],
  # replace shell vars in shell
  [/\$\{([a-z_0-9]+)\}/, 'my_\1'],
  # remove extraneous quotes on JSON
  [/("?)'"([a-z_.]+)"'("?)/, '\1\2\3'],
  [/TST_([A-Z]{3})_(FILENAME|LCL_PATH)/, 'test_file.bin'],
  [/TMP_SYNCS[a-z_0-9]*/, '/data/local_sync'],
  ['HSTS_UPLOADED_FILE', 'test_file.bin'],
  ['HSTS_FOLDER_UPLOAD', 'folder_1'],
  [%q['"CF_LOCAL_SYNC_DIR"'], 'sync_dir'],
  ['Test Package TIMESTAMP', 'Important files delivery'],
  ['AOC_EXTERNAL_EMAIL', 'external.user@example.com'],
  ['EMAIL_ADDR', 'internal.user@example.com'],
  ['CF_', ''],
  ['$@', 'test'],
  ['my_f5_meta', ''],
  # remove special configs
  ['-N ', ''],
  [/-P[0-9a-z_]+ /, ''],
  [/--preset=[0-9a-z_]+/, ''],
  ['TMP_CONF', ''],
  ['WIZ_TEST', ''],
  # URLs for doc
  [/@preset:([^_]+)_[^ ]+\.url/, 'https://\1.example.com/path'],
  [/@preset:[a-z0-9_]+\.([a-z0-9_]+)@?/, 'my_\1'],
  [/my_link_([a-z_]+)/, 'https://app.example.com/\1_path'],
  ['@extend:', ''],
  ['"my_password"', '"my_password_here"']
].freeze

# @return [Hash] all test commands with key by plugin
def all_test_commands_by_plugin
  if @commands.nil?
    commands = {}
    File.open(@param[:makefile]) do |file|
      file.each_line do |line|
        next unless line.include?('$(INCMAN)')
        line = line.chomp
        REPLACEMENTS.each{ |replace| line = line.gsub(replace.first, replace.last)}
        line = line.strip.squeeze(' ')
        Aspera::Log.log.debug(line)
        # plugin name shall be the first argument: command
        plugin = line.split(' ').first
        commands[plugin] ||= []
        commands[plugin].push(line.gsub(/^#{plugin} /, ''))
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
  commands = all_test_commands_by_plugin.delete(plugin_name.to_s)
  raise "plugin #{plugin_name} not found in test makefile" if commands.nil?
  @undocumented_plugins.delete(plugin_name.to_sym)
  return "### #{plugin_name.capitalize} sample commands\n\n> **Note:** Add `#{cmd} #{plugin_name}` in front of the commands:\n\n```bash\n#{commands.join("\n")}\n```"
end

def include_commands
  all = []
  all_test_commands_by_plugin.each_value do |v|
    all.concat(v)
  end
  return all.join("\n")
end

REMOVED_OPTIONS = %w[insecure].freeze
KEEP_HOSTS = %w[localhost 127.0.0.1].freeze
SAMPLE_EMAIL = 'my_user@example.com'
SHORT_LINK = 'https://aspera.pub/MyShOrTlInK'

# main function to generate template configuration file for tests
# hide sensitive information
def generate_generic_conf
  local_config = ENV['ASPERA_CLI_TEST_CONF_FILE']
  raise 'missing env var ASPERA_CLI_TEST_CONF_FILE: local config file' if local_config.nil?
  raise "Missing conf file: #{local_config}" if !File.exist?(local_config)
  configuration = YAML.load_file(local_config)
  configuration.each do |k, preset_hash|
    preset_hash.each do |param_name, param_value|
      if param_name.eql?('ignore_certificate') && param_value.is_a?(Array) && param_value.all?(String)
        param_value.map!{ |fqdn| fqdn.gsub('aspera-emea', 'example')}
      end
      next unless param_value.is_a?(String)
      next if param_value.start_with?('@preset:')
      if k.eql?('config') && param_name.eql?('version')
        preset_hash[param_name] = '4.0'
        next
      end
      if param_value.match?(/^[a-z.0-9+]+@[a-z.0-9+]+$/)
        preset_hash[param_name] = SAMPLE_EMAIL
        next
      end
      if param_name.eql?('client_id')
        preset_hash[param_name] = 'my_client_id'
      end
      if param_name.eql?('bucket_name') || param_name.eql?('bucket')
        preset_hash[param_name] = 'my_bucket'
      end
      begin
        uri = URI.parse(param_value)
        raise '' if uri.scheme.nil?
        next if KEEP_HOSTS.include?(uri.host)
        if uri.host.eql?('aspera.pub')
          preset_hash[param_name] = SHORT_LINK
          next
        end
        uri.host = if uri.host.end_with?('.ibmaspera.com')
          'example.ibmaspera.com'
        else
          uri.host.gsub('aspera-emea', 'example').gsub('asperademo', 'example').gsub('my_local_server', '127.0.0.1')
        end
        if uri.query.is_a?(String)
          uri.query = uri.query.gsub(/&?token=[^&]*/, 'token=some_token')
          uri.query = uri.query.gsub(/&?passcode=[^&]*/, 'token=some_passcode')
          uri.query = uri.query.gsub(/&?context=[^&]*/, 'context=some_passcode')
        end
        preset_hash[param_name] = uri.to_s
      rescue
        nil
      end
      case param_name
      when 'url'
      when 'username'
        preset_hash[param_name] = param_value.include?('@') ? SAMPLE_EMAIL : 'my_user'
        next
      when /password/, /secret/, /client_id/, /key$/, /crn/, /instance_id/, /pass$/, 'instance'
        preset_hash[param_name] = 'your value here'
        next
      end
      next unless param_value.start_with?('https://')
    end
  end
  File.open(ARGV.shift, 'w') do |f|
    f.puts(configuration.to_yaml)
  end
end

def check_links(file_path)
  # read markdown file line by line, and check that all links are valid
  # ignore links starting with https:// or #, other links are considered as file paths
  require 'uri'
  require 'net/http'
  File.open(file_path) do |file|
    file.each_line do |line|
      line.scan(/(?:\[(.*?)\]\((.*?)\))/) do |match|
        link_text = match[0]
        link_url = match[1]
        next if link_url.include?('<%=')
        next if link_url.start_with?('#')
        next if link_url.eql?('docs/Manual.pdf')
        next if link_url.start_with?('https://cloud.ibm.com/')
        if link_url.start_with?('https://', 'http://')
          Aspera::Log.log.info("Checking: #{link_url}")
          Aspera::Rest.new(base_url: link_url, redirect_max: 5).call(operation: 'GET')
          next
        end
        raise "Invalid link: #{link_text} (#{link_url})" unless File.exist?(File.join('..', link_url))
      end
    end
  end
end

# main function to generate README.md
def generate_doc
  # parameters
  outfile = ARGV.shift
  @param = {}
  %i[template ascli asession makefile gemspec gemfile].each do |name|
    @param[name] = ARGV.shift
    raise "Missing arg: #{name}" if @param[name].nil?
  end
  # no unicode
  Aspera::Environment.force_terminal_c
  check_links(@param[:template]) unless ENV['ASPERA_CLI_DOC_SKIP_LINK_CHECK']
  # get current plugins
  plugin_manager = Aspera::Cli::PluginFactory.instance
  plugin_manager.add_lookup_folder(Aspera::Cli::Plugins::Config.gem_plugins_folder)
  plugin_manager.add_plugins_from_lookup_folders
  @undocumented_plugins = plugin_manager.plugin_list
  tmp_file = [outfile, 'tmp'].join('.')
  File.open(tmp_file, 'w') do |f|
    f.puts(ERB.new(File.read(@param[:template])).result(Kernel.binding))
  end
  Aspera::Log.log.warn("Undocumented plugins: #{@undocumented_plugins}") unless @undocumented_plugins.empty?
  # check that all test commands are included in the doc
  if !all_test_commands_by_plugin.empty?
    Aspera::Log.log.error("Those plugins not included in doc: #{all_test_commands_by_plugin.keys.join(', ')}".red)
    raise 'Remediate: remove from doc using EXE_NO_MAN or add section in doc'
  end
  File.rename(tmp_file, outfile)
end
