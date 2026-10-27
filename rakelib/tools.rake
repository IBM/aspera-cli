# frozen_string_literal: true

require_relative '../build/lib/build_tools'
require 'aspera/uri_reader'
require 'aspera/rest'
require 'aspera/assert'
require 'json'
require 'yaml'
require 'zlib'
include BuildTools
include Paths

# Scan of secrets: files with fake secrets (unit tests, examples in API specifications)
SECRETS_EXCLUDED_FILES = ['^\.secrets\.baseline$', '^spec/', '^lib/aspera/schema/IBM.*\.yaml$'].freeze
# Scan of secrets: fake secrets in documentation, examples and integration tests
SECRETS_EXCLUDED_VALUES = ['^my_[a-z_]+_here$', '^your value here$', '^Bearer ', '^your-', '^sim$', '^S3cret', '^password$', '^DOCKERHUB_'].freeze
# Ruby versions available in ruby/setup-ruby (CI)
RUBY_SETUP_VERSIONS_URL = 'https://raw.githubusercontent.com/ruby/setup-ruby/refs/heads/master/ruby-builder-versions.json'
# Tags of the Ruby container image
RUBY_IMAGE_TAGS_URL = 'https://hub.docker.com/v2/repositories/library/ruby/tags'
# AppStream repository of UBI (same Ruby module streams as RHEL), for a major version of RHEL
UBI_APPSTREAM_URL = 'https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi%<major>d/%<major>d/x86_64/appstream/os'

# @param url [String] URL
# @return [Boolean] `true` if the URL exists: success, or redirect (not followed)
def url_exist?(url)
  response = Aspera::Rest::Client.new(base_url: url).call(operation: 'HEAD', exception: false, ret: :resp)
  response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
end

# @return [Array<String>] Stable Ruby versions (`X.Y.Z`, no -preview, -rc, etc.) in setup-ruby (CI)
def ruby_setup_versions
  raw = Aspera::Rest::Client.new(base_url: RUBY_SETUP_VERSIONS_URL, redirect_max: 3).read(nil)
  data = raw.is_a?(String) ? JSON.parse(raw) : raw
  data['ruby'].grep(/\A\d+\.\d+\.\d+\z/)
end

# @return [Array<String>] Stable Ruby versions with a source archive (Linux packages, `RUBY_SOURCE_BASE_URL` of linuxtgz.rake)
def ruby_source_versions
  Aspera::Rest::Client.new(base_url: "#{RUBY_SOURCE_BASE_URL}/index.txt", redirect_max: 3).read(nil).scan(/^ruby-(\d+\.\d+\.\d+)\t/).flatten
end

# A tag may exist before its release is published: check the archive used by the Windows zip (`RUBY_RELEASES_BASE_URL` of windowszip.rake)
# @return [Boolean] `true` if the RubyInstaller release of Ruby version with suffix is published (Windows zip)
def ruby_installer?(version, ext)
  url_exist?("#{RUBY_RELEASES_BASE_URL}/download/RubyInstaller-#{version}#{ext}/rubyinstaller-#{version}#{ext}-x64.7z")
end

# @return [String, nil] Suffix of the latest published RubyInstaller release of Ruby version (e.g. `-2`), `nil` if none
def ruby_installer_ext(version)
  last = (1..).find { |n| !ruby_installer?(version, "-#{n}") } - 1
  last.zero? ? nil : "-#{last}"
end

# @return [Boolean] `true` if the Ruby container image exists (container image)
def ruby_image?(version)
  url_exist?("#{RUBY_IMAGE_TAGS_URL}/#{version}")
end

# Highest Ruby version available for CI and all packages: setup-ruby, source archive, RubyInstaller and container image
# @param setup_versions [Array<String>] Versions in setup-ruby
# @return [Array(String, String)] Ruby version and suffix of its latest RubyInstaller release (e.g. `4.0.7`, `-2`)
def ruby_latest_common(setup_versions = ruby_setup_versions)
  (setup_versions & ruby_source_versions).sort_by { |v| Gem::Version.new(v) }.reverse_each do |version|
    next unless ruby_image?(version)
    ext = ruby_installer_ext(version)
    return version, ext unless ext.nil?
  end
  raise 'No Ruby version available in setup-ruby, source archives, RubyInstaller and container images'
