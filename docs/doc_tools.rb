#!/usr/bin/env ruby
# frozen_string_literal: true

# cspell:ignore geminstadd transferspec passcode emea

# Tools used in README.erb.md

# get transfer spec parameter description
require 'aspera/environment'
require 'aspera/cli/info'
require 'aspera/cli/plugin_factory'
require 'aspera/cli/plugins/config'
require 'aspera/cli/main'
require 'aspera/transfer/spec_doc'
require 'aspera/log'
require 'aspera/rest'
require 'yaml'
require 'erb'
require 'English'

# Log control
Aspera::Log.instance.level = :info
Aspera::Log.instance.level = ENV['ASPERA_CLI_DOC_DEBUG'].to_sym if ENV['ASPERA_CLI_DOC_DEBUG']
Aspera::RestParameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}

HTML_BREAK = '<br/>'

# Format special values to markdown
class MarkdownFormatter
  class << self
    def special_format(special)
      "&lt;#{special}&gt;"
    end

    def check_row(row)
      row.each_key do |k|
        row[k] = row[k].join(HTML_BREAK) if row[k].is_a?(Array)
        row[k] = '&nbsp;' if row[k].to_s.strip.empty?
      end
    end

    def keyword_highlight(value)
      "`#{value}`"
    end

    def tick(bool)
      bool ? 'Y' : ' '
    end
  end
end

