# frozen_string_literal: true

require 'bundler'
require 'yaml'
require 'aspera/log'
require 'aspera/secret_hider'
require 'aspera/environment'
require 'aspera/cli/version'
require 'aspera/cli/parser'
require_relative 'paths'
require 'aspera/rainbow'
using Rainbow

module BuildTools
  # @see Aspera::Log#logger
  def log(*args, **kwargs, &block)
    Aspera::Log.instance.logger(*args, **kwargs, &block)
  end

  # Execute the command line (not in shell)
  # @see `Aspera::Environment#secure_execute`
  def run(*cmd, **kwargs)
    log.info("Executing: #{cmd.map { |i| Aspera::Environment.shell_escape_pretty(i.to_s) }.join(' ').sub(%r{^ruby -w [^ ]+ [^ ]+/bin/ascli }, 'ascli ')}")
    Aspera::Environment.secure_execute(*cmd, **kwargs)
  end

  # If env var `DRY_RUN` is set to `1`, then do not execute `git` and `gh` commands.
  def dry_run?
    ENV['DRY_RUN'] == '1'
  end

  # Execute command only if not dry run (env `DRY_RUN=1`)
  # @param git [Symbol] Name of executable
  def drun(*cmd, **kwargs)
    if dry_run?
      log.info("#{'Would execute'.red}: #{cmd.map { |i| Aspera::Environment.shell_escape_pretty(i.to_s) }.join(' ')}")
      return [''] if kwargs[:mode].eql?(:capture)
    else
      run(*cmd, **kwargs)
    end
  end

  # Extract gem specifications in a given group from the Gemfile
  # @param gemfile [String] Path to gem file
  # @param group_name_sym [Symbol] Group name
  # @return [Array<String>] List of gem specifications in the group
  def gems_in_group(gemfile, group_name_sym)
    Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil).dependencies.filter_map do |dep|
      next unless dep.groups.include?(group_name_sym)
      "#{dep.name}:#{dep.requirement.to_s.delete(' ')}"
    end
  end

  # Download gem and dependencies to folder
  # @param gem_location [String] Path to gem file or <name>:<version>
  # @param destination_path [Pathname] Path to folder where gems files will be stored
  def get_dependency_gems(gem_location, destination_path)
    tmp_install_ruby = TMP / 'gem_deps_cache'
    run('gem', 'install', gem_location, '--no-document', '--install-dir', tmp_install_ruby)
    (tmp_install_ruby / 'cache').each_child do |child|
      child.rename(destination_path / child.basename)
    end
    tmp_install_ruby.rmtree
  end

  # Read a file from a gem package
  # @param gem_path [Pathname] Path to .gem file
  # @param file     [String]   Path of file inside gem
  # @return [String] File content
  def gem_file_content(gem_path, file)
    require 'rubygems/package'
    require 'zlib'
    gem_path.open('rb') do |io|
      Gem::Package::TarReader.new(io).seek('data.tar.gz') do |data|
        Zlib::GzipReader.wrap(data) do |gz|
          Gem::Package::TarReader.new(gz).seek(file) do |entry|
            return entry.read
          end
        end
      end
    end
    raise "#{file} not found in #{gem_path}"
  end

  # Download a file
  # @param url  [String]   URL of file
  # @param dest [Pathname] Destination file path
  # @return [Pathname] Destination file path
  def download_file(url, dest)
    require 'aspera/rest'
    Aspera::Rest::Client.new(base_url: url.sub(%r{/[^/]+$}, ''), redirect_max: 5)
      .read(url.sub(%r{^.+/}, ''), save_to: dest)
    dest
  end

  # Gem to package: locally built gem file if present (e.g. during release, before it is published), else from rubygems.org
  # @param gem_version [String] Version of gem
  # @return [String] Local gem file path, or gem name and version
  def package_gem_location(gem_version)
    local_gem = Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version}.gem"
    location = local_gem.exist? ? local_gem.to_s : "#{Aspera::Cli::Info::GEM_NAME}:#{gem_version}"
    log.info("Using gem: #{location}")
    location
  end

  # Versions of SDK and Ruby tested with the packaged gem version
  # @param gem_file    [Pathname] Path to aspera-cli .gem file
  # @param gem_version [String]   Version of gem
  # @return [Array(String, String)] SDK version, RubyInstaller version (e.g. `4.0.7-1`)
  def package_versions(gem_file, gem_version)
    info_rb = gem_file_content(gem_file, 'lib/aspera/cli/info.rb')
    sdk_version = info_rb[/SDK_VERSION = '([^']+)'/, 1] || raise("SDK_VERSION not found in gem #{gem_version}")
    ruby_version = info_rb[/WINDOWS_RUBY_INSTALLER_VERSION = '([^']+)'/, 1]
    if ruby_version.nil?
      ruby_version = Aspera::Cli::Info::WINDOWS_RUBY_INSTALLER_VERSION
      log.warn("WINDOWS_RUBY_INSTALLER_VERSION not found in gem #{gem_version}, using current: #{ruby_version}")
    end
    return sdk_version, ruby_version
  end

  # Download the Transfer SDK archive
  # @param sdk_version [String]   SDK version
  # @param platform    [String]   SDK platform, e.g. `linux-x86_64`
  # @param folder      [Pathname] Destination folder
  # @return [Pathname] Path to SDK archive
  def download_sdk_archive(sdk_version, platform, folder)
    require 'aspera/ascp/installation'
    log.info("Getting Aspera SDK #{sdk_version} for #{platform}")
    sdk_url = Aspera::Ascp::Installation.instance.sdk_url_for_platform(platform: platform, version: sdk_version)
    download_file(sdk_url, folder / sdk_url.sub(%r{^.+/}, ''))
  end

  # Extract the Transfer SDK runtime files in the folder of a package
  # Files that `ascli` would create on first use are generated, so that the folder can be read-only.
  # The fallback certificate is not generated: its private key must be unique per installation.
  # @param sdk_archive [Pathname] Path to SDK archive
  # @param sdk_version [String]   SDK version
  # @param sdk_dir     [Pathname] Destination folder
  def install_package_sdk(sdk_archive, sdk_version, sdk_dir)
    require 'aspera/ascp/installation'
    require 'aspera/uri_reader'
    require 'aspera/products/transferd'
    require 'aspera/products/other'
    Aspera::Ascp::Installation.instance.download_sdk(folder: sdk_dir.to_s, url: Aspera::UriReader.file_url(sdk_archive.to_s), backup: false)
    Aspera::Products::Transferd.sdk_directory = sdk_dir.to_s
    %i[aspera_license aspera_conf ssh_private_dsa ssh_private_rsa].each { |file_id| Aspera::Ascp::Installation.instance.path(file_id) }
    # Same as generated by `ascli conf ascp install` (which gets version from binaries, cannot be executed here)
    (sdk_dir / Aspera::Products::Other::INFO_META_FILE).write("<product><name>IBM Aspera Transfer SDK</name><version>#{sdk_version}</version></product>")
  end

  # The executable requires a glibc at least as recent as the one of the build system
  # @return [String, nil] e.g. `2.28`, or nil if not glibc (e.g. macOS, musl)
  def glibc_version
    require 'etc'
    Etc.confstr(Etc::CS_GNU_LIBC_VERSION).to_s[/\Aglibc (\S+)\z/, 1]
  rescue NameError, SystemCallError
    nil
  end

  # Download the transfer.proto file into a temporary folder
  # @param tmp_proto_folder [String] Temporary folder to download the proto file into
  def download_proto_file(tmp_proto_folder)
    require 'aspera/ascp/installation'
    require 'aspera/cli/transfer_progress'
    Aspera::Rest::Parameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
    # Retrieve `transfer.proto` from the web
    Aspera::Ascp::Installation.instance.download_sdk(folder: tmp_proto_folder, backup: false) { |name| name.end_with?('.proto') ? '/' : nil }
  end

  # Version that is currently being built.
  # Use this instead of Aspera::Cli::VERSION to account for beta builds.
  # Default value: `VERSION` from `lib/aspera/cli/version.rb`
  def build_version
    return Paths::OVERRIDE_VERSION_FILE.read.strip if Paths::OVERRIDE_VERSION_FILE.exist?
    VERSION_FILE.read[/VERSION = '([^']+)'/, 1] || raise("VERSION not found in #{VERSION_FILE}")
  end

  # Change version to build
  def use_specific_version(version)
    Aspera.assert(!version.to_s.empty?) { 'Version argument is required for beta task' }
    OVERRIDE_VERSION_FILE.write(version)
    log.info("Version set to: #{BuildTools.build_version}")
  end

  # Ensure that env var `SIGNING_KEY` is set (path to key file, or PEM content).
  def check_gem_signing_key
    return if dry_run?
    raise 'Please set env var: SIGNING_KEY (path to key file or PEM content) to build a signed gem file' unless ENV.key?('SIGNING_KEY')
  end

  # .gem file built by bundler target `build`
  def built_gem_file
    Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{build_version}.gem"
  end

  def env_var_true?(var_name, default: 'no')
    Aspera::Cli::BoolValue.true?(ENV.fetch(var_name, default).downcase.to_sym)
  end

  module_function :log, :run, :drun, :dry_run?, :gems_in_group, :download_proto_file, :build_version, :check_gem_signing_key, :built_gem_file, :use_specific_version, :env_var_true?, :get_dependency_gems,
    :gem_file_content, :download_file, :package_gem_location, :package_versions, :download_sdk_archive, :install_package_sdk, :glibc_version
end

# Log control for rake
Aspera::Log.instance.level = ENV.fetch('LOG_LEVEL', 'info').to_sym
Aspera::SecretHider.instance.log_secrets = BuildTools.env_var_true?('LOG_SECRETS')
# Aspera::Rest::Parameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}
