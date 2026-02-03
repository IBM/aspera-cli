# Rakefile
# frozen_string_literal: true

require 'rake'
require 'fileutils'
require 'pathname'
require 'bundler'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/cli/info'
require 'aspera/cli/version'

require_relative '../build/lib/build_tools'
include BuildTools

TEBAKO_VERSION = '0.13.4'
TEBAKO_LINUX_CONTAINER_IMAGE = 'ghcr.io/tamatebako/tebako-ubuntu-20.04:0.13.4'
PATH_WORKDIR = Paths::TMP / 'tebako'

# Build environment
TBK_PREFIX_DIRNAME = 'env'
# Place gem files there
TBK_ROOT_DIRNAME = 'root'

def install_gem(name, into)
  run('gem', 'install', name, '--no-document', '--install-dir', into)
end

namespace :binary do
  desc 'Build the single executable'
  task :build, [:version] do |_t, args|
    gem_version_build = args[:version] || specific_version

    log.info('Creating tebako environment')
    # Final destination folder
    Paths::RELEASE.mkpath
    # Temp folders
    PATH_WORKDIR.rmtree
    [TBK_PREFIX_DIRNAME, TBK_ROOT_DIRNAME].each{ |sub| (PATH_WORKDIR / sub).mkpath}
    ENV['TMPDIR'] = PATH_WORKDIR.realpath.to_s

    log.info('Installing gems into staging area')
    install_tmp = Paths::TMP / 'extract_gems'
    install_tmp.mkpath
    install_gem("#{Aspera::Cli::Info::GEM_NAME}:#{gem_version_build}", install_tmp)
    # gems_in_group(Paths::GEMFILE, :optional).each{ |spec| install_gem(spec, install_tmp)}
    Dir.glob(install_tmp / 'cache/*.gem').each do |gem_file|
      FileUtils.mv(gem_file, PATH_WORKDIR / TBK_ROOT_DIRNAME)
    end
    install_tmp.rmtree

    # prefix to tebako command
    tebako_cmd_prefix = []
    # additional options to tebako command
    tebako_cmd_options = []
    # Path used by tebako command
    tebako_work_path = PATH_WORKDIR
    puts 'Building executable'

    # OS handling
    case Aspera::Environment.instance.os
    when Aspera::Environment::OS_MACOS
      run(*%W[brew bundle install --file=#{Paths::TOP / 'build/binary/Brewfile'}])
      ENV['PATH'] =
        [
          File.join(%x(brew --prefix flex).strip, 'bin'),
          File.join(%x(brew --prefix bison).strip, 'bin'),
          ENV['PATH'].split(':').reject{ |p| p.include?('binutils')}
        ].join(':')
      run('gem', 'install', "tebako:#{TEBAKO_VERSION}")
    when Aspera::Environment::OS_LINUX
      # Tebako container config
      tebako_work_path = Pathname.new('/mnt/w')
      tebako_cmd_prefix = [
        'podman', 'run', '--rm',
        '-v', "#{PATH_WORKDIR}:#{tebako_work_path}",
        TEBAKO_LINUX_CONTAINER_IMAGE
      ]
      tebako_cmd_options = ['--patchelf']
    else
      raise "Unsupported OS: #{Aspera::Environment.instance.os}"
    end

    # Tebako build execution
    run(*(
      tebako_cmd_prefix +
      [
        'tebako',
        'press',
        "--entry-point=#{Aspera::Cli::Info::CMD_NAME}",
        "--output=#{tebako_work_path / Aspera::Cli::Info::CMD_NAME}",
        "--root=#{tebako_work_path / TBK_ROOT_DIRNAME}",
        "--prefix=#{tebako_work_path / TBK_PREFIX_DIRNAME}"
      ] +
      tebako_cmd_options
    ))

    # Move artifact to release folder
    # Target file path
    path_exec_target = Paths::RELEASE / "#{Aspera::Cli::Info::CMD_NAME}.#{gem_version_build}.#{Aspera::Environment.instance.architecture}"
    FileUtils.mv(PATH_WORKDIR / Aspera::Cli::Info::CMD_NAME, path_exec_target)
    puts "Build finished: #{path_exec_target}"
  end
end
