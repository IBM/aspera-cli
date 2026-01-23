# frozen_string_literal: true

require 'bundler'
require 'yaml'
require 'aspera/log'
require 'aspera/environment'
require 'aspera/cli/version'
require_relative 'paths'

# Log control
Aspera::Log.instance.level = ENV.key?('LOG_LEVEL') ? ENV['LOG_LEVEL'].to_sym : :info
# Aspera::RestParameters.instance.session_cb = lambda{ |http_session| http_session.set_debug_output(Aspera::LineLogger.new(:trace2)) if Aspera::Log.instance.logger.trace2?}

module BuildTools
  # @see Aspera::Log#logger
  def log(*args, **kwargs, &block)
    Aspera::Log.instance.logger(*args, **kwargs, &block)
  end

  # Execute the command line (not in shell)
  # @see `Aspera::Environment#secure_execute`
  def run(*cmd, **kwargs)
    dry_run = ENV['DRY_RUN'] == '1'
    log.info("#{dry_run ? 'Would run' : 'Executing'}: #{cmd.map(&:to_s).join(' ')}")
    Aspera::Environment.secure_execute(*cmd, **kwargs) unless dry_run
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

  # Determine release versions
  # @param release_version [String] Release version (empty to use current version without .pre)
  # @param next_version [String] Next development version (empty to auto-increment minor)
  # @return [Hash<Symbol,String>] Versions: :current, :release, :next, :dev
  def release_versions(release_version, next_version)
    versions = {}
    versions[:current] = Aspera::Cli::VERSION
    versions[:release] =
      if release_version.to_s.empty?
        Aspera::Cli::VERSION.sub(/\.pre$/, '')
      else
        release_version
      end
    versions[:next] =
      if next_version.to_s.empty? == false
        major, minor, _patch = versions[:release].split('.').map(&:to_i)
        [major, minor + 1, 0].map(&:to_s).join('.')
      else
        next_version
      end
    versions[:dev] = "#{versions[:next]}.pre"
    return versions
  end

  # Version that is currently being built
  # Use this instead of Aspera::Cli::VERSION to account for beta builds
  def specific_version
    return Paths::OVERRIDE_VERSION_FILE.read.strip if Paths::OVERRIDE_VERSION_FILE.exist?
    VERSION_FILE.read[/VERSION = '([^']+)'/, 1] || raise('VERSION not found in version file')
  end

  def use_specific_version(version)
    Aspera.assert(!version.to_s.empty?){'Version argument is required for beta task'}
    OVERRIDE_VERSION_FILE.write(version)
    log.info("Version set to: #{BuildTools.specific_version}")
  end

  module_function :log, :run, :gems_in_group, :download_proto_file, :release_versions, :specific_version
end
