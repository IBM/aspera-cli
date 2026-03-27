# Rakefile
# frozen_string_literal: true

require 'rake'
require 'erb'
require 'fileutils'
require 'aspera/cli/info'
require 'aspera/cli/version'

require_relative '../build/lib/build_tools'
require_relative '../build/lib/paths'
include BuildTools

# Path to Chocolatey templates
CHOCOLATEY_SRC = Paths::BUILD / 'chocolatey'
# Nae of the package
CHOCO_PACKAGE_NAME = Aspera::Cli::Info::GEM_NAME

namespace :chocolatey do
  desc 'Create Chocolatey package'
  task :build, [:version] do |_t, args|
    gem_version_build = args[:version] || build_version
    # Version of that choco package (choco requires hyphen)
    nuget_version_build = gem_version_build.sub('.pre', '-pre')
    path_build_dir = Paths::TMP / 'build_chocolatey'
    path_tools_dir = path_build_dir / 'tools'
    gem_spec = Gem::Specification.load(GEMSPEC)

    # Clean and create build directories
    path_build_dir.rmtree if path_build_dir.exist?
    path_tools_dir.mkpath

    log.info("Generating Chocolatey package for #{Aspera::Cli::Info::GEM_NAME} v#{nuget_version_build}")
    log.info("Building in #{path_build_dir}")

    # Generate install script from template
    log.info('Generating install script from template')
    erb_src = (CHOCOLATEY_SRC / 'install.erb.ps1').read
    install_content = ERB.new(erb_src).result(binding)
    (path_tools_dir / 'chocolateyInstall.ps1').write(install_content)

    # Generate uninstall script from template
    log.info('Generating uninstall script from template')
    erb_src = (CHOCOLATEY_SRC / 'uninstall.erb.ps1').read
    uninstall_content = ERB.new(erb_src).result(binding)
    (path_tools_dir / 'chocolateyUninstall.ps1').write(uninstall_content)

    # Copy README files
    log.info('Copying README files')
    FileUtils.cp(CHOCOLATEY_SRC / 'README.package.md', path_build_dir / 'README.md')

    # Generate nuspec file from template
    log.info('Generating nuspec file')
    # Convert Ruby gem version format to NuGet/Chocolatey format
    # Replace .pre with -pre, .beta with -beta, etc.
    nuget_version = nuget_version_build.gsub(/\.([a-z]+)/, '-\1')
    erb_src = (CHOCOLATEY_SRC / 'package.erb.nuspec').read
    # Preprocess: replace %=variable% with <%= variable %>
    erb_src = erb_src.gsub(/%=([^%]+)%/, '<%=\1%>')
    # Use nuget_version instead of nuget_version_build for the nuspec
    nuspec_content = ERB.new(erb_src).result(binding).gsub(nuget_version_build, nuget_version)
    (path_build_dir / "#{CHOCO_PACKAGE_NAME}.nuspec").write(nuspec_content)

    # Create the Chocolatey package using nuget
    log.info('Creating Chocolatey package with nuget')
    Paths::RELEASE.mkpath
    Dir.chdir(path_build_dir) do
      run('nuget', 'pack', "#{CHOCO_PACKAGE_NAME}.nuspec", '-OutputDirectory', Paths::RELEASE)
    end

    package_path = Paths::RELEASE / "#{CHOCO_PACKAGE_NAME}.#{nuget_version_build}.nupkg"

    log.info("Created: #{package_path}")
  end
end