end

# Ruby module streams (dnf) of RHEL, from the module metadata of the UBI AppStream repository
# Parsed with regular expressions: downloaded YAML is not deserialized
# @param major [Integer] Major version of RHEL
# @return [Array<String>] Streams, lowest first (e.g. `3.1`, `3.3`)
def ubi_ruby_streams(major)
  repo = format(UBI_APPSTREAM_URL, major: major)
  rest = Aspera::Rest::Client.new(base_url: repo, redirect_max: 3)
  modules_path = rest.read('repodata/repomd.xml')[/<data type="modules">.*?<location href="([^"]+)"/m, 1] || raise("No module metadata in #{repo}")
  Zlib.gunzip(rest.read(modules_path))
    .split(/^---$/)
    .select { |doc| doc.match?(/^document: modulemd$/) && doc[/^  name: (\S+)$/, 1].eql?('ruby') }
    .filter_map { |doc| doc[/^  stream: "?([\d.]+)"?$/, 1] }
    .uniq
    .sort_by { |v| Gem::Version.new(v) }
end

namespace :tools do
  desc 'Show changes since latest tag'
  task changes: [] do
    latest_tag = run(*%w[git describe --tags --abbrev=0], mode: :capture).first.chomp
    log.info("Changes since #{latest_tag}")
    run('git', 'log', "#{latest_tag}..HEAD", '--oneline', env: {'PAGER'=>''})
  end
  # https://github.com/Yelp/detect-secrets
  desc 'Init scan of secrets'
  task scan_init: [] do
    run('detect-secrets', 'scan', *SECRETS_EXCLUDED_FILES.flat_map { |i| ['--exclude-files', i] }, *SECRETS_EXCLUDED_VALUES.flat_map { |i| ['--exclude-secrets', i] })
  end
  desc 'Scan secrets'
  task scan: [] do
    run('detect-secrets', 'scan', '--baseline', '.secrets.baseline')
  end
  desc 'Rubocop'
  task rubocop: [] do
    run('rubocop', LIB)
  end
  desc 'Reek'
  task reek: [] do
    run('reek', '-c', TOP / '.reek.yml')
  end
  desc 'Semgrep'
  task semgrep: [] do
    run('semgrep', 'scan', '--config', 'auto')
  end
  desc 'Check spelling (cspell): configuration .cspell.json, project dictionaries in .cspell/'
  task spell: [] do
    run('cspell', '--no-progress', '--dot', '**')
  end

  desc 'Remove all installed gems'
  task clean_gems: [] do
    gems_dir = File.join(Gem.dir, 'gems')
    if Dir.exist?(gems_dir) && !Dir.empty?(gems_dir)
      gem_names =
        Dir.children(gems_dir)
          .map { |d| d.sub(/-[0-9].*$/, '') }
          .uniq
          .sort
      run('gem', 'uninstall', '-a', '-x', '-I', *gem_names)
    end
    GEMFILE_LOCK.delete
    run('gem', 'install', 'bundler')
  end

  PROTO_PATH = TMP / 'protos'
  GRPC_DEST = LIB
  desc 'Build Transfer SDK stub from proto'
  task grpc: [] do
    PROTO_PATH.mkpath
    download_proto_file(PROTO_PATH)
    run('grpc_tools_ruby_protoc', "--proto_path=#{PROTO_PATH}", "--ruby_out=#{GRPC_DEST}", "--grpc_out=#{GRPC_DEST}", PROTO_PATH / 'transferd.proto')
  end

  task :check_signature do
    run('gem', 'specification', built_gem_file, 'signing_key', 'cert_chain', 'version')
  end

  desc 'Show gem build version'
  task :version do
    puts BuildTools.build_version
  end

  desc 'Prepare beta version'
  task :version_override, [:version] do |_t, args|
    Aspera.assert(!args[:version].to_s.empty?) { 'Version argument is required for beta task' }
    OVERRIDE_VERSION_FILE.write(args[:version])
    puts("Beta version set to: #{BuildTools.build_version}")
  end

  desc 'Download OpenAPI schemas from GitHub'
  task :openapi do
    config_file = TOP / 'docs' / 'openapi_sources.yaml'
    Aspera.assert(File.exist?(config_file), "Configuration file not found: #{config_file}")
    config = YAML.load_file(config_file)
    Aspera.assert(config['schemas'], "No 'schemas' section found in configuration file")
    config['schemas'].each do |schema|
      url = schema['url']
      destination = TOP / schema['destination']
      log.info("Downloading: #{url}")
      log.info("Destination: #{destination}")
      begin
        # Download the file content using UriReader
        content = Aspera::UriReader.read(url)
        # Add header comment with source URL and warning
        header = <<~HEADER
          # DO NOT EDIT THIS FILE MANUALLY
          # This file is automatically downloaded from:
          # #{url}
          # Use 'rake tools:openapi' to update this file

        HEADER
        # Write the header and content to the destination file
        destination.write(header + content)
      end
    end
    log.info('All OpenAPI schemas downloaded successfully')
  end

  desc 'Update Ruby version to the latest available for CI and all packages: Aspera::Cli::Info, .ruby-version and GitHub Actions workflows'
  task :update_ruby do
    # Source of truth for CI: the version list used by ruby/setup-ruby itself.
    log.info("Fetching Ruby versions from: #{RUBY_SETUP_VERSIONS_URL}")
    setup_versions = ruby_setup_versions
    raise 'No stable Ruby versions found' if setup_versions.empty?

    # Latest release available for CI and all packages — tested version, in Aspera::Cli::Info and .ruby-version.
    latest_str, latest_ext = ruby_latest_common(setup_versions)
    log.info("Latest stable Ruby version: #{setup_versions.max_by { |v| Gem::Version.new(v) }}, available for CI and all packages: #{latest_str} (RubyInstaller#{latest_ext})")

    # Minimum supported version (e.g. "3.2" → [3, 2]), and minor line of the tested version.
    min_ver = Aspera::Cli::Info::RUBY_MINIMUM_VERSION.split('.').map(&:to_i)
    log.info("Minimum Ruby version: #{Aspera::Cli::Info::RUBY_MINIMUM_VERSION}")
    tested_ver = latest_str.split('.').first(2).map(&:to_i)

    # One "X.Y" entry per minor line, from min_ver up to the tested one, plus jruby.
    # setup-ruby resolves "X.Y" to the latest patch automatically.
    minor_lines = setup_versions
      .map { |v| v.split('.').first(2).map(&:to_i) }
      .uniq
      .sort
      .grep(min_ver..tested_ver)
      .map { |maj, min| "#{maj}.#{min}" }
    test_matrix = minor_lines + ['jruby']
    log.info("Test matrix: #{test_matrix.inspect}")

    updated = []

    # 1. Tested Ruby version (reference) and suffix of its latest RubyInstaller release: Aspera::Cli::Info
    info_file = LIB / 'aspera/cli/info.rb'
    content = info_file.read
    new_content = content
      .sub(/(?<=RUBY_TESTED_VERSION = ')[^']+/, latest_str)
      .sub(/(?<=WINDOWS_RUBY_INSTALLER_EXT = ')[^']+/, latest_ext)
    if new_content != content
      info_file.write(new_content)
      updated << info_file.basename.to_s
      log.info("Updated: #{info_file.relative_path_from(TOP)}")
    end

    # 2. Fixed Ruby version for all workflows (setup-ruby and Ruby build in packages.yml): .ruby-version
    ruby_version_file = TOP / '.ruby-version'
    if ruby_version_file.read.strip != latest_str
      ruby_version_file.write("#{latest_str}\n")
      updated << ruby_version_file.basename.to_s
      log.info("Updated: #{ruby_version_file.relative_path_from(TOP)}")
    end

    workflows_dir = TOP / '.github' / 'workflows'
    workflows_dir.glob('*.yml').sort.each do |workflow_file|
      content = workflow_file.read
      new_content = content.dup

      # 3. Matrix list in the `unit` job of test.yml:  ruby: ["X.Y", ..., "jruby"]
      # The pattern matches the list only when it follows the `unit:` job block
      # (i.e. before the `test:` job block starts).
      new_content.gsub!(/(^unit:.*?ruby: )\["[\d.]+"(?:, "(?:[\d.]+|jruby)")*\]/m) do
        "#{Regexp.last_match(1)}[#{test_matrix.map { |v| %Q("#{v}") }.join(', ')}]"
      end

      # 4. Fixed ruby-version: "X.Y" in the `test` job of test.yml (latest minor line only).
      latest_minor = minor_lines.last
      new_content.gsub!(/(^  test:.*?ruby-version:\s)(["'])\d+\.\d+\2/m) do
        "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{latest_minor}#{Regexp.last_match(2)}"
      end

      if new_content != content
        workflow_file.write(new_content)
        updated << workflow_file.basename.to_s
        log.info("Updated: #{workflow_file.relative_path_from(TOP)}")
      end
    end

    if updated.empty?
      log.info('All files already use the latest Ruby version — nothing to update.')
    else
      log.info("Updated #{updated.size} file(s): #{updated.join(', ')}")
    end
  end

  desc 'Check consistency of Ruby versions in files, and availability of the tested one; reference: Aspera::Cli::Info (minimum, future minimum, tested)'
  task :check_ruby do
    min = Aspera::Cli::Info::RUBY_MINIMUM_VERSION
    future = Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION
    tested = Aspera::Cli::Info::RUBY_TESTED_VERSION
    tested_minor = tested[/\A\d+\.\d+/]
    log.info("Reference (Aspera::Cli::Info): minimum #{min}, future minimum #{future}, tested #{tested}")
    errors = []
    # @return [MatchData, nil] match of regex in file, error recorded if not found
    find = lambda do |file, regex|
      m = file.read.match(regex)
      errors << "#{file.relative_path_from(TOP)}: not found: #{regex.source}" if m.nil?
      m
    end
    # Record an error if value is not the expected one, else log the check
    same = lambda do |file, what, found, expected|
      if found.eql?(expected)
        log.info("OK: #{file.relative_path_from(TOP)}: #{what}: #{found}")
      else
        errors << "#{file.relative_path_from(TOP)}: #{what}: #{found.inspect}, expected #{expected.inspect}"
      end
    end
    # Record an error if version is less than minimum, else log the check
    not_less = lambda do |file, what, found, minimum|
      if Gem::Version.new(found) < Gem::Version.new(minimum)
        errors << "#{file.relative_path_from(TOP)}: #{what}: #{found}, less than #{minimum}"
      else
        log.info("OK: #{file.relative_path_from(TOP)}: #{what}: #{found} (>= #{minimum})")
      end
    end
    # Reference
    errors << "Aspera::Cli::Info::RUBY_FUTURE_MINIMUM_VERSION #{future} shall be greater than minimum #{min}" if Gem::Version.new(future) <= Gem::Version.new(min)
    errors << "Aspera::Cli::Info::RUBY_TESTED_VERSION #{tested} shall not be less than future minimum #{future}" if Gem::Version.new(tested) < Gem::Version.new(future)
    # RuboCop
    file = TOP / '.rubocop.yml'
    same.call(file, 'TargetRubyVersion', find.call(file, /TargetRubyVersion:\s*(\S+)/)&.[](1), min)
    # Test workflow: matrix from minimum to tested, job `test` with tested
    file = TOP / '.github/workflows/test.yml'
    matrix = find.call(file, /^\s*ruby: \[(.*?)\]/)&.[](1).to_s.scan(/"(\d+\.\d+)"/).flatten
    same.call(file, 'first version of matrix', matrix.first, min)
    same.call(file, 'last version of matrix', matrix.last, tested_minor)
    same.call(file, 'ruby-version of job test', find.call(file, /^  test:.*?ruby-version:\s*"(\d+\.\d+)"/m)&.[](1), tested_minor)
    # .ruby-version: used by all workflows (setup-ruby and Ruby build in packages.yml)
    file = TOP / '.ruby-version'
    same.call(file, 'Ruby version', file.read.strip, tested)
    # Workflows: any remaining fixed Ruby version shall be the tested one
    (TOP / '.github/workflows').glob('*.yml').sort.each do |workflow|
      workflow.read.scan(/ruby-version:\s*["'](\d+\.\d+\.\d+)["']/).flatten.each do |v|
        same.call(workflow, 'ruby-version', v, tested)
      end
    end
    # Ruby module streams of RHEL 8 (dnf) in files: at least the minimum, and available in UBI 8 (checked below)
    dnf_streams = {}
    # Ruby used to run rake in the Linux package build: RHEL 8 system Ruby (dnf module), not the tested version,
    # so it only needs to be at least the minimum
    file = TOP / '.github/workflows/packages.yml'
    dnf_streams[file] = find.call(file, /dnf module install -y ruby:(\d+\.\d+)/)&.[](1) || '0'
    not_less.call(file, 'dnf module ruby', dnf_streams[file], min)
    # Documentation
    file = TOP / 'README.md'
    same.call(file, 'Ruby version', find.call(file, /Install \*\*Ruby\*\* ≥ (\d+\.\d+)/)&.[](1), min)
    file = Paths::MD_MANUAL
    same.call(file, 'Required Ruby version', find.call(file, /Required Ruby version is version: >= (\d+\.\d+)/)&.[](1), min)
    same.call(file, 'Future minimum Ruby version', find.call(file, /The minimum Ruby version will be (\d+\.\d+) in a future version/)&.[](1), future)
    [Paths::MD_MANUAL, Paths::MD_ERB].each do |doc|
      dnf_streams[doc] = find.call(doc, /dnf module -y enable ruby:(\d+\.\d+)/)&.[](1) || '0'
      not_less.call(doc, 'dnf module ruby', dnf_streams[doc], min)
    end
    # Availability of the tested version for CI and all packages (network access: warning only if not reachable)
    file = LIB / 'aspera/cli/info.rb'
    ext = Aspera::Cli::Info::WINDOWS_RUBY_INSTALLER_EXT
    begin
      setup_versions = ruby_setup_versions
      {
        "setup-ruby: #{tested} (CI)"                                         => setup_versions.include?(tested),
        "source archive: ruby-#{tested}.tar.gz (Linux packages)"             => ruby_source_versions.include?(tested),
        "RubyInstaller release: RubyInstaller-#{tested}#{ext} (Windows zip)" => ruby_installer?(tested, ext),
        "container image: ruby:#{tested} (container image)"                  => ruby_image?(tested)
      }.each do |what, available|
        if available
          log.info("OK: #{file.relative_path_from(TOP)}: #{what}")
        else
          errors << "#{file.relative_path_from(TOP)}: not available: #{what}"
        end
      end
      latest, latest_ext = ruby_latest_common(setup_versions)
      log.warn("Latest Ruby available for CI and all packages: #{latest} (RubyInstaller-#{latest}#{latest_ext}), tested: #{tested} (RubyInstaller-#{tested}#{ext}): use `rake tools:update_ruby`") unless [latest, latest_ext].eql?([tested, ext])
    rescue StandardError => e
      log.warn("Availability of Ruby #{tested} not checked: #{e.class}: #{e.message}")
    end
    # Availability of Ruby module streams of RHEL 8 in UBI 8 (network access: warning only if not reachable)
    begin
      ubi_streams = ubi_ruby_streams(8)
      dnf_streams.each do |dnf_file, stream|
        if !ubi_streams.include?(stream)
          errors << "#{dnf_file.relative_path_from(TOP)}: not available: UBI 8 dnf module: ruby:#{stream} (available: #{ubi_streams.join(', ')})"
        elsif stream.eql?(ubi_streams.last)
          log.info("OK: #{dnf_file.relative_path_from(TOP)}: UBI 8 dnf module: ruby:#{stream}")
        else
          log.warn("#{dnf_file.relative_path_from(TOP)}: UBI 8 dnf module: ruby:#{stream}, latest: ruby:#{ubi_streams.last}")
        end
      end
    rescue StandardError => e
      log.warn("Availability of UBI 8 dnf module ruby not checked: #{e.class}: #{e.message}")
    end
    raise "Inconsistent Ruby versions:\n#{errors.join("\n")}" unless errors.empty?
    log.info('Ruby versions are consistent')
  end
end
