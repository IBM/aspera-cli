# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/cli/info'
require_relative '../lib/aspera/cli/version'
require 'rake'
require 'erb'
require 'digest'
require 'fileutils'

require_relative '../build/lib/build_tools'
require_relative '../build/lib/paths'
include BuildTools

# Chocolatey package: it downloads the Windows portable package attached to the GitHub release (`windowszip:portable`),
# checked with its SHA-256, and puts only `ascli` on the PATH.
# Templates of the package
CHOCOLATEY_SRC = Paths::BUILD / 'chocolatey'

namespace :chocolatey do
  desc 'Create the Chocolatey package (nuspec and scripts, and .nupkg if `choco` is available), from the Windows portable package of the release'
  task :build, %i[version zip] do |_t, args|
    gem_version = args[:version] || build_version
    # Chocolatey (NuGet) versions: pre-release with hyphen, e.g. 4.30.0-pre
    nuget_version = gem_version.gsub(/\.([a-z]+)/, '-\1')
    zip_name = windows_portable_zip(gem_version).basename.to_s
    zip_url = "#{Aspera::Cli::Info::SRC_URL}/releases/download/v#{gem_version}/#{zip_name}"
    # The zip of the release: given, or built locally, or downloaded
    zip_path = args[:zip] ? Pathname(args[:zip]) : windows_portable_zip(gem_version)
    unless zip_path.exist?
      zip_path = Paths::TMP / zip_name
      log.info("Downloading #{zip_url}")
      run('curl', '-fsSL', '-o', zip_path.to_s, zip_url)
    end
    zip_sha256 = Digest::SHA256.file(zip_path).hexdigest
    log.info("#{zip_name}: sha256 #{zip_sha256}")
    path_build_dir = Paths::TMP / 'build_chocolatey'
    path_tools_dir = path_build_dir / 'tools'
    path_build_dir.rmtree if path_build_dir.exist?
    path_tools_dir.mkpath
    {
      'install.erb.ps1'    => path_tools_dir / 'chocolateyInstall.ps1',
      'uninstall.erb.ps1'  => path_tools_dir / 'chocolateyUninstall.ps1',
      'package.erb.nuspec' => path_build_dir / "#{Aspera::Cli::Info::GEM_NAME}.nuspec"
    }.each do |template, target|
      target.write(ERB.new((CHOCOLATEY_SRC / template).read).result(binding))
    end
    log.info("Package sources: #{path_build_dir}")
    if system('choco', '--version', out: File::NULL, err: File::NULL)
      Paths::RELEASE.mkpath
      Dir.chdir(path_build_dir) { run('choco', 'pack', "#{Aspera::Cli::Info::GEM_NAME}.nuspec", '--output-directory', Paths::RELEASE.to_s) }
      log.info("Created: #{Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}.#{nuget_version}.nupkg"}")
    else
      log.warn('choco not found: package sources generated, .nupkg not created (choco pack runs on Windows)')
    end
  end
end
