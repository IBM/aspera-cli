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
TEBAKO_TMP   = Paths::TMP / 'tebako'
TEBAKO_ENV   = TEBAKO_TMP / 'env'
TEBAKO_ROOT  = TEBAKO_TMP / 'root'

def install_gem(name, into)
  run('gem', 'install', name, '--no-document', '--install-dir', into)
end

namespace :binary do
  desc 'Build the single executable'
  task :build, [:version] do |_t, args|
    gem_version_build = args[:version] || Aspera::Cli::VERSION
    path_cli_exec = Paths::RELEASE / "#{Aspera::Cli::Info::CMD_NAME}.#{gem_version_build}.#{Aspera::Environment.instance.architecture}"
    # Final destination
    Paths::RELEASE.mkpath
    # Temp folders
    [TEBAKO_TMP, TEBAKO_ENV, TEBAKO_ROOT].each(&:mkpath)
    ENV['TMPDIR'] = TEBAKO_TMP.realpath.to_s

    log.info('Installing gems into staging area')
    install_tmp = TEBAKO_TMP / 'install'
    install_tmp.mkpath
    install_gem("#{Aspera::Cli::Info::GEM_NAME}:#{gem_version_build}", install_tmp)
    # gems_in_group(Paths::GEMFILE, :optional).each{ |spec| install_gem(spec, install_tmp)}
    Dir.glob(install_tmp / 'cache/*.gem').each do |gem_file|
      FileUtils.mv(gem_file, TEBAKO_ROOT)
    end
    install_tmp.rmtree

    # Tebako container config
    tebako_container_workdir = Pathname.new('/mnt/w')
    tebako_cmd_pre = []
    tebako_cmd_post = []
    tebako_output = path_cli_exec
    puts "Building executable: #{tebako_output}"

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
      tebako_cmd_pre = ['podman', 'run', '--rm',
                        '-v', "#{TEBAKO_ROOT}:#{tebako_container_workdir}", TEBAKO_LINUX_CONTAINER_IMAGE]
      tebako_cmd_post = ['--patchelf']
      tebako_output = tebako_container_workdir / tebako_output.basename
    else
      raise "Unsupported OS: #{Aspera::Environment.instance.os}"
    end

    # Tebako build execution
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

    # Move artifact back if using container path
    FileUtils.mv(TEBAKO_ROOT / tebako_output.relative_path_from(tebako_container_workdir), path_cli_exec) if tebako_output != path_cli_exec
    puts "Build finished: #{path_cli_exec}"
  end
end
