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

CLI_EXEC_FILENAME = "#{Aspera::Cli::Info::CMD_NAME}.#{GEM_VERSION}.#{Aspera::Environment.instance.architecture}"
PATH_CLI_EXEC = Paths::RELEASE / CLI_EXEC_FILENAME
CLI_GEM_VERS_SPEC = "#{Aspera::Cli::Info::GEM_NAME}:#{GEM_VERSION}"
TEBAKO_VERSION = '0.14.0'
TEBAKO_LINUX_CONTAINER_IMAGE = 'ghcr.io/tamatebako/tebako-ubuntu-20.04:0.13.4'
TEBAKO_TMP   = Paths::TMP / 'tebako'
TEBAKO_ENV   = TEBAKO_TMP / 'env'
TEBAKO_ROOT  = TEBAKO_TMP / 'root'

def install_gem(name, into)
  run('gem', 'install', name, '--no-document', '--install-dir', into)
end

def fetch_gems
end

# clean   : Remove any temporary products.
CLEAN.push(TEBAKO_TMP)
# clobber : Remove any generated file.
CLOBBER.push(PATH_CLI_EXEC)

namespace :binary do
  task default: :build

  desc 'Build the single executable (default)'
  task build: [PATH_CLI_EXEC]

  file PATH_CLI_EXEC do
    Paths::RELEASE.mkpath
    [TEBAKO_TMP, TEBAKO_ENV, TEBAKO_ROOT].each(&:mkpath)
    ENV['TMPDIR'] = TEBAKO_TMP.realpath.to_s

    ##########################################################
    # Install gems into staging area
    ##########################################################
    install_tmp = TEBAKO_TMP / 'install'
    install_tmp.mkpath
    install_gem(CLI_GEM_VERS_SPEC, install_tmp)
    BuildTools.gems_in_group(Paths::TOP / 'Gemfile', :optional).each{ |spec| install_gem(spec, install_tmp)}
    Dir.glob(install_tmp / 'cache/*.gem').each do |gem_file|
      FileUtils.mv(gem_file, TEBAKO_ROOT)
    end
    install_tmp.rmtree

    ##########################################################
    # Tebako container config
    ##########################################################
    tebako_container_workdir = Pathname.new('/mnt/w')
    tebako_cmd_pre = []
    tebako_cmd_post = []
    tebako_output = PATH_CLI_EXEC
    puts "Building executable: #{tebako_output}"

    ##########################################################
    # OS handling
    ##########################################################
    case Aspera::Environment.instance.os
    when Aspera::Environment::OS_MACOS
      run('brew', 'update')
      run('brew', 'install', 'bash', 'binutils', 'bison', 'flex', 'gnu-sed', 'lz4', 'pkg-config', 'xz')
      run(
        'brew', 'install',
        'double-conversion', 'fmt', 'gdbm', 'glog',
        'jemalloc', 'libevent', 'libffi', 'libsodium',
        'libyaml', 'ncurses', 'openssl@3', 'zlib'
      )
      run('brew', 'install', 'boost@1.85')
      run('brew', 'link', '--force', 'boost@1.85')
      ENV['PATH'] =
        [
          File.join(%x(brew --prefix flex).strip, 'bin'),
          File.join(%x(brew --prefix bison).strip, 'bin'),
          ENV['PATH'].split(':').reject{ |p| p.include?('binutils')}
        ].join(':')
      run('gem', 'install', "tebako:#{TEBAKO_VERSION}")
    when Aspera::Environment::OS_LINUX
      tebako_cmd_pre = ['podman', 'run', '--rm',
                        '-v', "#{TEBAKO_ROOT}:#{tebako_container_workdir}", TEBAKO_LINUX_CONTAINER_IMAGE]
      tebako_cmd_post = ['--patchelf']
      tebako_output = tebako_container_workdir / tebako_output.basename
    else
      raise "Unsupported OS: #{Aspera::Environment.instance.os}"
    end

    ##########################################################
    # Tebako build execution
    ##########################################################

    run(*(
      tebako_cmd_pre +
      [
        'tebako',
        'press',
        "--root=#{TEBAKO_ROOT}",
        "--entry-point=#{Aspera::Cli::Info::CMD_NAME}",
        "--output=#{tebako_output}",
        "--prefix=#{TEBAKO_ENV}"
      ] +
      tebako_cmd_post
    ))

    ##########################################################
    # Move artifact back if using container path
    ##########################################################
    FileUtils.mv(TEBAKO_ROOT / tebako_output.relative_path_from(tebako_container_workdir), PATH_CLI_EXEC) if tebako_output != PATH_CLI_EXEC
    puts "✔ Build finished: #{PATH_CLI_EXEC}"
  end
end
