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

namespace :chocolatey do
  desc 'Create Chocolatey package'
  task :build, [:version] do |_t, args|
    version_build = args[:version] || build_version
    choco_package = Aspera::Cli::Info::GEM_NAME
    package_file_name = "aspera-cli.#{version_build}.nupkg"
    path_build_dir = Paths::TMP / 'build_chocolatey'
    path_tools_dir = path_build_dir / 'tools'

    # Clean and create build directories
    path_build_dir.rmtree if path_build_dir.exist?
    path_tools_dir.mkpath

    log.info("Generating Chocolatey package for #{Aspera::Cli::Info::GEM_NAME} v#{version_build}")
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
    nuspec_template = (CHOCOLATEY_SRC / 'ascli.nuspec').read
    # Update version in nuspec
    nuspec_content = nuspec_template.gsub(%r{<version>.*?</version>}, "<version>#{version_build}</version>")
    (path_build_dir / 'aspera-cli.nuspec').write(nuspec_content)

    # Create the Chocolatey package using nuget
    log.info('Creating Chocolatey package with nuget')
    Dir.chdir(path_build_dir) do
      run('nuget', 'pack', 'aspera-cli.nuspec')
    end

    # Move package to release directory
    Paths::RELEASE.mkpath
    package_source = path_build_dir / package_file_name
    package_target = Paths::RELEASE / package_file_name

    if package_source.exist?
      FileUtils.mv(package_source, package_target)
      log.info("Created: #{package_target}")
    else
      log.error("Package file not found: #{package_source}")
      raise 'Failed to create Chocolatey package'
    end
  end

  desc 'Test Chocolatey package installation locally'
  task :test, [:version] do |_t, args|
    version_build = args[:version] || build_version
    package_file_name = "aspera-cli.#{version_build}.nupkg"
    package_path = Paths::RELEASE / package_file_name

    unless package_path.exist?
      log.error("Package not found: #{package_path}")
      log.info("Run 'rake chocolatey:build' first")
      raise 'Package file not found'
    end

    log.info("Testing Chocolatey package: #{package_path}")
    log.warn('Note: Testing requires Windows with Chocolatey installed')
    log.info("To test on Windows, run: choco install aspera-cli --source #{Paths::RELEASE} --version #{version_build} --force --yes")
  end

  desc 'Uninstall Chocolatey package'
  task :uninstall do
    log.info('Uninstalling aspera-cli Chocolatey package')
    log.warn('Note: Uninstalling requires Windows with Chocolatey installed')
    log.info('To uninstall on Windows, run: choco uninstall aspera-cli --yes')
  end
end

# Made with Bob
