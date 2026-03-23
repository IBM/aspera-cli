# frozen_string_literal: true

require 'bundler'
require 'yaml'
require 'aspera/log'
require 'aspera/secret_hider'
require 'aspera/environment'
require 'aspera/cli/version'
require 'aspera/cli/manager'
require_relative 'paths'

module BuildTools
  # @see Aspera::Log#logger
  def log(*args, **kwargs, &block)
    Aspera::Log.instance.logger(*args, **kwargs, &block)
  end

  # Execute the command line (not in shell)
  # @see `Aspera::Environment#secure_execute`
  def run(*cmd, **kwargs)
    log.info("Executing: #{cmd.map{ |i| Aspera::Environment.shell_escape_pretty(i.to_s)}.join(' ')}")
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
      log.info("#{'Would execute'.red}: #{cmd.map{ |i| Aspera::Environment.shell_escape_pretty(i.to_s)}.join(' ')}")
      return '' if kwargs[:mode].eql?(:capture)
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

  # Download the transfer.proto file into a temporary folder
  # @param tmp_proto_folder [String] Temporary folder to download the proto file into
  def download_proto_file(tmp_proto_folder)
    require 'aspera/ascp/installation'
    require 'aspera/cli/transfer_progress'
    Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
    # Retrieve `transfer.proto` from the web
    Aspera::Ascp::Installation.instance.install_sdk(folder: tmp_proto_folder, backup: false, with_exe: false){ |name| name.end_with?('.proto') ? '/' : nil}
  end

  # Version that is currently being built.
  # Use this instead of Aspera::Cli::VERSION to account for beta builds.
  def build_version
    return Paths::OVERRIDE_VERSION_FILE.read.strip if Paths::OVERRIDE_VERSION_FILE.exist?
    VERSION_FILE.read[/VERSION = '([^']+)'/, 1] || raise("VERSION not found in #{VERSION_FILE}")
  end

  # Change version to build
  def use_specific_version(version)
    Aspera.assert(!version.to_s.empty?){'Version argument is required for beta task'}
    OVERRIDE_VERSION_FILE.write(version)
    log.info("Version set to: #{BuildTools.build_version}")
  end

  # Ensure that env var `SIGNING_KEY` (path to signing key file) is set.
  # If env var `SIGNING_KEY_PEM` is set, creates sur file in $HOME/.gem/signing_key.pem
  def check_gem_signing_key
    return if dry_run?
    if ENV.key?('SIGNING_KEY_PEM')
      gem_conf_dir = Pathname.new(Dir.home) / '.gem'
      gem_conf_dir.mkpath
      signing_key_file = gem_conf_dir / 'signing_key.pem'
      # Atomically create file with right perms
      File.open(signing_key_file, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |f|
        f.write(ENV.fetch('SIGNING_KEY_PEM'))
      end
      ENV['SIGNING_KEY'] = signing_key_file.to_s
    end
    raise 'Please set env var: SIGNING_KEY or SIGNING_KEY_PEM to build a signed gem file' unless ENV.key?('SIGNING_KEY')
  end

  # .gem file built by bundler target `build`
  def built_gem_file
    Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{build_version}.gem"
  end

  def env_var_true?(var_name, default: 'no')
    Aspera::Cli::BoolValue.true?(ENV.fetch(var_name, default).downcase.to_sym)
  end

  module_function :log, :run, :drun, :dry_run?, :gems_in_group, :download_proto_file, :build_version, :check_gem_signing_key, :built_gem_file, :use_specific_version, :env_var_true?, :get_dependency_gems
end

# Log control for rake
Aspera::Log.instance.level = ENV.fetch('LOG_LEVEL', 'info').to_sym
Aspera::SecretHider.instance.log_secrets = BuildTools.env_var_true?('LOG_SECRETS')
# Aspera::RestParameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}
