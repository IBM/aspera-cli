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
require 'aspera/uri_reader'
require 'aspera/products/transferd'
require 'aspera/products/other'

require_relative '../build/lib/build_tools'
include BuildTools

Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new

RUBY_RELEASES_BASE_URL = 'https://github.com/oneclick/rubyinstaller2/releases'
MS_VC_BASE_URL         = 'https://aka.ms/vc14'
# "resources" sub-folder
ARCHIVE_FOLDER_NAME    = 'resources'
VC_REDIST_FILENAME = 'vc_redist.x64.exe'
SDK_PLATFORM = 'windows-x86_64'
# Folder with files specific to the portable package
WIN_PORTABLE_SRC = Paths::WIN_ZIP_SRC / 'portable'

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

# Download a file
# @param url  [String]   URL of file
# @param dest [Pathname] Destination file path
# @return [Pathname] Destination file path
def download_file(url, dest)
  Aspera::Rest.new(base_url: url.sub(%r{/[^/]+$}, ''), redirect_max: 5)
    .read(url.sub(%r{^.+/}, ''), save_to: dest)
  dest
end

# Versions of SDK and Ruby tested with the packaged gem version
# @param gem_file    [Pathname] Path to aspera-cli .gem file
# @param gem_version [String]   Version of gem
# @return [Array(String, String)] SDK version, RubyInstaller version
def windows_package_versions(gem_file, gem_version)
  info_rb = gem_file_content(gem_file, 'lib/aspera/cli/info.rb')
  sdk_version = info_rb[/SDK_VERSION = '([^']+)'/, 1] || raise("SDK_VERSION not found in gem #{gem_version}")
  ruby_version = info_rb[/WINDOWS_RUBY_INSTALLER_VERSION = '([^']+)'/, 1]
  if ruby_version.nil?
    ruby_version = Aspera::Cli::Info::WINDOWS_RUBY_INSTALLER_VERSION
    log.warn("WINDOWS_RUBY_INSTALLER_VERSION not found in gem #{gem_version}, using current: #{ruby_version}")
  end
  return sdk_version, ruby_version
end

# Download the Windows Transfer SDK archive
# @param sdk_version [String]   SDK version
# @param folder      [Pathname] Destination folder
# @return [Pathname] Path to SDK archive
def download_windows_sdk(sdk_version, folder)
  log.info("Getting Aspera SDK #{sdk_version} for #{SDK_PLATFORM}")
  sdk_url = Aspera::Ascp::Installation.instance.sdk_url_for_platform(platform: SDK_PLATFORM, version: sdk_version)
  download_file(sdk_url, folder / sdk_url.sub(%r{^.+/}, ''))
end

# Tools to extract a 7z archive, in order of preference: executable name => arguments for archive and destination folder
SEVEN_ZIP_EXTRACTORS = {
  '7zz'    => ->(archive, folder) { ['x', '-y', "-o#{folder}", archive] }, # Linux: package 7zip
  '7z'     => ->(archive, folder) { ['x', '-y', "-o#{folder}", archive] }, # Linux: package p7zip
  'bsdtar' => ->(archive, folder) { ['-xf', archive, '-C', folder] }       # macOS: built-in, Linux: package libarchive-tools
}.freeze

# Extract a 7z archive using the first available tool
# @param archive [Pathname] Path to .7z archive
# @param folder  [Pathname] Destination folder
def extract_7z(archive, folder)
  exe = SEVEN_ZIP_EXTRACTORS.keys.find do |name|
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) }
  end
  raise "No tool found to extract 7z archive, install one of: #{SEVEN_ZIP_EXTRACTORS.keys.join(', ')}" if exe.nil?
  run(exe, *SEVEN_ZIP_EXTRACTORS[exe].call(archive.to_s, folder.to_s))
end

# Gem to package: locally built gem file if present (e.g. during release, before it is published), else from rubygems.org
# @param gem_version [String] Version of gem
# @return [String] Local gem file path, or gem name and version
def windows_gem_location(gem_version)
  local_gem = Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version}.gem"
  location = local_gem.exist? ? local_gem.to_s : "#{Aspera::Cli::Info::GEM_NAME}:#{gem_version}"
  log.info("Using gem: #{location}")
  location
end

