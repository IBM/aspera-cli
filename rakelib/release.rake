# frozen_string_literal: true

require 'pathname'
require 'tmpdir'
require 'aspera/markdown'
require 'aspera/environment'
require 'aspera/yaml'
require_relative '../build/lib/paths'
require_relative '../build/lib/build_tools'
require_relative '../build/lib/test_env'
include BuildTools

namespace :release do
  # Pre-release
  PRE_SUFFIX = '.pre'
  DATE_PLACE_HOLDER = 'Released: [Place date of release here]'

  private

  # Determine release versions
  # @param release_version [String] Release version (empty to use current version without .pre)
  # @param next_version [String] Next development version (empty to auto-increment minor)
  # @return [Hash<Symbol,String>] Versions: :current, :release, :next, :next_dev
  def release_versions(release_version, next_version)
    versions = {}
    versions[:current] = Aspera::Cli::VERSION
    versions[:release] =
      if release_version.to_s.empty?
        Aspera::Cli::VERSION.delete_suffix(PRE_SUFFIX)
      else
        release_version
      end
    versions[:release_tag] = "v#{versions[:release]}"
    versions[:next] =
      if next_version.to_s.empty?
        major, minor, _patch = versions[:release].split('.').map(&:to_i)
        [major, minor + 1, 0].join('.')
      else
        next_version
      end
    versions[:next_dev] = "#{versions[:next]}#{PRE_SUFFIX}"
    return versions
  end

  # Extract the latest changelog section (everything between first ## and second ##)
  # Strips the version heading and release date lines
  # @return [String] The changelog content for the latest version
  def extract_latest_changelog
    content = CHANGELOG_FILE.read

    # Match from first ## heading to the next ## heading (or end of file)
    match = content.match(/^(## .+?)(?=^## |\z)/m)
    raise 'Missing changelog' unless match

    section = match[1].strip
    # Remove the version heading (## X.Y.Z) and Released: line
    # Change heading level 3 to 2
    section.sub(/\A## .+\n+Released: .+\n*/, '').strip.gsub(/^### /, '## ')
  end

  # Format the tested server and agent versions table from YAML for inclusion in changelog / release notes
  # @return [String] Markdown section with server and agent versions table
  def server_versions_section
    return '' unless Paths::SERVERS_TESTED.exist?
    data = Aspera::Yaml.safe_load(Paths::SERVERS_TESTED.read)
    return '' if data.nil? || data.empty?

    sections = []

    # Support list format or hash format with servers/agents keys
    servers = data.is_a?(Hash) ? data['servers'] : data
    if servers.is_a?(Array) && !servers.empty?
      server_table = [%w[Plugin Product Version]]
      servers.sort_by { |s| s['plugin'].to_s }.each do |s|
        server_table << [
          Aspera::Markdown.icode(s['plugin']),
          s['product'],
          s['version']
        ]
      end
      sections << Aspera::Markdown.heading('Server Versions', level: 3)
      sections << "#{Aspera::Markdown.table(server_table)}\n\n"
    end

    agents = data.is_a?(Hash) ? data['agents'] : nil
    if agents.is_a?(Array) && !agents.empty?
      agent_table = [%w[Agent Product Version]]
      agents.sort_by { |a| a['agent'].to_s }.each do |a|
        agent_table << [
          Aspera::Markdown.icode(a['agent']),
          a['product'],
          a['version']
        ]
      end
      sections << Aspera::Markdown.heading('Transfer Agent Versions', level: 3)
      sections << "#{Aspera::Markdown.table(agent_table)}\n\n"
    end

    sections.join
  end

  # Insert or replace server & agent versions section in CHANGELOG.md for a given version
  # @param version [String] Version heading in CHANGELOG.md (e.g. '4.28.0.pre' or '4.28.0')
  def insert_or_replace_server_versions_in_changelog(version)
    server_section = server_versions_section
    return if server_section.empty?

    content = CHANGELOG_FILE.read
    match = content.match(/^(## #{Regexp.escape(version)}\n.+?)(?=\n## |\z)/m)
    raise "Version section #{version} not found in #{CHANGELOG_FILE}" unless match

    current_section = match[1]
    # Remove existing Server Versions and Transfer Agent Versions sections if present
    cleaned_section = current_section.sub(/\n### Server Versions\n.+?(?=\n### |\z)/m, '')
    cleaned_section = cleaned_section.sub(/\n### Transfer Agent Versions\n.+?(?=\n### |\z)/m, '')

    updated_section = "#{cleaned_section.rstrip}\n\n#{server_section.rstrip}\n"
    content.sub!(current_section, updated_section)
    CHANGELOG_FILE.write(content)
  end

  # Update `CHANGELOG.md` for release:
  # - Replace current version with release version
  # - Replace date placeholder with today's date
  # - Append tested server versions table
  # @param current_version [String] The current version (with `.pre`)
  # @param release_version [String] The release version (without `.pre`)
  def update_changelog_for_release(current_version, release_version)
    content = CHANGELOG_FILE.read
    today = Date.today.strftime('%Y-%m-%d')

    # Replace the .pre version heading with release version
    content.sub!("\n## #{current_version}\n", "\n## #{release_version}\n")

    # Replace the date placeholder
    raise 'Missing date place holder' unless content.include?(DATE_PLACE_HOLDER)
    content.sub!(DATE_PLACE_HOLDER, "Released: #{today}")
    CHANGELOG_FILE.write(content)

    insert_or_replace_server_versions_in_changelog(release_version)
  end

  # Add a new development section to `CHANGELOG.md` for the next version
  # @param next_version_dev [String] The next version (with .pre suffix)
  def add_next_changelog_section(next_version_dev)
    content = CHANGELOG_FILE.read

    new_section = [
      Aspera::Markdown.heading(next_version_dev, level: 2),
      Aspera::Markdown.paragraph(DATE_PLACE_HOLDER),
      Aspera::Markdown.heading('New Features', level: 3),
      Aspera::Markdown.heading('Issues Fixed', level: 3),
      Aspera::Markdown.heading('Breaking Changes', level: 3)
    ].join

    # Insert before the first section
    content.sub!("\n## ", "\n#{new_section}## ")

    CHANGELOG_FILE.write(content)
  end

  # Update version.rb with a new version
  # @param version [String] The new version string
  def update_version_file(version)
    content = VERSION_FILE.read
    content.sub!(/VERSION = '[^']+'/, "VERSION = '#{version}'")
    VERSION_FILE.write(content)
    log.info("Version file:\n#{Paths::VERSION_FILE.read}")
  end

  # @return [Pathname] Path to generated gem file
  def gem_file(version)
    Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{version}.gem"
  end

  # Check if the user has access to GitHub
  # Raises an error if not authenticated or does not have access
  def check_github_access
    drun('gh', 'api', 'user', out: File::NULL, err: File::NULL)
  end

  desc 'Bundle gem dependencies in a zip file'
  task gem_pack: [Paths::GEM_PACK]

  file Paths::GEM_PACK => ['build'] do
    tmp_dir = TMP / 'build_gem_pack'
    tmp_dir.mkpath
    get_dependency_gems(built_gem_file, tmp_dir)
    zip_directory(tmp_dir, Paths::GEM_PACK)
    tmp_dir.rmtree
    log.info("Gem pack: #{Paths::GEM_PACK}")
  end

  desc 'Create a new release: args: release_version, next_version'
  task :run, %i[release_version next_version] do |_t, args|
    check_gem_signing_key
    check_github_access

    # Determine versions
    versions = release_versions(args[:release_version], args[:next_version])
    log.info("Current version in version.rb: #{versions[:current]}")
    log.info("Release version: #{versions[:release]}")
    log.info("Next development version: #{versions[:next_dev]}")
    raise "Current version must end with #{PRE_SUFFIX}" unless versions[:current].end_with?(PRE_SUFFIX)
    porcelain_status = drun('git', 'status', '--porcelain', mode: :capture).first.strip
    raise "Git working tree not clean:\n#{porcelain_status}" unless porcelain_status.empty?

    # Release version + changelog
    update_version_file(versions[:release])
    update_changelog_for_release(versions[:current], versions[:release])

    # Extract release notes (temporary, not committed)
    release_notes_path = Pathname(Dir.tmpdir) / 'release_notes.md'
    release_notes_path.write(extract_latest_changelog)
    log.info("Release Notes:\n#{release_notes_path.read}")

    # Build PDF Manual for release
    Rake::Task['doc:build'].invoke
    # Build gem file
    Rake::Task[dry_run? ? 'unsigned' : 'signed'].invoke
    # Build gem pack
    Rake::Task['release:gem_pack'].invoke

    # Commit, Tag, Push release: CHANGELOG.md README.md version.rb
    drun('git', 'add', '-A')
    drun('git', 'commit', '-m', "Release #{versions[:release_tag]}")
    drun('git', 'tag', '-a', versions[:release_tag], '-m', "Version #{versions[:release]}")
    drun('git', 'push', 'origin', versions[:release_tag])

    # GitHub release: publishing it triggers workflow `packages.yml`, which attaches Linux and Windows packages
    drun(
      'gh',
      'release', 'create', versions[:release_tag],
      '--title', "Aspera CLI #{versions[:release_tag]}",
      '--notes-file', release_notes_path,
      Paths::PDF_MANUAL,
      gem_file(versions[:release]),
      Paths::GEM_PACK
    )

    # Prepare next development cycle
    update_version_file(versions[:next_dev])
    Paths::MD_MANUAL.delete
    Rake::Task[Paths::MD_MANUAL].reenable
    Rake::Task[Paths::MD_MANUAL].invoke
    add_next_changelog_section(versions[:next_dev])
    drun('git', 'add', '-A')
    drun('git', 'commit', '-m', "Prepare for next development cycle (#{versions[:next_dev]})")
    drun('git', 'push', 'origin', 'main')

    log.info("Release #{versions[:release]} completed")
  end

  desc 'Yank a gem version from RubyGems (arg: version)'
  task :yank, [:version] do |_t, args|
    version = args[:version].to_s.strip
    raise 'Missing version (usage: rake release:yank[1.2.3])' if version.empty?
    drun('gem', 'yank', Aspera::Cli::Info::GEM_NAME, '--version', version)
  end

  namespace :servers do
    desc 'Detect and update tested server versions in tests/servers_tested.yaml'
    task :update do
      # Mapping between preset names in test config and plugin symbols
      preset_plugins = {
        'node_user'     => :node,
        'f5_user'       => :faspex5,
        'shares_admin'  => :shares,
        'console_admin' => :console,
        'orch_user'     => :orchestrator,
        'aoc_user'      => :aoc,
        'tst_httpgw'    => :httpgw
      }

      # Plugin classes map
      plugin_classes = {
        node:         'Aspera::Cli::Plugins::Node',
        faspex5:      'Aspera::Cli::Plugins::Faspex5',
        shares:       'Aspera::Cli::Plugins::Shares',
        console:      'Aspera::Cli::Plugins::Console',
        orchestrator: 'Aspera::Cli::Plugins::Orchestrator',
        aoc:          'Aspera::Cli::Plugins::Aoc',
        httpgw:       'Aspera::Cli::Plugins::Httpgw'
      }

      # Require plugins
      plugin_classes.each_key do |plugin_name|
        require "aspera/cli/plugins/#{plugin_name}"
      end

      # Set 5 seconds timeout on HTTP sessions for detect and disable retries
      Aspera::Rest::Parameters.instance.session_cb = lambda do |http|
        http.open_timeout = 5
        http.read_timeout = 5
      end
      Aspera::Rest::Parameters.instance.retry_max = 0
      Aspera::Rest::Parameters.instance.retry_on_timeout = false
      Aspera::Rest::Parameters.instance.retry_on_error = false

      config = TestEnv.configuration
      if config.empty?
        log.warn("No test configuration available (#{TestEnv::ENV_VAR_REF_CONF} not set). Keeping existing #{Paths::SERVERS_TESTED}.")
        next
      end

      # Load current servers_tested or init empty
      raw_data = Paths::SERVERS_TESTED.exist? ? Aspera::Yaml.safe_load(Paths::SERVERS_TESTED.read) : {}
      servers_list = raw_data.is_a?(Hash) ? raw_data['servers'] || [] : (raw_data || [])
      agents_list = raw_data.is_a?(Hash) ? raw_data['agents'] || [] : []

      current_by_plugin = servers_list.to_h { |s| [s['plugin'].to_s, s] }

      preset_plugins.each do |preset_name, plugin_sym|
        preset_cfg = config[preset_name]
        next unless preset_cfg.is_a?(Hash) && preset_cfg['url']

        url = preset_cfg['url']
        plugin_class = Object.const_get(plugin_classes[plugin_sym])
        next unless plugin_class.respond_to?(:detect)

        product_name = plugin_class.respond_to?(:application_name) ? plugin_class.application_name : plugin_sym.to_s
        log.info("Detecting #{plugin_sym} at #{url}...")
        begin
          res = plugin_class.detect(url)
          version = nil
          if res.is_a?(Hash) && res[:version] && res[:version] != 'unknown' && res[:version] != 'requires authentication'
            version = res[:version].to_s
          elsif plugin_sym.eql?(:node) && preset_cfg['username'] && preset_cfg['password']
            # Fallback to authenticating with test preset credentials to get Node version via /info
            require 'aspera/api/node'
            node_api = Aspera::Api::Node.new(
              base_url: url,
              auth:     {
                type:     :basic,
                username: preset_cfg['username'],
                password: preset_cfg['password']
              }
            )
            info = node_api.read('info')
            version = info['version'] if info.is_a?(Hash) && info['version']
          end

          if version
            log.info("  Found #{plugin_sym} version: #{version}")
            current_by_plugin[plugin_sym.to_s] = {
              'plugin'  => plugin_sym.to_s,
              'product' => product_name,
              'version' => version
            }
          else
            log.warn("  Could not detect valid version for #{plugin_sym} at #{url} (keeping existing entry if any)")
          end
        rescue StandardError => e
          log.warn("  Detection failed for #{plugin_sym} at #{url}: #{e.message} (keeping existing entry if any)")
        end
      end

      # Write updated yaml
      sorted_servers = current_by_plugin.values.sort_by { |s| s['plugin'].to_s }
      sorted_agents = agents_list.sort_by { |a| a['agent'].to_s }
      result_hash = {
        'servers' => sorted_servers,
        'agents'  => sorted_agents
      }
      yaml_content = "# Tested server and transfer agent versions against this version of ascli\n#{result_hash.to_yaml.delete_prefix("---\n")}"
      Paths::SERVERS_TESTED.write(yaml_content)
      log.info("Updated #{Paths::SERVERS_TESTED}:\n#{Paths::SERVERS_TESTED.read}")
    end

    desc 'Insert or replace tested server & agent versions in CHANGELOG.md for the current version'
    task :changelog do
      current_ver = Aspera::Cli::VERSION
      insert_or_replace_server_versions_in_changelog(current_ver)
      log.info("Updated #{Paths::CHANGELOG_FILE} with server versions for #{current_ver}")
    end
  end
end
