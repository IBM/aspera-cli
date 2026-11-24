# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/log'
require_relative '../../lib/aspera/secret/hider'
require_relative '../../lib/aspera/environment'
require_relative '../../lib/aspera/cli/version'
require_relative '../../lib/aspera/cli/parser'
require_relative 'paths'
require_relative '../../lib/aspera/rainbow'
require 'bundler'
require 'yaml'
using Rainbow

# Helpers for rake tasks: logging, command execution (with dry run), gems, versions, packaging
# Methods are module functions: called as `BuildTools.<method>` or without receiver when included
module BuildTools
  # Logger of the CLI
  # @return [Logger]
  # @see Aspera::Log#logger
  def log
    Aspera::Log.instance.logger
  end

  # Execute the command line (not in shell)
  # @param cmd    [Array<#to_s>] Executable and arguments
  # @param kwargs [Hash]         Options of `Aspera::Environment.secure_execute` (e.g. `mode:`, `env:`)
  # @return [Boolean, Integer, Array(String, String, Process::Status), nil] Depends on `mode`
  # @see Aspera::Environment.secure_execute
  def run(*cmd, **kwargs)
    log.info("Executing: #{cmd.map { |i| Aspera::Environment.shell_escape_pretty(i.to_s) }.join(' ').sub(%r{^ruby -w [^ ]+ [^ ]+/bin/ascli }, 'ascli ')}")
    Aspera::Environment.secure_execute(*cmd, **kwargs)
  end

  # If env var `DRY_RUN` is set to `1`, then do not execute `git` and `gh` commands.
  # @return [Boolean] `true` if dry run
  def dry_run?
    ENV['DRY_RUN'] == '1'
  end

  # Execute command only if not dry run (env `DRY_RUN=1`), else log it
  # @param cmd    [Array<#to_s>] Executable and arguments
  # @param kwargs [Hash]         Options of {run}
  # @return [Object] Result of {run}, in dry run: `['']` for `mode: :capture`, else `nil`
  def drun(*cmd, **kwargs)
    if dry_run?
      log.info("#{'Would execute'.red}: #{cmd.map { |i| Aspera::Environment.shell_escape_pretty(i.to_s) }.join(' ')}")
      return [''] if kwargs[:mode].eql?(:capture)
    else
      run(*cmd, **kwargs)
    end
  end

  # Extract gem specifications in a given group from the Gemfile, for the current platform
  # @param gemfile [String] Path to gem file
  # @param group_name_sym [Symbol] Group name
  # @return [Array<String>] List of gem specifications in the group
  def gems_in_group(gemfile, group_name_sym)
    Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil).dependencies.filter_map do |dep|
      next unless dep.groups.include?(group_name_sym) && dep.should_include?
      "#{dep.name}:#{dep.requirement.to_s.delete(' ')}"
    end
  end

  # Download gem and dependencies to folder
  # @param gem_location [String] Path to gem file or <name>:<version>
  # @param destination_path [Pathname] Path to folder where gems files will be stored
  # @return [void]
  def get_dependency_gems(gem_location, destination_path)
    tmp_install_ruby = Paths::TMP / 'gem_deps_cache'
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
    require_relative '../../lib/aspera/rest'
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
  # @return [Array(String, String, String)] SDK version, Ruby version (e.g. `4.0.x`), RubyInstaller version (e.g. `4.0.x-1`)
  def package_versions(gem_file, gem_version)
    info_rb = gem_file_content(gem_file, 'lib/aspera/cli/info.rb')
    sdk_version = info_rb[/SDK_VERSION = '([^']+)'/, 1] || raise("SDK_VERSION not found in gem #{gem_version}")
    ruby_version = info_rb[/RUBY_TESTED_VERSION = '([^']+)'/, 1]
    installer_ext = info_rb[/WINDOWS_RUBY_INSTALLER_EXT = '([^']+)'/, 1]
    if ruby_version.nil?
      # Gems 4.27.x: RubyInstaller version only, e.g. `4.0.7-1`
      installer_version = info_rb[/WINDOWS_RUBY_INSTALLER_VERSION = '([^']+)'/, 1]
      ruby_version, installer_ext = installer_version&.match(/\A(.+)(-\d+)\z/)&.captures
    end
    if ruby_version.nil?
      ruby_version = Aspera::Cli::Info::RUBY_TESTED_VERSION
      installer_ext = Aspera::Cli::Info::WINDOWS_RUBY_INSTALLER_EXT
      log.warn("Ruby version not found in gem #{gem_version}, using current: #{ruby_version}")
    end
    return sdk_version, ruby_version, "#{ruby_version}#{installer_ext}"
  end

  # Download the Transfer SDK archive
  # @param sdk_version [String]   SDK version
  # @param platform    [String]   SDK platform, e.g. `linux-x86_64`
  # @param folder      [Pathname] Destination folder
  # @return [Pathname] Path to SDK archive
  def download_sdk_archive(sdk_version, platform, folder)
    require_relative '../../lib/aspera/ascp/installation'
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
  # @return [void]
  def install_package_sdk(sdk_archive, sdk_version, sdk_dir)
    require_relative '../../lib/aspera/ascp/installation'
    require_relative '../../lib/aspera/uri_reader'
    require_relative '../../lib/aspera/products/transferd'
    require_relative '../../lib/aspera/products'
    Aspera::Ascp::Installation.instance.download_sdk(folder: sdk_dir.to_s, url: Aspera::UriReader.file_url(sdk_archive.to_s), backup: false)
    Aspera::Products::Transferd.sdk_directory = sdk_dir.to_s
    %i[aspera_license aspera_conf ssh_private_dsa ssh_private_rsa].each { |file_id| Aspera::Ascp::Installation.instance.path(file_id) }
    # Same as generated by `ascli conf ascp install` (which gets version from binaries, cannot be executed here)
    (sdk_dir / Aspera::Products::INFO_META_FILE).write("<product><name>IBM Aspera Transfer SDK</name><version>#{sdk_version}</version></product>")
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
  # @return [void]
  def download_proto_file(tmp_proto_folder)
    require_relative '../../lib/aspera/ascp/installation'
    require_relative '../../lib/aspera/cli/transfer_progress'
    Aspera::Rest::Parameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
    # Retrieve `transfer.proto` from the web
    Aspera::Ascp::Installation.instance.download_sdk(folder: tmp_proto_folder, backup: false) { |name| name.end_with?('.proto') ? '/' : nil }
  end

  # Version that is currently being built.
  # Use this instead of Aspera::Cli::VERSION to account for beta builds.
  # Default value: `VERSION` from `lib/aspera/cli/version.rb`
  # @return [String] Version, from `Paths::OVERRIDE_VERSION_FILE` if present (see {use_specific_version})
  def build_version
    return Paths::OVERRIDE_VERSION_FILE.read.strip if Paths::OVERRIDE_VERSION_FILE.exist?
    Paths::VERSION_FILE.read[/VERSION = '([^']+)'/, 1] || raise("VERSION not found in #{Paths::VERSION_FILE}")
  end

  # Change version to build (e.g. beta), saved in `Paths::OVERRIDE_VERSION_FILE`
  # @param version [String] Version to build
  # @return [void]
  def use_specific_version(version)
    Aspera.assert(!version.to_s.empty?) { 'Version argument is required for beta task' }
    Paths::OVERRIDE_VERSION_FILE.dirname.mkpath
    Paths::OVERRIDE_VERSION_FILE.write(version)
    log.info("Version set to: #{BuildTools.build_version}")
  end

  # Ensure that env var `SIGNING_KEY` is set (path to key file, or PEM content), unless dry run.
  # @return [void]
  # @raise [RuntimeError] If `SIGNING_KEY` is not set
  def check_gem_signing_key
    return if dry_run?
    raise 'Please set env var: SIGNING_KEY (path to key file or PEM content) to build a signed gem file' unless ENV.key?('SIGNING_KEY')
  end

  # .gem file built by bundler target `build`
  # @return [Pathname] Path to .gem file of {build_version}
  def built_gem_file
    Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{build_version}.gem"
  end

  # Tell if an env var is set to a true value (e.g. `yes`, `true`), see `Aspera::Cli::BoolValue`
  # @param var_name [String] Name of env var
  # @param default  [String] Value if env var is not set
  # @return [Boolean] `true` if the value is a true value
  def env_var_true?(var_name, default: 'no')
    Aspera::Cli::BoolValue.true?(ENV.fetch(var_name, default).downcase.to_sym)
  end

  module_function :log, :run, :drun, :dry_run?, :gems_in_group, :download_proto_file, :build_version, :check_gem_signing_key, :built_gem_file, :use_specific_version, :env_var_true?, :get_dependency_gems,
    :gem_file_content, :download_file, :package_gem_location, :package_versions, :download_sdk_archive, :install_package_sdk, :glibc_version
end

# Log control for rake
Aspera::Log.instance.level = ENV.fetch('LOG_LEVEL', 'info').to_sym
Aspera::Secret::Hider.instance.log_secrets = BuildTools.env_var_true?('LOG_SECRETS')
# Aspera::Rest::Parameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}
