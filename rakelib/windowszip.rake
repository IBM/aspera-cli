# Rakefile
# frozen_string_literal: true

require 'rake'
require 'zip'
require 'erb'
require 'aspera/rest'
require 'aspera/colors'
require 'aspera/environment'
require 'aspera/cli/info'
require 'aspera/cli/version'
require 'fileutils'
require 'aspera/cli/transfer_progress'
require 'aspera/ascp/installation'

require_relative '../build/lib/build_tools'
include BuildTools

Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new

RUBY_RELEASES_BASE_URL = 'https://github.com/oneclick/rubyinstaller2/releases'
MS_VC_BASE_URL         = 'https://aka.ms/vc14'
ARCHIVE_FOLDER_NAME    = 'resources'
VC_REDIST_FILENAME = 'vc_redist.x64.exe'

# in template binding
def vc_redist_exe
  VC_REDIST_FILENAME
end

# Zip a directory
# @param source_folder [String] Source folder to zip
# @param zip_path [String] Target zip file path
# @return [nil]
def zip_directory(source_folder, zip_path)
  source_folder = File.expand_path(source_folder)
  Aspera.assert(Dir.exist?(source_folder)){"Source directory not found: #{source_folder}"}
  File.delete(zip_path) if File.exist?(zip_path)
  prefix_length = (source_folder.length + 1)
  Zip::File.open(zip_path, create: true) do |zipfile|
    Dir.glob(File.join(source_folder, '**', '*')).each do |path|
      zipfile.add(path[prefix_length..-1], path)
    end
  end
end

namespace :windowszip do
  desc 'Create installation archive for Windows'
  task :build, [:version] do |_t, args|
    gem_version_build    = args[:version] || build_version
    target_folder_name   = "aspera-cli-#{gem_version_build}-windows-amd64-installer"
    path_build_dir       = Paths::TMP / target_folder_name
    path_resources_dir   = path_build_dir / ARCHIVE_FOLDER_NAME
    install_ruby_version = '3.4.7-1'
    ruby_installer_exe   = "rubyinstaller-devkit-#{install_ruby_version}-x64.exe"
    path_build_dir.rmtree
    path_resources_dir.mkpath

    log.info("Generating Windows package for #{Aspera::Cli::Info::GEM_NAME} v#{gem_version_build}")
    log.info("Building in #{path_build_dir}")

    log.info('Getting gem dependencies')
    tmp_install_ruby = path_build_dir / 'tmpruby'
    run('gem', 'install', "#{Aspera::Cli::Info::GEM_NAME}:#{gem_version_build}", '--no-document', '--install-dir', tmp_install_ruby)
    File.rename(File.join(tmp_install_ruby, 'cache'), path_resources_dir)
    tmp_install_ruby.rmtree

    log.info('Getting Aspera SDK')
    sdk_url  = Aspera::Ascp::Installation.instance.sdk_url_for_platform(platform: 'windows-x86_64')
    sdk_base = sdk_url.gsub(%r{/[^/]+$}, '')
    sdk_file = sdk_url.gsub(%r{^.+/}, '')
    Aspera::Rest.new(base_url: sdk_base, redirect_max: 5)
      .read(sdk_file, save_to_file: File.join(path_resources_dir, sdk_file))

    log.info('Getting Ruby')
    ruby_installer_path = "download/RubyInstaller-#{install_ruby_version}/#{ruby_installer_exe}"
    Aspera::Rest.new(base_url: RUBY_RELEASES_BASE_URL, redirect_max: 5)
      .read(ruby_installer_path, save_to_file: File.join(path_resources_dir, ruby_installer_exe))

    log.info('Getting VC++ Redistributable')
    Aspera::Rest.new(base_url: MS_VC_BASE_URL, redirect_max: 5)
      .read(VC_REDIST_FILENAME, save_to_file: File.join(path_resources_dir, VC_REDIST_FILENAME))

    log.info('Generating installer script and README')
    erb_src = (WIN_ZIP_SRC / 'install.erb.ps1').read
    File.open(File.join(path_resources_dir, 'install.ps1'), 'w') do |f|
      f.puts(ERB.new(erb_src).result(binding))
    end
    FileUtils.cp(WIN_ZIP_SRC / 'README.user.md', path_build_dir / 'README.md')
    FileUtils.cp(WIN_ZIP_SRC / 'setup.cmd', path_build_dir)

    log.info('Generating installer zip')
    zip_target = Paths::TMP / "#{target_folder_name}.zip"
    zip_directory(path_build_dir, zip_target)

    log.info("Created: #{zip_target}")
  end
end
