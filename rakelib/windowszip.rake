# Rakefile
# frozen_string_literal: true

require 'rake'
require 'zip'
require 'erb'
require 'aspera/rest'
require 'aspera/environment'
require 'aspera/cli/info'
require 'aspera/cli/version'
require 'fileutils'
require 'rubygems/package'
require 'zlib'
require 'aspera/cli/transfer_progress'
require 'aspera/ascp/installation'

require_relative '../build/lib/build_tools'
include BuildTools

Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new

RUBY_RELEASES_BASE_URL = 'https://github.com/oneclick/rubyinstaller2/releases'
MS_VC_BASE_URL         = 'https://aka.ms/vc14'
# "resources" sub-folder
ARCHIVE_FOLDER_NAME    = 'resources'
VC_REDIST_FILENAME = 'vc_redist.x64.exe'

# Used in install.erb.ps1 template
def vc_redist_exe
  VC_REDIST_FILENAME
end

# Zip a directory
# @param source_folder [Pathname] Source folder to zip
# @param zip_path      [Pathname] Target zip file path
# @return [nil]
def zip_directory(source_folder, zip_path)
  Aspera.assert(source_folder.exist?) { "Source directory not found: #{source_folder}" }
  Aspera.assert(source_folder.directory?) { "Expecting directory: #{source_folder}" }
  source_folder = source_folder.expand_path
  zip_path.delete if zip_path.exist?
  zip_path.dirname.mkpath
  Zip::File.open(zip_path, create: true) do |zipfile|
    Pathname.glob(source_folder.join('**', '*')).each do |path|
      zipfile.add(path.relative_path_from(source_folder), path.to_s)
    end
  end
  nil
end

# Read a file from a gem package
# @param gem_path [Pathname] Path to .gem file
# @param file     [String]   Path of file inside gem
# @return [String] File content
def gem_file_content(gem_path, file)
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

namespace :windowszip do
  desc 'Create installation archive for Windows'
  task :build, [:version] do |_t, args|
    gem_version_build = args[:version] || build_version
    target_zip_file = "aspera-cli-#{gem_version_build}-windows-amd64-installer.zip"
    path_build_dir       = Paths::TMP / 'build_win_zip'
    path_resources_dir   = path_build_dir / ARCHIVE_FOLDER_NAME
    path_build_dir.rmtree
    path_resources_dir.mkpath

    log.info("Generating Windows package for #{Aspera::Cli::Info::GEM_NAME} v#{gem_version_build}")
    log.info("Building in #{path_build_dir}")

    log.info('Getting gem dependencies')
    get_dependency_gems("#{Aspera::Cli::Info::GEM_NAME}:#{gem_version_build}", path_resources_dir)

    # Versions tested with the packaged gem version
    info_rb = gem_file_content(path_resources_dir / "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version_build}.gem", 'lib/aspera/cli/info.rb')
    sdk_version = info_rb[/SDK_VERSION = '([^']+)'/, 1] || raise("SDK_VERSION not found in gem #{gem_version_build}")
    install_ruby_version = info_rb[/WINDOWS_RUBY_INSTALLER_VERSION = '([^']+)'/, 1]
    if install_ruby_version.nil?
      install_ruby_version = Aspera::Cli::Info::WINDOWS_RUBY_INSTALLER_VERSION
      log.warn("WINDOWS_RUBY_INSTALLER_VERSION not found in gem #{gem_version_build}, using current: #{install_ruby_version}")
    end
    ruby_installer_exe = "rubyinstaller-devkit-#{install_ruby_version}-x64.exe"

    sdk_platform = 'windows-x86_64'
    log.info("Getting Aspera SDK #{sdk_version} for #{sdk_platform}")
    sdk_url  = Aspera::Ascp::Installation.instance.sdk_url_for_platform(platform: sdk_platform, version: sdk_version)
    sdk_base = sdk_url.gsub(%r{/[^/]+$}, '')
    sdk_file = sdk_url.gsub(%r{^.+/}, '')
    Aspera::Rest.new(base_url: sdk_base, redirect_max: 5)
      .read(sdk_file, save_to: path_resources_dir / sdk_file)

    log.info("Getting Ruby #{install_ruby_version}")
    ruby_installer_path = "download/RubyInstaller-#{install_ruby_version}/#{ruby_installer_exe}"
    Aspera::Rest.new(base_url: RUBY_RELEASES_BASE_URL, redirect_max: 5)
      .read(ruby_installer_path, save_to: path_resources_dir / ruby_installer_exe)

    log.info('Getting VC++ Redistributable')
    Aspera::Rest.new(base_url: MS_VC_BASE_URL, redirect_max: 5)
      .read(VC_REDIST_FILENAME, save_to: path_resources_dir / VC_REDIST_FILENAME)

    log.info('Generating installer script and README')
    erb_src = (WIN_ZIP_SRC / 'install.erb.ps1').read
    (path_resources_dir / 'install.ps1').write(ERB.new(erb_src).result(binding))
    FileUtils.cp(WIN_ZIP_SRC / 'README.user.md', path_build_dir / 'README.md')
    FileUtils.cp(WIN_ZIP_SRC / 'setup.cmd', path_build_dir)

    log.info('Generating installer zip')
    zip_target = Paths::RELEASE / target_zip_file
    zip_directory(path_build_dir, zip_target)

    log.info("Created: #{zip_target}")
  end
end
