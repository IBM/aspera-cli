#!/usr/bin/env ruby
# frozen_string_literal: true

require 'zip'
require 'erb'
require 'aspera/rest'
require 'aspera/colors'
require 'aspera/environment'
require 'fileutils'
require 'aspera/cli/transfer_progress'
require 'aspera/ascp/installation'
Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new

GEM_NAME = 'aspera-cli'
GEM_VERSION = '4.24.2'
RUBY_INSTALLER_BASE_URL = 'https://github.com/oneclick/rubyinstaller2/releases/download'
RUBY_INST_VERSION = '3.4.7-1'
MS_VC_BASE_URL = 'https://aka.ms/vc14'
TARGET_FOLDER_NAME = "aspera-cli-#{GEM_VERSION}-windows-amd64-installer"
TEMP_FOLDER = File.join(File.dirname(__FILE__, 2), 'tmp')

def zip_directory(source_dir, zip_path)
  source_dir = File.expand_path(source_dir)
  Aspera.assert(Dir.exist?(source_dir)){"Source directory not found: #{source_dir}"}
  File.delete(zip_path) if File.exist?(zip_path)
  prefix_length = (File.dirname(source_dir).length + 1)
  Zip::File.open(zip_path, create: true) do |zipfile|
    Dir.glob(File.join(source_dir, '**', '*')).each do |source_path|
      zipfile.add(source_path[prefix_length..-1], source_path)
    end
  end
end

puts("Generating Windows package for #{GEM_NAME} v#{GEM_VERSION}")
build_folder = File.join(TEMP_FOLDER, TARGET_FOLDER_NAME)
FileUtils.rm_rf(build_folder)
FileUtils.mkdir_p(build_folder)
puts("Building in #{build_folder}")

puts('Getting SDK'.blue)
sdk_url = Aspera::Ascp::Installation.instance.sdk_url_for_platform(platform: 'windows-x86_64')
sdk_file = sdk_url.gsub(%r{^.+/}, '')
sdk_base = sdk_url.gsub(%r{/[^/]+$}, '')
Aspera::Rest.new(base_url: sdk_base, redirect_max: 5).read(sdk_file, save_to_file: File.join(build_folder, sdk_file))

puts('Getting gems'.blue)
gem_archive_dir = 'rbgems'
tmp_install_ruby = File.join(build_folder, 'tmpruby')
Aspera::Environment.secure_execute(exec: 'gem', args: ['install', "#{GEM_NAME}:#{GEM_VERSION}", '--no-document', '--install-dir', tmp_install_ruby])
File.rename(File.join(tmp_install_ruby, 'cache'), File.join(build_folder, gem_archive_dir))
FileUtils.rm_rf(tmp_install_ruby)

puts('Getting Ruby'.blue)
ruby_installer_exe = "rubyinstaller-devkit-#{RUBY_INST_VERSION}-x64.exe"
source_file = "RubyInstaller-#{RUBY_INST_VERSION}/#{ruby_installer_exe}"
Aspera::Rest.new(base_url: RUBY_INSTALLER_BASE_URL, redirect_max: 5).read(source_file, save_to_file: File.join(build_folder, ruby_installer_exe))

puts('Getting VC++ Redistributable'.blue)
vc_redist_exe = 'vc_redist.x64.exe'
Aspera::Rest.new(base_url: MS_VC_BASE_URL, redirect_max: 5).read(vc_redist_exe, save_to_file: File.join(build_folder, vc_redist_exe))

puts('Generating installer script'.blue)
File.open(File.join(build_folder, 'install.ps1'), 'w') do |f|
  f.puts(ERB.new(File.read(File.join(File.dirname(__FILE__), 'install.erb.ps1'))).result(binding))
end

FileUtils.cp(File.join(File.dirname(__FILE__), 'README.md'), File.join(build_folder, 'README.md'))

zip_target = File.join(TEMP_FOLDER, "#{TARGET_FOLDER_NAME}.zip")
puts('Generating installer zip'.blue)
zip_directory(build_folder, zip_target)
puts "Created: #{zip_target}"
