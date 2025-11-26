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
require_relative '../build_tools'

############################################################
# Constants / environment
############################################################

GEM_VERSION = ENV['GEM_VERSION'] || Aspera::Cli::VERSION
DIR_TMP = File.join(File.dirname(__dir__, 2), '/tmp')
CLI_EXEC_FILE = "#{Aspera::Cli::Info::CMD_NAME}.#{GEM_VERSION}.#{Aspera::Environment.instance.architecture}"
CLI_EXEC_PATH = File.join(DIR_TMP, CLI_EXEC_FILE)

############################################################
# Helper: run shell commands
############################################################

def install_gem(name, into)
  run('gem', 'install', name, '--no-document', '--install-dir', into)
end

############################################################
# Main build task (replaces Makefile + Ruby script)
############################################################

task default: :build

desc 'Build the single executable (default)'
task build: [CLI_EXEC_PATH]

file CLI_EXEC_PATH do
  ##########################################################
  # PREP
  ##########################################################

  top_dir = Pathname.new(__dir__).parent.parent
  main_tmp = top_dir / 'tmp'
  optional_gems = BuildTools.gems_in_group(top_dir / 'Gemfile', :optional)

  cli_bin_path = main_tmp / CLI_EXEC_FILE
  main_gem_version = "#{Aspera::Cli::Info::GEM_NAME}:#{GEM_VERSION}"
  tebako_version = '0.14.0'

  puts "Building executable: #{cli_bin_path}"

  ##########################################################
  # Tebako temp structure
  ##########################################################

  tebako_tmp   = main_tmp / 'tebako'
  tebako_env   = tebako_tmp / 'env'
  tebako_root  = tebako_tmp / 'root'
  FileUtils.mkdir_p([tebako_tmp, tebako_env, tebako_root])
  ENV['TMPDIR'] = tebako_tmp.realpath.to_s

  install_tmp = tebako_tmp / 'install'
  FileUtils.mkdir_p(install_tmp)

  ##########################################################
  # Install gems into staging area
  ##########################################################

  install_gem(main_gem_version, install_tmp)
  optional_gems.each{ |spec| install_gem(spec, install_tmp)}

  Dir.glob(install_tmp / 'cache/*.gem').each do |gem_file|
    FileUtils.mv(gem_file, tebako_root)
  end
  FileUtils.rm_rf(install_tmp)

  ##########################################################
  # Tebako container config
  ##########################################################

  tebako_container_image = 'ghcr.io/tamatebako/tebako-ubuntu-20.04:0.13.4'
  tebako_container_root = Pathname.new('/mnt/w')

  tebako_out_path = cli_bin_path
  tebako_prefix = []
  tebako_opts   = []

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

    run('gem', 'install', "tebako:#{tebako_version}")

  when Aspera::Environment::OS_LINUX
    local_root = tebako_root
    tebako_prefix = ['podman', 'run', '--rm',
                     '-v', "#{local_root}:#{tebako_container_root}", tebako_container_image]
    tebako_opts   = ['--patchelf']
    tebako_out_path = tebako_container_root / cli_bin_path.basename

  else
    raise "Unsupported OS: #{Aspera::Environment.instance.os}"
  end

  ##########################################################
  # Tebako build execution
  ##########################################################

  run(*(
    tebako_prefix +
    [
      'tebako', 'press',
      "--root=#{tebako_root}",
      "--entry-point=#{Aspera::Cli::Info::CMD_NAME}",
      "--output=#{tebako_out_path}",
      "--prefix=#{tebako_env}"
    ] +
    tebako_opts
  ))

  ##########################################################
  # Move artifact back if using container path
  ##########################################################

  if tebako_out_path.to_s.start_with?(tebako_container_root.to_s)
    src = local_root.join(tebako_out_path.relative_path_from(tebako_container_root))
    FileUtils.mv(src, cli_bin_path)
  end

  puts "✔ Build finished: #{cli_bin_path}"

  FileUtils.mkdir_p(File.dirname(CLI_EXEC_PATH))
  FileUtils.cp(cli_bin_path, CLI_EXEC_PATH)
end

############################################################
# CLEAN
############################################################

desc 'Remove built executable and temporary files'
task :clean do
  FileUtils.rm_f(CLI_EXEC_PATH)
  FileUtils.rm_f('nohup.out')
end
