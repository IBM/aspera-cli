# Rakefile
# frozen_string_literal: true

require 'rake'
require 'fileutils'
require 'pathname'
require 'tmpdir'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/cli/info'
require 'aspera/cli/version'

require_relative '../build/lib/build_tools'
include BuildTools

# AppImage build configuration
APP_IMAGE_SRC = Paths::BUILD / 'appimage'
APP_NAME = 'Ascli'
# RUBY_VERSION = '3.2.2'
RUBY_VERSION = '4.0.2'
CONTAINER_IMAGE = 'ubuntu:20.04'
CONTAINER_TOOL = ENV['CONTAINER_TOOL'] || 'podman'

# Detect the system architecture and convert it to AppImage naming convention
# Returns: 'x86_64' for Intel/AMD 64-bit, 'aarch64' for ARM 64-bit
def linux_architecture
  case Aspera::Environment.instance.cpu
  when Aspera::Environment::CPU_X86_64 then 'x86_64'
  when Aspera::Environment::CPU_ARM64 then 'aarch64'
  else Aspera.error_unexpected_value(Aspera::Environment.instance.cpu){'architecture'}
  end
end

# @return [Pathname] path to the built AppImage for a given version
def built_appimage_path(version)
  Paths::RELEASE / "#{APP_NAME}-#{version}-#{linux_architecture}.AppImage"
end

def build_in_container(build_script_path, app_dir, output_file)
  log.info('Container build')
  host_build_dir = app_dir.parent
  # Container paths
  container_build_dir = '/build'
  container_output_dir = '/output'
  container_appdir = "#{container_build_dir}/#{app_dir.basename}"
  container_script = "#{container_build_dir}/#{build_script_path.basename}"
  container_output_path = "#{container_output_dir}/#{output_file.basename}"

  # Build the container command
  cmd = [
    CONTAINER_TOOL, 'run', '--rm', '--interactive', '--tty',
    '--volume', "#{host_build_dir}:#{container_build_dir}",
    '--volume', "#{Paths::RELEASE}:#{container_output_dir}",
    '--workdir', container_build_dir,
    CONTAINER_IMAGE,
    'bash',
    container_script,
    container_appdir,
    container_output_path,
    RUBY_VERSION,
    linux_architecture
  ]
end

namespace :appimage do
  desc 'Build the AppImage package'
  task :build, [:version] do |_t, args|
    gem_version_build = args[:version] || build_version

    log.info("Building AppImage for #{Aspera::Cli::Info::GEM_NAME} v#{gem_version_build}")
    log.info("Detected architecture: #{linux_architecture}")

    # Final destination folder
    Paths::RELEASE.mkpath

    # Create temporary directory for build files
    Dir.mktmpdir('aspera-appimage-build-') do |tmpdir|
      build_dir = Pathname(tmpdir)
      app_dir = build_dir / "#{APP_NAME}.AppDir"
      build_script_path = build_dir / 'build-container.sh'
      output_file = built_appimage_path(gem_version_build)

      log.info('Cleaning previous build')
      output_file.delete if output_file.exist?

      log.info('Creating AppDir structure')
      (app_dir / 'usr').mkpath

      log.info('Copying AppImage source files to build directory')
      # Copy AppRun script
      (app_dir / 'AppRun').write((APP_IMAGE_SRC / 'AppRun').read)
      (app_dir / 'AppRun').chmod(0o755)

      # Copy desktop file
      (app_dir / 'ascli.desktop').write((APP_IMAGE_SRC / 'ascli.desktop').read)

      # Copy icon (mascot.svg from docs)
      (app_dir / 'ascli.svg').write(Paths::MASCOT_SVG.read)

      log.info('Creating container build script')
      # Copy the build.sh script to the temporary directory
      Aspera.assert((APP_IMAGE_SRC / 'build.sh').exist?){"Build script not found at #{APP_IMAGE_SRC / 'build.sh'}"}
      build_script_path.write((APP_IMAGE_SRC / 'build.sh').read)
      build_script_path.chmod(0o755)

      # Execute the container build command
      run(*build_in_container(build_script_path, app_dir, output_file))

      # Verify the build was successful
      Aspera.assert(output_file.exist?){"AppImage build failed: #{output_file} not found"}

      log.info('Build complete!')
      log.info("Output: #{output_file}")
      size_mb = output_file.size / (1024.0 * 1024.0)
      log.info('Size: %.1f MB' % size_mb)
    end
  end

  desc 'Test the AppImage'
  task :test, [:version] do |_t, args|
    gem_version_build = args[:version] || build_version
    appimage_path = built_appimage_path(gem_version_build)

    Aspera.assert(appimage_path.exist?){"AppImage not found: #{appimage_path}"}

    log.info("Testing AppImage: #{appimage_path}")
    run(appimage_path, '-v')
    run(appimage_path, 'config', 'ascp', 'info')
  end

  desc 'Release the AppImage on GitHub'
  task :release, [:version] do |_t, args|
    version = args[:version] || build_version
    asset_path = built_appimage_path(version)
    Aspera.assert(asset_path.exist?){"AppImage not found: #{asset_path}"}
    run('gh', 'release', 'upload', "v#{version}", asset_path)
  end
end

# Made with Bob
