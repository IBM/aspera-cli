# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Tools used in README.erb.md

# get transfer spec parameter description
require_relative '../../lib/aspera/environment'
require_relative '../../lib/aspera/cli/info'
require_relative '../../lib/aspera/cli/error'
require_relative '../../lib/aspera/agent/factory'
require_relative '../../lib/aspera/cli/plugins/factory'
require_relative '../../lib/aspera/cli/plugins/config'
require_relative '../../lib/aspera/schema/documentation'
require_relative '../../lib/aspera/schema/registry'
require_relative '../../lib/aspera/sync/operations'
require_relative '../../lib/aspera/log'
require_relative '../../lib/aspera/rest'
require_relative '../../lib/aspera/markdown'
require_relative 'test_env'
require_relative 'paths'
require_relative 'build_tools'
require_relative 'markdown_formatter'
require_relative 'doc_markup'
require_relative '../../lib/aspera/rainbow'
require 'yaml'
require 'erb'
require 'date'
require 'json'
require 'open3'
require 'tmpdir'
require 'pathname'
using Rainbow

# Generates `README.md` from the ERB template `README.erb.md`
# Instance methods are callable without receiver from the ERB template
# :reek:TooManyMethods
class DocHelper
  include DocMarkup

  # Hosts kept as-is in URLs of the template configuration
  KEEP_HOSTS = %w[localhost 127.0.0.1].freeze
  # Replaces email addresses in the template configuration
  SAMPLE_EMAIL = 'my_user@example.com'
  # Replaces short links (`aspera.pub`) in the template configuration
  SHORT_LINK = 'https://aspera.pub/MyShOrTlInK'
  # URL query parameters whose value is replaced with a placeholder in the template configuration
  SECRET_QUERIES = %w[token passcode context].freeze
  # Preset fields shown as placeholder (`ph`) in doc: secrets, links containing a secret, identifiers
  PLACEHOLDER_FIELDS = /secret|pass|private_key|api_?key|access_key|token|cred|_link_|_id\z/
  class << self
    # Doc value for a reference to a preset field in a test command
    # @param field [String] Name of field in preset
    # @param file  [Boolean] Value is read from a file (`@file:`)
    # @return [String] Placeholder for secrets and identifiers, else example value `my_<field>`
    def preset_value(field, file: false)
      field = field.delete_suffix('_here')
      return "#{'@file:' if file}my_#{field}" unless field.match?(PLACEHOLDER_FIELDS)
      file ? "@file:#{DocMarkup.ph("#{field}_file")}" : DocMarkup.ph(field)
    end

    # Generate template configuration file for tests
    # Hide sensitive information: secrets, identifiers, emails, host names
    # @param configuration [Hash] Configuration: preset name => preset values (modified in place)
    # @param template      [Pathname] Path of generated template file
    # @return [void]
    def config_to_template(configuration, template)
      Aspera::Log.log.info { "Generating: #{template}" }
      configuration.each do |k, preset_hash|
        preset_hash.each do |param_name, param_value|
          param_value.map! { |fqdn| fqdn.gsub('aspera-emea', 'example') } if param_name.eql?('ignore_certificate') && param_value.is_a?(Array) && param_value.all?(String)
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
              # Replace secret values in query on the final string: `URI#query=` would escape placeholder
              preset_hash[param_name] = SECRET_QUERIES.reduce(uri.to_s) do |url, key|
                url.gsub(/([?&])#{key}=[^&#]*/) { "#{::Regexp.last_match(1)}#{key}=#{DocMarkup.ph(key)}" }
              end
            end
          rescue URI::InvalidURIError
            nil
          end
          case param_name
          when 'url'
          when 'username'
            preset_hash[param_name] = param_value.include?('@') ? SAMPLE_EMAIL : 'my_user'
            next
          when /address/, /password/, /secret/, /client_id/, /key$/, /crn/, /instance_id/, /pass$/, 'instance'
            preset_hash[param_name] = DocMarkup.ph(param_name)
            next
          end
        end
      end
      template.write(configuration.to_yaml)
    end
  end

  # List of supported log formatters
  # @return [String] Formatter names as inline code, separated by line breaks (for a table cell)
  def log_formatters
    Aspera::Log::FORMATTERS.map { |i| Aspera::Markdown.icode(i) }.join(br)
  end

  # Markdown table of exit codes
  # @return [String] Markdown table: code, description
  def exit_codes_md_table
    Aspera::Markdown.table([%w[Code Description]] + Aspera::Cli::ExitCode::DESCRIPTIONS.map { |code, description| [Aspera::Markdown.icode(code), description] })
  end

  # Gem specification, loaded once from the gemspec file
  # @return [Gem::Specification]
  def gemspec
    @gem_spec = Gem::Specification.load(@paths[:gem_spec_file]) || raise("error loading #{@paths[:gem_spec_file]}") if !@gem_spec
    @gem_spec
  end

  # Version of gem being built
  # @return [String]
  def build_version
    BuildTools.build_version
  end

  # Option of `gem install` for the gem version
  # If version contains other characters than digit and dot, it is pre-release
  # @return [String] ` --pre` for a pre-release, else empty
  def gem_install_option; /[^.0-9]/.match?(gemspec.version.to_s) ? ' --pre' : ''; end

  # Build markdown table with optional gems
  # @return [String] Markdown table: name, version, comment
  def gem_opt_md_list
    columns = %i[name version comment].freeze
    data = gem_opt_list.map do |g|
      columns.map { |c| g[c] }
    end
    data.unshift(columns)
    Aspera::Markdown.table(data)
  end

  # Build installation commands for optional gems
  # @return [String] One `gem install` command per line
  def gem_opt_cmd
    gem_opt_list.map do |g|
      "gem install #{g[:name]} -v '#{g[:version]}'"
    end.join("\n")
  end

  # Get list of optional gems, parsed from the Gemfile
  # Not super strict, but it gets comments
  # @return [Array<Hash{Symbol => String}>] Keys: `name`, `version`, `comment`
  def gem_opt_list
    File.read(@paths[:gemfile]).lines.filter_map do |l|
      m = l.match(/^ *gem\('([^']+)', '([^']+)'(?:, platforms: ([^)]+))?\)(.*)/)
      next nil unless m
      platform = case m[3]
                 when nil then nil
                 when ':jruby' then '(jruby)'
                 when '%i[ruby windows]' then '(no jruby)'
                 else raise "Unexpected platforms in Gemfile: #{m[3]}"
                 end
      {
        name:    m[1],
        version: m[2],
        comment: [platform, m[4].gsub('# ', '').strip].compact.join(' ').strip
      }
    end
  end

  # Get list of optional gems, using Bundler (alternative to `gem_opt_list`, unused)
  # More reliable but missing comments
  # @return [Array<Hash{Symbol => Object}>] Keys: `name`, `version` (requirement), `comment`
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

  # Generate table from schema
  # @param spec   [Aspera::Schema::Reader] Schema to document
  # @param kwargs [Hash] Additional options for `Aspera::Schema::Documentation`
  # @return [String] Markdown table, one row per field
  def spec_to_table(spec, **kwargs)
    table = Aspera::Schema::Documentation.new(MarkdownFormatter, spec, code_highlight: true, **kwargs).build.table
    # Multi-line cells joined with line breaks
    table = table.map { |row| row.map { |cell| Array(cell).join(Aspera::Markdown::HTML_BREAK) } }
    table[0] = table[0].map(&:capitalize)
    table[0][0] = 'Field'
    Aspera::Markdown.table(table)
  end

  # Generate table from schema registry path
  # @param schema_path [String] Path of schema in `Aspera::Schema::Registry`
  # @return [String] Markdown table, see `spec_to_table`
  def schema_to_table(schema_path)
    schema = Aspera::Schema::Registry.instance.reader(schema_path)
    spec_to_table(schema)
  end

  # Markdown table of transfer agents
  # @return [String] Markdown table: short identifier, name, sorted by identifier
  def agent_table
    Aspera::Markdown.table([%w[ID Name]] + Aspera::Agent::Factory::ALL.map { |_, v| [v[:short].upcase, v[:long]] }.sort_by { |a| a[0] })
  end

  # Get minimum required Ruby version and future one, from `Aspera::Cli::Info`
  # @return [String] Markdown text, with a warning if the future minimum version differs
  def ruby_version
    message = "version: >= #{Aspera::Cli::Info::RUBY_MINIMUM_VERSION}"
    message += ".\n\n> [!WARNING]\n> The minimum Ruby version will be #{Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION} in a future version" unless Aspera::Cli::Info::RUBY_MINIMUM_VERSION.eql?(Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION)
    return message
  end

  # Fetch lifecycle data from `endoflife.date` API with graceful fallback
  # @param product [String] Product name in `endoflife.date` (e.g. `ruby`, `rhel`, `ubuntu`)
  # @return [Array<Hash>, nil] One entry per release cycle (`cycle`, `eol`, ...), `nil` on failure
  def fetch_eol_data(product)
    begin
      rest = Aspera::Rest::Client.new(base_url: 'https://endoflife.date', redirect_max: 3)
      data = rest.call(operation: 'GET', subpath: "api/#{product}.json")
      return data if data.is_a?(Array)
    rescue StandardError => e
      Aspera::Log.log.warn("Could not fetch endoflife.date API for #{product}: #{e.message}")
    end
    nil
  end

  # Generate markdown table with Ruby version support policy
  # Uses built-in EOL dates if `endoflife.date` is not reachable
  # @return [String] Markdown table, one row per Ruby version >= 3.0, most recent first
  def ruby_support_table
    min_v = Aspera::Cli::Info::RUBY_MINIMUM_VERSION
    future_v = Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION
    tested_v = Aspera::Cli::Info::RUBY_TESTED_VERSION[/\A\d+\.\d+/]

    eol_data = fetch_eol_data('ruby') || [
      {'cycle' => '4.0', 'eol' => '2029-03-31'},
      {'cycle' => '3.4', 'eol' => '2028-03-31'},
      {'cycle' => '3.3', 'eol' => '2027-03-31'},
      {'cycle' => '3.2', 'eol' => '2026-03-31'},
      {'cycle' => '3.1', 'eol' => '2025-03-26'},
      {'cycle' => '3.0', 'eol' => '2024-04-23'}
    ]

    headers = ['Ruby Version', 'Official EOL Date', 'ascli Support End (EOL + 6 mo)', 'ascli Status']
    rows = []

    eol_data.each do |entry|
      cycle = entry['cycle'].to_s
      next if Gem::Version.new(cycle) < Gem::Version.new('3.0')

      eol = entry['eol']
      if eol.is_a?(String) && eol.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        eol_date = Date.parse(eol)
        ascli_eol = (eol_date >> 6).strftime('%Y-%m-%d')
        eol_str = eol
      else
        eol_str = 'Active'
        ascli_eol = 'Active'
      end

      status = if cycle.eql?(min_v)
        '**Supported (Current minimum)**'
      elsif cycle.eql?(future_v) && !min_v.eql?(future_v)
        '**Supported (Future minimum)**'
      elsif cycle.eql?(tested_v)
        '**Supported (Tested & Packaged)**'
      elsif Gem::Version.new(cycle) > Gem::Version.new(min_v)
        'Supported'
      else
        'End of Support'
      end

      rows << [cycle, eol_str, ascli_eol, status]
    end

    rows.sort_by! { |r| Gem::Version.new(r[0]) }.reverse!
    Aspera::Markdown.table([headers] + rows)
  end

  # Required GLIBC version for the tested Aspera Transfer SDK on Linux x86_64, from docs/sdk_location.yaml
  # @return [String] GLIBC version, `2.28` if not found
  def sdk_glibc_version
    sdk_version = Aspera::Cli::Info::SDK_VERSION
    yaml_file = Paths::DOC / 'sdk_location.yaml'
    return '2.28' unless yaml_file.exist?

    locations = YAML.safe_load(yaml_file.read)
    entry = locations.find { |l| l['version'].to_s.eql?(sdk_version) && l['platform'].eql?('linux-x86_64') }
    entry&.[]('transferd_glibc') || entry&.[]('ascp_glibc') || entry&.[]('comment')&.[](/(?:GLIBC|glibc)\s*([\d.]+)/, 1) || '2.28'
  rescue StandardError => e
    Aspera::Log.log.warn("Could not extract GLIBC version from sdk_location.yaml: #{e.message}")
    '2.28'
  end

  # Generate markdown table with supported Linux distributions, EOL dates, GLIBC and Ruby support
  # Releases past their EOL are skipped, for Ubuntu only LTS releases are listed
  # @return [String] Markdown table, one row per distribution release
  def linux_support_table
    today = Date.today
    glibc_min = sdk_glibc_version

    os_info = {
      'rhel' => {
        'cycles' => {
          '8'  => {'glibc' => '2.28', 'ruby' => '3.1, 3.3 (DNF module)', 'install_mode' => 'Gem (`dnf module enable ruby:3.3`), Portable, Container'},
          '9'  => {'glibc' => '2.34', 'ruby' => '3.0 (default), 3.1, 3.3 (DNF module)', 'install_mode' => 'Gem (`dnf module enable ruby:3.3`), Portable, Container'},
          '10' => {'glibc' => '2.39+', 'ruby' => '>= 3.3 (default)', 'install_mode' => 'Gem, Portable, Container'}
        }
      },
      'ubuntu' => {
        'cycles' => {
          '20.04' => {'glibc' => '2.31', 'ruby' => '2.7 (APT package)', 'install_mode' => 'Portable, Container, rbenv (OS Ruby < 3.2)'},
          '22.04' => {'glibc' => '2.35', 'ruby' => '3.0 (APT package)', 'install_mode' => 'Portable, Container, rbenv (OS Ruby < 3.2)'},
          '24.04' => {'glibc' => '2.39', 'ruby' => '3.2 (APT package)', 'install_mode' => 'Gem (`apt install ruby-full`), Portable, Container'},
          '26.04' => {'glibc' => '2.43+', 'ruby' => '>= 3.3 (APT package)', 'install_mode' => 'Gem, Portable, Container'}
        }
      }
    }

    rhel_eol = fetch_eol_data('rhel') || [
      {'cycle' => '10', 'eol' => '2035-05-31'},
      {'cycle' => '9', 'eol' => '2032-05-31'},
      {'cycle' => '8', 'eol' => '2029-05-31'}
    ]

    ubuntu_eol = fetch_eol_data('ubuntu') || [
      {'cycle' => '26.04', 'lts' => true, 'eol' => '2031-05-29'},
      {'cycle' => '24.04', 'lts' => true, 'eol' => '2029-05-31'},
      {'cycle' => '22.04', 'lts' => true, 'eol' => '2027-06-01'}
    ]

    headers = ['Linux Distribution', 'OS Support End (EOL)', "GLIBC (>= #{glibc_min})", 'OS Ruby Version(s)', 'ascli Support / Mode']
    rows = []

    rhel_eol.each do |entry|
      cycle = entry['cycle'].to_s
      meta = os_info['rhel']['cycles'][cycle]
      next unless meta

      eol = entry['eol'].to_s
      next if eol.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.parse(eol) < today

      os_glibc = meta['glibc'][/[\d.]+/]
      compat = Gem::Version.new(os_glibc) >= Gem::Version.new(glibc_min) ? 'Compatible' : 'Incompatible'

      rows << [
        "**RHEL / UBI #{cycle}**",
        eol,
        "#{meta['glibc']} (#{compat})",
        meta['ruby'],
        meta['install_mode']
      ]
    end

    ubuntu_eol.each do |entry|
      next unless entry['lts']
      cycle = entry['cycle'].to_s
      meta = os_info['ubuntu']['cycles'][cycle]
      next unless meta

      eol = entry['eol'].to_s
      next if eol.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.parse(eol) < today

      os_glibc = meta['glibc'][/[\d.]+/]
      compat = Gem::Version.new(os_glibc) >= Gem::Version.new(glibc_min) ? 'Compatible' : 'Incompatible'

      rows << [
        "**Ubuntu #{cycle} LTS**",
        eol,
        "#{meta['glibc']} (#{compat})",
        meta['ruby'],
        meta['install_mode']
      ]
    end

    Aspera::Markdown.table([headers] + rows)
  end

  # Generate help for the given command, by executing it with `-h`
  # Runs in an isolated home folder (empty but for a minimal config file), without `ASCLI_*` variables:
  # the help does not depend on the user's plugins, config file or environment.
  # @param tool_name [Symbol] Key of the executable in paths: `:ascli` or `:asession`
  # @return [String] Help text
  # @raise [RuntimeError] If the executable is unknown or fails
  def generate_help(tool_name)
    raise "missing #{tool_name}" unless @paths.key?(tool_name)
    exec_path = @paths[tool_name]
    # Add library path for Ruby CLI execution
    lib_path = File.expand_path('../lib', File.dirname(exec_path))
    command = ['ruby', '-I', lib_path, exec_path, '-h']
    output, status = Dir.mktmpdir('doc_home') do |home|
      # Existing config file: no warning "No config file found"
      File.write(File.join(home, 'config.yaml'), {'config' => {'version' => Aspera::Cli::VERSION}}.to_yaml)
      env = ENV.keys.grep(/^ASCLI_/).to_h { |k| [k, nil] }.merge('ASCLI_HOME' => home)
      Open3.capture2e(env, *command)
    end
    raise "Error executing: #{command.join(' ')}\nOutput:\n#{output}" unless status.success?
    return output.gsub(/^Ignoring.+Try: gem pristine.*\n/, '')
  end

  # Help of `ascli`, with user-specific home folder replaced
  # @return [String] Help text
  def include_usage
    generate_help(:ascli).gsub(%r{(current=).*(/.aspera/)}, '\1/user_home\2')
  end

  # Help of `asession`
  # @return [String] Help text
  def include_asession
    generate_help(:asession)
  end

  # Replacements applied to each argument of test commands for the doc, in order
  # Each entry: pattern ([String, Regexp]), replacement ([String, Proc] called with the `MatchData`)
  REPLACEMENTS_YAML = [
    # `@extend:` is shown only for embedded values other than presets (replaced by their value below), e.g. `@date:now-1h@`
    [/@extend:(.*)/m, ->(m) { m[1].gsub(/(?:@file:)?@preset:[^@]*@/, '').match?(/@[a-z]+:/) ? m[0] : m[1] }],
    ['.$(SecureRandom.uuid)', ''],
    [/\$\(TMP\)$/, '.'],
    [/\$\(\(?t\.saved_output( :|\(')([^)']+_id)'?.*\)/, DocMarkup.ph(:id)],
    [/\$\(t\.saved_output( :|\(')([^)']+)'?.*\)/, ->(m) { DocMarkup.ph(m[2]) }],
    [/@preset:([^_]+)_[^ ]+\.url/, 'https://\1.example.com/path'],
    # Value of a preset field: placeholder or example, see `preset_value`
    [/(@file:)?@preset:(?:[a-z0-9_]+|\$\([a-z_]+\)[a-z0-9_]*)\.([a-z0-9_]+)@?/, ->(m) { preset_value(m[2], file: !m[1].nil?) }],
    [/my_link_([a-z_]+)/, 'https://app.example.com/\1_path'],
    [%r{\$\(PATH_TMP_SYNCS / '[^']+'\)}, '/data/local_sync'],
    [%r{\$\([A-Z_]+ / '([^']+)'\)}, '\1'],
    ['$(PATH_SHARES_SYNC)', '/data/local_sync'],
    ['$(PATH_TST_LCL_FOLDER)', 'send_folder'],
    ['$(PATH_HOT_FOLDER)', 'hot_folder'],
    ['$(PATH_TST_ASC_LCL)', 'test_file.bin'],
    ['$(PATH_TST_UTF_LCL)', 'test_file.bin'],
    ['$(PATH_TST_LCL_FILE)', 'test_file.bin'],
    ['$(FILENAME_UNICODE)', 'test_file.bin'],
    ['$(FILENAME_ASCII)', 'test_file.bin'],
    ['$(PATH_FILE_LIST)', 'file_list.txt'],
    ['$(PATH_VAULT_FILE)', '/secure/vault_file'],
    ['$(PATH_SCRIPTS)', '/path/to/scripts'],
    ['$(path_file_pair_list)', 'file_pair_list.txt'],
    ['$(TMP / "localhost.p12")', '.../localhost.p12'],
    ['"docroot":"$(TMP)"', '"docroot":"/data"'],
    ['$(remote_host)', 'app.example.com'],
    # Generated secret, see `generated_secret` in tests/test_helpers.rb
    [/\$\(secret :[a-z0-9_]+\)/, DocMarkup.ph(:password)],
    [/\$\((?:name|t\.resolve :[a-z0-9_]+)\) \$\(TIMESTAMP_TEST_RUN\)/, 'package title'],
    [/^--base=.*/, '--base=test'],
    [/^(--[a-z\-.]+=)?((?:@[a-z]+:)*)(.*['"*! $\\?].*)$/, "\\1\\2'\\3'"]
  ].freeze

  # Test commands to include in doc (not tagged `no_doc`), with test values replaced (see `REPLACEMENTS_YAML`)
  # Computed once, entries are removed when included in doc
  # @return [Hash{Symbol => Array<String>}] Plugin name => sorted unique commands, without plugin name
  def all_test_commands_by_plugin
    return @commands unless @commands.nil?
    @commands = {}
    all_tests = TestEnv.descriptions
    all_tests.select { |_, v| v[:command] && !v[:tags].include?(:no_doc) && v[:plugin] }.each_value do |test|
      # Cleanup command line
      line = test[:args].reject { |cmd| cmd.to_s.start_with?('--preset=') || cmd.eql?('-N') }.map do |cmd|
        next cmd unless cmd.is_a?(String)
        next "''" if cmd.empty?
        REPLACEMENTS_YAML.each do |replace|
          cmd = replace.last.is_a?(Proc) ? cmd.gsub(replace.first) { replace.last.call(Regexp.last_match) } : cmd.gsub(replace.first, replace.last)
        end
        cmd
      end.join(' ')
      line = line.strip.squeeze(' ')
      Aspera::Log.log.debug(line)
      plugin = test[:plugin]
      @commands[plugin] ||= []
      @commands[plugin].push(line.gsub(/^#{plugin} /, ''))
    end
    @commands.each_key do |plugin|
      @commands[plugin] = @commands[plugin].sort.uniq
    end
    @commands
  end

  # Section with tested commands of a plugin, marks the plugin as documented
  # @param plugin_name_sym [Symbol] Plugin name
  # @param level           [Integer] Heading level of the section
  # @return [String] Markdown: heading, note, code block with commands
  # @raise [RuntimeError] If plugin has no test command, or was already included
  def include_commands_for_plugin(plugin_name_sym, level = 3)
    commands = all_test_commands_by_plugin.delete(plugin_name_sym)
    raise "Plugin #{plugin_name_sym} not found in test cases (#{all_test_commands_by_plugin.keys.join(',')})" if commands.nil?
    @undocumented_plugins.delete(plugin_name_sym)
    return [
      Aspera::Markdown.heading(sample_commands_title(plugin_name_sym), level: level),
      Aspera::Markdown.admonition(["Add `#{cmd} #{plugin_name_sym}` in front of the following commands:"], type: 'NOTE'),
      Aspera::Markdown.code(commands)
    ].join.chomp.chomp
  end

  # Manual section of a plugin bundle, ERB template `manual.erb.md` of the bundle folder, evaluated in the context of the main template
  # @param plugin_name_sym [Symbol] Bundle name
  # @return [String] Markdown
  # @raise [RuntimeError] If the bundle has no manual
  def include_plugin_manual(plugin_name_sym)
    file = Paths::LIB / 'aspera/plugins' / plugin_name_sym.to_s / 'manual.erb.md'
    raise "Bundle #{plugin_name_sym} has no manual: #{file}" unless file.file?
    return ERB.new(file.read, trim_mode: '-').result(binding)
  end

  # All tested commands not yet included in doc
  # @return [String] One command per line
  def include_commands
    all = []
    all_test_commands_by_plugin.each_value do |v|
      all.concat(v)
    end
    return all.join("\n")
  end

  # Heading whose text after a colon starts with a lowercase letter
  HEADING_PATTERN = /^#[^:]*: [a-z]/

  # Check that headings are capitalized after a colon
  # @param file_path [String] Path of markdown file
  # @return [void]
  # @raise [RuntimeError] If a heading is not capitalized
  def check_headings(file_path)
    error = false
    File.open(file_path) do |file|
      file.each_line do |line|
        if line.match?(HEADING_PATTERN)
          error = true
          Aspera::Log.log.error { "Heading shall be capitalized: #{line}" }
        end
      end
    end
    raise 'Check headings specified above' if error
  end

  # Read markdown file line by line, and check that all links are valid
  # Remote links are fetched, local links must exist, anchors and ERB links are skipped
  # @param file_path [String] Path of markdown file
  # @param folder [Pathname, nil] Folder that local links are relative to, default: the folder of the file
  # @return [void]
  # @raise [RuntimeError] If a local file does not exist
  def check_links_file(file_path, folder: nil)
    require 'uri'
    require 'net/http'
    file_folder = folder || Pathname.new(file_path).parent
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
            Aspera::Rest::Client.new(base_url: link_url, redirect_max: 5).call(operation: 'GET')
            next
          end
          file_path = Pathname.new(link_url)
          file_path = file_folder / file_path unless file_path.absolute?
          raise "Invalid link: no such file: #{file_path} (#{link_text})" unless file_path.exist?
        end
      end
    end
  end

  # Get paths of files from the command line arguments
  # @param args [Array<String>] Paths, in order: outfile, template, ascli, asession, makefile, gem_spec_file, gemfile (consumed)
  # @raise [RuntimeError] If an argument is missing
  def initialize(args)
    @commands = nil
    @gem_spec = nil
    @undocumented_plugins = nil
    @paths = {}
    %i[outfile template ascli asession makefile gem_spec_file gemfile].each do |name|
      @paths[name] = args.shift.to_s
      raise "Missing arg: #{name}" if @paths[name].empty?
    end
  end

  # Check links of the template `README.erb.md`, see `check_links_file`
  # @return [void]
  def check_links_manual
    check_links_file(@paths[:template])
    Paths::TOP.glob(Paths::BUNDLE_MANUAL_GLOB).each { |f| check_links_file(f, folder: Paths::DOC) }
  end

  # Generate README.md from README.erb.md
  # Checks that all plugins and all test commands are documented
  # @return [void]
  # @raise [RuntimeError] If test commands of a plugin are not included in doc
  def generate
    Aspera::Log.log.info("Generating markdown doc for version #{build_version}")
    check_headings(@paths[:template])
    Paths::TOP.glob(Paths::BUNDLE_MANUAL_GLOB).each { |f| check_headings(f) }
    # get current plugins
    plugin_manager = Aspera::Cli::Plugins::Factory.instance
    plugin_manager.add_lookup_folder(Aspera::Cli::Plugins::Config.gem_plugins_folder)
    plugin_manager.add_plugins_from_lookup_folders if plugin_manager.plugin_list.empty?
    @undocumented_plugins = plugin_manager.plugin_list
    Aspera::Log.log.info { "Generating: #{@paths[:outfile]}" }
    tmp_file = [@paths[:outfile], 'tmp'].join('.')
    File.open(tmp_file, 'w') do |f|
      f.puts(ERB.new(File.read(@paths[:template]).sub("-->\n", "-->\n<!-- markdownlint-disable MD033 -->\n"), trim_mode: '-').result(binding))
    end
    Aspera::Log.log.warn("Undocumented plugins: #{@undocumented_plugins}") unless @undocumented_plugins.empty?
    # check that all test commands are included in the doc
    all_test_commands_by_plugin.delete(:my_command)
    if !all_test_commands_by_plugin.empty?
      Aspera::Log.log.error("Those plugins not included in doc: #{all_test_commands_by_plugin.keys.map { |p| %Q{"#{p}"} }.join(', ')}".red)
      raise 'Remediate: remove from doc using tag `no_doc` or add section in doc'
    end
    File.rename(tmp_file, @paths[:outfile])
  end
end
