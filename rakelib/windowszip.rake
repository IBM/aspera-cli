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

Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new

RUBY_RELEASES_BASE_URL = 'https://github.com/oneclick/rubyinstaller2/releases'
INSTALL_RUBY_VERSION   = '3.4.7-1'
MS_VC_BASE_URL         = 'https://aka.ms/vc14'
TARGET_FOLDER_NAME     = "aspera-cli-#{GEM_VERSION}-windows-amd64-installer"
ARCHIVE_FOLDER_NAME    = 'resources'
PATH_BUILD_DIR         = Paths::TMP / TARGET_FOLDER_NAME
PATH_RESOURCES_DIR     = PATH_BUILD_DIR / ARCHIVE_FOLDER_NAME
ruby_installer_exe     = "rubyinstaller-devkit-#{INSTALL_RUBY_VERSION}-x64.exe"
vc_redist_exe          = 'vc_redist.x64.exe'
sdk_file               = nil

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
  task :prepare do
    puts("Generating Windows package for #{Aspera::Cli::Info::GEM_NAME} v#{GEM_VERSION}")
    PATH_BUILD_DIR.rmtree
    PATH_RESOURCES_DIR.mkdir
    puts("Building in #{PATH_BUILD_DIR}")
  end

  task gems: :prepare do
    puts('Getting gems'.blue)
    tmp_install_ruby = PATH_BUILD_DIR / 'tmpruby'

    Aspera::Environment.secure_execute(
      exec: 'gem',
      args: ['install', "#{Aspera::Cli::Info::GEM_NAME}:#{GEM_VERSION}", '--no-document', '--install-dir', tmp_install_ruby]
    )

    File.rename(File.join(tmp_install_ruby, 'cache'), PATH_RESOURCES_DIR)
    tmp_install_ruby.rmtree
  end

  task sdk: :gems do
    puts('Getting SDK'.blue)
    sdk_url  = Aspera::Ascp::Installation.instance.sdk_url_for_platform(platform: 'windows-x86_64')
    sdk_base = sdk_url.gsub(%r{/[^/]+$}, '')
    sdk_file = sdk_url.gsub(%r{^.+/}, '')

    Aspera::Rest.new(base_url: sdk_base, redirect_max: 5)
      .read(sdk_file, save_to_file: File.join(PATH_RESOURCES_DIR, sdk_file))
  end

  task ruby: :sdk do
    puts('Getting Ruby'.blue)
    ruby_installer_path = "download/RubyInstaller-#{INSTALL_RUBY_VERSION}/#{ruby_installer_exe}"

    Aspera::Rest.new(base_url: RUBY_RELEASES_BASE_URL, redirect_max: 5)
      .read(ruby_installer_path, save_to_file: File.join(PATH_RESOURCES_DIR, ruby_installer_exe))
  end

  task vcredist: :ruby do
    puts('Getting VC++ Redistributable'.blue)
    Aspera::Rest.new(base_url: MS_VC_BASE_URL, redirect_max: 5)
      .read(vc_redist_exe, save_to_file: File.join(PATH_RESOURCES_DIR, vc_redist_exe))
  end

  task installer: :vcredist do
    puts('Generating installer script'.blue)
    erb_src = File.read(File.join(__dir__, 'install.erb.ps1'))

    File.open(File.join(PATH_RESOURCES_DIR, 'install.ps1'), 'w') do |f|
      f.puts(ERB.new(erb_src).result(binding))
    end
  end

  task package: :installer do
    FileUtils.cp(File.join(__dir__, 'README.md'), PATH_BUILD_DIR)
    FileUtils.cp(File.join(__dir__, 'setup.cmd'), PATH_BUILD_DIR)
  end

  desc 'Create installation archive for Windows'
  task zip: :package do
    zip_target = Paths::TMP / "#{TARGET_FOLDER_NAME}.zip"
    puts('Generating installer zip'.blue)
    zip_directory(PATH_BUILD_DIR, zip_target)
    puts("Created: #{zip_target}")
  end
end
