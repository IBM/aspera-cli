# frozen_string_literal: true

require 'bundler'
require 'yaml'
require 'aspera/log'
require 'aspera/secret_hider'
require 'aspera/environment'
require 'aspera/cli/version'
require 'aspera/cli/manager'
require_relative 'paths'

# Log control
Aspera::Log.instance.level = ENV.fetch('RAKE_LOG_LEVEL', 'info').to_sym
Aspera::SecretHider.instance.log_secrets = Aspera::Cli::Manager.enum_to_bool(ENV.fetch('RAKE_HIDE_SECRETS', 'yes').downcase.to_sym)
# Aspera::RestParameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}

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

  # If env var `DRY_RUN` is set to `1`, then do not execute `git` and `gh` commands.
  def dry_run?
    ENV['DRY_RUN'] == '1'
  end

  module_function :log, :run, :gems_in_group, :download_proto_file, :build_version, :check_gem_signing_key, :dry_run?
end