# @param gem_version [String] Version of gem
# @return [Pathname] Path to Windows portable package
def windows_portable_zip(gem_version)
  Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version}-windows-amd64-portable.zip"
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
    get_dependency_gems(windows_gem_location(gem_version_build), path_resources_dir)

    sdk_version, install_ruby_version = windows_package_versions(path_resources_dir / "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version_build}.gem", gem_version_build)
    ruby_installer_exe = "rubyinstaller-devkit-#{install_ruby_version}-x64.exe"
    sdk_file = download_windows_sdk(sdk_version, path_resources_dir).basename.to_s

    log.info("Getting Ruby #{install_ruby_version}")
    download_file("#{RUBY_RELEASES_BASE_URL}/download/RubyInstaller-#{install_ruby_version}/#{ruby_installer_exe}", path_resources_dir / ruby_installer_exe)

    log.info('Getting VC++ Redistributable')
    download_file("#{MS_VC_BASE_URL}/#{VC_REDIST_FILENAME}", path_resources_dir / VC_REDIST_FILENAME)

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

  desc 'Create portable archive for Windows (extract and run, no installation)'
  task :portable, [:version] do |_t, args|
    gem_version_build = args[:version] || build_version
    path_build_dir = Paths::TMP / 'build_win_portable'
    path_download_dir = path_build_dir / 'download'
    path_package_dir = path_build_dir / 'package'
    path_build_dir.rmtree if path_build_dir.exist?
    path_download_dir.mkpath
    path_package_dir.mkpath

    log.info("Generating Windows portable package for #{Aspera::Cli::Info::GEM_NAME} v#{gem_version_build}")
    log.info("Building in #{path_build_dir}")

    log.info('Getting gem dependencies')
    get_dependency_gems(windows_gem_location(gem_version_build), path_download_dir)
    sdk_version, ruby_version = windows_package_versions(path_download_dir / "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version_build}.gem", gem_version_build)

    log.info("Getting Ruby #{ruby_version}")
    ruby_archive_base = "rubyinstaller-#{ruby_version}-x64"
    ruby_archive = download_file("#{RUBY_RELEASES_BASE_URL}/download/RubyInstaller-#{ruby_version}/#{ruby_archive_base}.7z", path_download_dir / "#{ruby_archive_base}.7z")
    extract_7z(ruby_archive, path_package_dir)
    path_ruby_dir = path_package_dir / 'ruby'
    (path_package_dir / ruby_archive_base).rename(path_ruby_dir)
    # Not needed at runtime: documentation, C headers, cached gem files
    [path_ruby_dir / 'share' / 'doc', path_ruby_dir / 'share' / 'ri', path_ruby_dir / 'include', *path_ruby_dir.glob('lib/ruby/gems/*/cache')].each(&:rmtree)

    log.info('Installing gems')
    # Native gem `json` cannot be built here: use the default gem provided by Ruby
    gem_files = path_download_dir.glob('*.gem').reject { |f| f.basename.to_s.start_with?('json-') }
    path_gems_dir = path_package_dir / 'gems'
    run('gem', 'install', '--local', '--no-document', '--ignore-dependencies', '--install-dir', path_gems_dir, '--bindir', path_gems_dir / 'bin', *gem_files)
    (path_gems_dir / 'cache').rmtree

    sdk_archive = download_windows_sdk(sdk_version, path_download_dir)
    path_sdk_dir = path_package_dir / 'sdk'
    Aspera::Ascp::Installation.instance.download_sdk(folder: path_sdk_dir.to_s, url: Aspera::UriReader.file_url(sdk_archive.to_s), backup: false)
    # Generate files that ascli would create on first use, so that folder `sdk` can be read-only
    # Fallback certificate is not generated: its private key must be unique per installation
    Aspera::Products::Transferd.sdk_directory = path_sdk_dir.to_s
    %i[aspera_license aspera_conf ssh_private_dsa ssh_private_rsa].each { |file_id| Aspera::Ascp::Installation.instance.path(file_id) }
    # Same as generated by `ascli conf ascp install` (which gets version from binaries, cannot be executed here)
    (path_sdk_dir / Aspera::Products::Other::INFO_META_FILE).write("<product><name>IBM Aspera Transfer SDK</name><version>#{sdk_version}</version></product>")

    log.info('Adding launcher and README')
    WIN_PORTABLE_SRC.each_child { |f| FileUtils.cp(f, path_package_dir) }

    log.info('Generating zip')
    zip_target = windows_portable_zip(gem_version_build)
    # Files at root of zip: Windows "Extract All" already extracts into a folder named after the zip
    zip_directory(path_package_dir, zip_target)

    log.info("Created: #{zip_target}")
  end
end