# :reek:TooManyMethods
class DocHelper
  # REMOVED_OPTIONS = %w[insecure].freeze
  KEEP_HOSTS = %w[localhost 127.0.0.1].freeze
  SAMPLE_EMAIL = 'my_user@example.com'
  SHORT_LINK = 'https://aspera.pub/MyShOrTlInK'
  SECRET_QUERIES = %w[token passcode context].freeze
  class << self
    # main function to generate template configuration file for tests
    # hide sensitive information
    def generate_generic_conf
      local_config = ENV['ASPERA_CLI_TEST_CONF_FILE']
      raise 'missing env var ASPERA_CLI_TEST_CONF_FILE: local config file' if local_config.nil?
      raise "Missing conf file: #{local_config}" if !File.exist?(local_config)
      configuration = YAML.load_file(local_config)
      configuration.each do |k, preset_hash|
        preset_hash.each do |param_name, param_value|
          param_value.map!{ |fqdn| fqdn.gsub('aspera-emea', 'example')} if param_name.eql?('ignore_certificate') && param_value.is_a?(Array) && param_value.all?(String)
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
            next
          end
          if param_name.eql?('bucket_name') || param_name.eql?('bucket')
            preset_hash[param_name] = 'my_bucket'
            next
          end
          if param_value.is_a?(String) && param_value.start_with?('/')
            preset_hash[param_name] = "/my_#{param_name}"
            next
          end
          begin
            uri = URI.parse(param_value)
            if uri.scheme.nil? ||
                uri.host.nil? ||
                KEEP_HOSTS.include?(uri.host)
              nil
            elsif uri.host.eql?('aspera.pub')
              preset_hash[param_name] = SHORT_LINK
              next
            else
              uri.host = if uri.host.end_with?('.ibmaspera.com')
                'example.ibmaspera.com'
              else
                uri.host.gsub('aspera-emea', 'example').gsub('asperademo', 'example').gsub('my_local_server', '127.0.0.1')
              end
              if uri.query.is_a?(String)
                SECRET_QUERIES.each do |key|
                  uri.query = uri.query.gsub(/(&?)#{key}=[^&]*/){"#{::Regexp.last_match(1)}#{key}=some_#{key}"}
                end
              end
              preset_hash[param_name] = uri.to_s
            end
          rescue URI::InvalidURIError
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
        end
      end
      File.open(ARGV.shift, 'w') do |f|
        f.puts(configuration.to_yaml)
      end
    end
  end
  # Place warning in generated file
  def doc_warn(_)
    'DO NOT EDIT: THIS FILE IS GENERATED, edit docs/README.erb.md, for details, read docs/README.md'
  end

  # Line break in tables
  def br; HTML_BREAK; end

  # To the power of
  def pow(value); "<sup>#{value}</sup>"; end

  # Just command name
  def cmd; Aspera::Cli::Info::CMD_NAME; end

  # Just command name
  def gem; Aspera::Cli::Info::GEM_NAME; end

  # (Markdown) used in text with formatting of command
  def tool; "`#{cmd}`"; end

  # Env var for option
  def opt_env(option); "#{cmd.upcase}_#{option.to_s.upcase}"; end

  # Container image in docker hub
  def container_image; Aspera::Cli::Info::CONTAINER; end

  def gemspec
    @gem_spec = Gem::Specification.load(@paths[:gemspecfile]) || raise("error loading #{@paths[:gemspecfile]}") if !@gem_spec
    @gem_spec
  end

  # If version contains other characters than digit and dot, it is pre-release
  def geminstadd; /[^\.0-9]/.match?(gemspec.version.to_s) ? ' --pre' : ''; end

  # Build markdown table with optional gems
  def gem_opt_md_list
    columns = %i[name version comment].freeze
    data = gem_opt_list.map do |g|
      columns.map{ |c| g[c]}
    end
    data.unshift(columns)
    markdown_table(data)
  end

  # Build installation commands for optional gems
  def gem_opt_cmd
    gem_opt_list.map do |g|
      "gem install #{g[:name]} -v '#{g[:version]}'"
    end.join("\n")
  end

  # Get list of optional gems
  # not super strict, but it gets comments
  def gem_opt_list
    File.read(@paths[:gemfile]).lines.filter_map do |l|
      m = l.match(/^ *gem\('([^']+)', '([^']+)'\)(.*)/)
      next nil unless m
      {
        name:    m[1],
        version: m[2],
        comment: m[3].gsub('# ', '').strip.sub('unless defined?(JRUBY_VERSION)', '(no jruby)').sub('if defined?(JRUBY_VERSION)', '(jruby)')
      }
    end
  end

  # Get list of optional gems
  # more reliable but missing comments
  def gem_opt_list_unused
    require 'bundler'
    # Load the definition from the Gemfile and Gemfile.lock
    definition = Bundler::Definition.build(@paths[:gemfile], "#{@paths[:gemfile]}.lock", nil)
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

  # Generate markdown from the provided 2D table
  def markdown_table(table)
    headings = table.shift
    # get max width of each columns
    col_widths = table.transpose.map do |col|
      [col.flat_map{ |c| c.to_s.delete('`').split(HTML_BREAK).map(&:size)}.max, 80].min
    end
    table.unshift(col_widths.map{ |col_width| '-' * col_width})
    table.unshift(headings)
    return table.map{ |line| "| #{line.map{ |i| i.to_s.gsub('\\', '\\\\').gsub('|', '\|')}.join(' | ')} |\n"}.join.chomp
  end

  # Generate markdown list from the provided list
  def markdown_list(items)
    items.map{ |i| "- #{i}"}.join("\n")
  end

  # Transfer spec description generation for markdown manual
  def spec_table
    agents = Aspera::Transfer::SpecDoc::AGENT_LIST.map{ |i| [i.last.upcase, i[1]]}
    agents.unshift(%w[ID Name])
    fields, data = Aspera::Transfer::SpecDoc.man_table(MarkdownFormatter, include_option: true, agent_columns: false)
    props = data.map{ |param| fields.map{ |field_name| param[field_name]}}
    # Column titles
    props.unshift(fields.map(&:capitalize))
    props.first[0] = 'Field'
    [markdown_table(agents), markdown_table(props)].join("\n\n")
  end

  # @return the minimum ruby version from gemspec
  def ruby_minimum_version
    requirement = gemspec.required_ruby_version.to_s
    raise "gemspec version must be generic, i.e. like '>= x.y', not specific like '#{requirement}'" if gemspec.required_ruby_version.specific?
    return requirement.gsub(/^[^0-9]*/, '')
  end

  # get minimum required Ruby version and future one
  def ruby_version
    message = "version: #{gemspec.required_ruby_version}"
    message += ".\n\n> [!WARNING]\n> The minimum Ruby version will be #{Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION} in a future version" unless ruby_minimum_version.eql?(Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION)
    return message
  end

  # generate help for the given command
  # @paths varname name of tool
  def generate_help(tool_name)
    # if tool_name.eql?(:ascli)
    #  tool = Aspera::Cli::Main.new({})
    #  tool.init_agents_options_plugins
    #  tool.show_usage(exit: false)
    #  return
    # end
    raise "missing #{tool_name}" unless @paths.key?(tool_name)
    exec_path = @paths[tool_name]
    # Add library path for Ruby CLI execution
    lib_path = File.expand_path('../lib', File.dirname(exec_path))
    output = %x(ruby -I #{lib_path} #{exec_path} -h 2>&1).gsub(/^Ignoring.+Try: gem pristine.*\n/, '')
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
      File.open(@paths[:makefile]) do |file|
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

  def sample_commands_title(plugin_name)
    "Tested commands for `#{plugin_name}`"
  end

  def include_commands_for_plugin(plugin_name)
    commands = all_test_commands_by_plugin.delete(plugin_name.to_s)
    raise "plugin #{plugin_name} not found in test makefile" if commands.nil?
    @undocumented_plugins.delete(plugin_name.to_sym)
    return "### #{sample_commands_title(plugin_name)}\n\n> [!NOTE]\n> Add `#{cmd} #{plugin_name}` in front of the following commands:\n\n```bash\n#{commands.join("\n")}\n```"
  end

  def include_commands
    all = []
    all_test_commands_by_plugin.each_value do |v|
      all.concat(v)
    end
    return all.join("\n")
  end

  # read markdown file line by line, and check that all links are valid
  # ignore links starting with https:// or #, other links are considered as file paths
  def check_links(file_path)
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
          raise "Invalid link: no such file: #{link_url} (#{link_text})" unless File.exist?(File.join('..', link_url))
        end
      end
    end
  end

  def initialize(args)
    @commands = nil
    @gem_spec = nil
    @undocumented_plugins = nil
    @paths = {}
    %i[outfile template ascli asession makefile gemspecfile gemfile].each do |name|
      @paths[name] = args.shift
      raise "Missing arg: #{name}" if @paths[name].nil?
    end
  end

  # main function to generate README.md
  def generate
    check_links(@paths[:template]) if ENV['ASPERA_CLI_DOC_CHECK_LINKS']
    # get current plugins
    plugin_manager = Aspera::Cli::PluginFactory.instance
    plugin_manager.add_lookup_folder(Aspera::Cli::Plugins::Config.gem_plugins_folder)
    plugin_manager.add_plugins_from_lookup_folders
    @undocumented_plugins = plugin_manager.plugin_list
    tmp_file = [@paths[:outfile], 'tmp'].join('.')
    File.open(tmp_file, 'w') do |f|
      f.puts(ERB.new(File.read(@paths[:template]).sub("-->\n", "-->\n<!-- markdownlint-disable MD033 -->\n")).result(binding))
    end
    Aspera::Log.log.warn("Undocumented plugins: #{@undocumented_plugins}") unless @undocumented_plugins.empty?
    # check that all test commands are included in the doc
    if !all_test_commands_by_plugin.empty?
      Aspera::Log.log.error("Those plugins not included in doc: #{all_test_commands_by_plugin.keys.join(', ')}".red)
      raise 'Remediate: remove from doc using EXE_NO_MAN or add section in doc'
    end
    File.rename(tmp_file, @paths[:outfile])
  end
end

def generate_doc
  # no unicode
  Aspera::Environment.force_terminal_c
  DocHelper.new(ARGV).generate
end

def generate_generic_conf
  DocHelper.generate_generic_conf
end
