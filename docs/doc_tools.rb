#!/usr/bin/env ruby
# frozen_string_literal: true

# cspell:ignore geminstadd transferspec passcode emea

# Tools used in README.erb.md

# get transfer spec parameter description
require 'aspera/transfer/parameters'
require 'aspera/cli/info'
require 'aspera/cli/plugin_factory'
require 'aspera/cli/plugins/config'
require 'aspera/cli/sync_actions'
require 'yaml'
require 'erb'
require 'English'

# format special value depending on context
class HtmlFormatter
  def special_format(special)
    "&lt;#{special}&gt;"
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

def sync_arguments_list; Aspera::Cli::SyncActions::ARGUMENTS_LIST.map{ |i| "- `#{i}`"}.join("\n"); end

def gemspec; Gem::Specification.load(@env[:GEMSPEC]) || raise("error loading #{@env[:GEMSPEC]}"); end

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
  File.read(@env[:GEMFILE]).lines.filter_map do |l|
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
  definition = Bundler::Definition.build(@env[:GEMFILE], "#{@env[:GEMFILE]}.lock", nil)
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

# transfer spec description generation
def spec_table
  # list of fields to display (column titles and key in source table)
  fields = [:name, :type, Aspera::Transfer::Parameters::SUPPORTED_AGENTS_SHORT, :description].flatten.freeze
  # Headings
  table = [fields.map(&:capitalize)]
  table.first[0] = 'Field'
  Aspera::Transfer::Parameters.man_table(HtmlFormatter.new).each do |param|
    param[:description] += (param[:description].empty? ? '' : "\n") + '(' + param[:cli] + ')' unless param[:cli].to_s.empty?
    param.each_key{ |k| param[k] = '&nbsp;' if param[k].to_s.strip.empty?}
    param[:description] = param[:description].gsub("\n", '<br/>')
    param[:type] = param[:type].gsub(',', '<br/>')
    table.push(fields.map{ |field_name| param[field_name]})
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
  unless ruby_minimum_version.eql?(Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION)
    message += ".\n\n> **Deprecation notice**: the minimum Ruby version will be #{Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION} in a future version"
  end
  return message
end

# generate help for the given command
def generate_help(varname)
  raise "missing #{varname}" unless @env.key?(varname)
  exec_path = @env[varname]
  output = %x(#{exec_path} -h 2>&1)
  raise "Error executing: #{exec_path} -h" unless $CHILD_STATUS.success?
  return output
end

def include_usage
  generate_help(:ASCLI).gsub(%r{(current=).*(/.aspera/)}, '\1/user_home\2')
end

def include_asession
  generate_help(:ASESSION)
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
  ['TST_SYNC_LCL_DIR', '/data/local_sync'],
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
    File.open(@env[:TEST_MAKEFILE]) do |file|
      file.each_line do |line|
        next unless line.include?('$(INCMAN)')
        line = line.chomp
        REPLACEMENTS.each{ |replace| line = line.gsub(replace.first, replace.last)}
        line = line.strip.squeeze(' ')
        $stderr.puts line if ENV['DEBUG']
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
  puts(configuration.to_yaml)
end

# main function to generate README.md
def generate_doc
  # parameters
  @env = {}
  %i[TEMPLATE ASCLI ASESSION TEST_MAKEFILE GEMSPEC GEMFILE].each do |var|
    @env[var] = ARGV.shift
    raise "Missing arg: #{var}" if @env[var].nil?
  end
  # get current plugins
  plugin_manager = Aspera::Cli::PluginFactory.instance
  plugin_manager.add_lookup_folder(Aspera::Cli::Plugins::Config.gem_plugins_folder)
  plugin_manager.add_plugins_from_lookup_folders
  @undocumented_plugins = plugin_manager.plugin_list
  puts ERB.new(File.read(@env[:TEMPLATE])).result(Kernel.binding)
  $stderr.puts("Warning: Undocumented plugins: #{@undocumented_plugins}") unless @undocumented_plugins.empty?
  # check that all test commands are included in the doc
  if !all_test_commands_by_plugin.empty?
    $stderr.puts("Those plugins not included in doc: #{all_test_commands_by_plugin.keys.join(', ')}".red)
    raise 'Remediate: remove from doc using EXE_NO_MAN or add section in doc'
  end
end
