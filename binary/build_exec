#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'bundler'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/cli/info'

def run(*args)
  puts("Executing: #{args.join(' ')}")
  args = args.map(&:to_s)
  Aspera::Environment.secure_execute(exec: args.shift, args: args)
end

def gems_in_group(gemfile, group_name_symn)
  Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil).dependencies.filter_map do |dep|
    next unless dep.groups.include?(group_name_symn)
    "#{dep.name}:#{dep.requirement.to_s.delete(' ')}"
  end
end

def install_gem(name, into)
  run('gem', 'install', name, '--no-document', '--install-dir', into)
end

Aspera.assert(ARGV.length <= 1){"Usage: #{$PROGRAM_NAME} [GEM_VERSION]"}

top_dir = Pathname.new(__dir__).parent
main_tmp = top_dir / 'tmp'
gem_version = ARGV.first || Aspera::Cli::VERSION
optional_gems = gems_in_group(top_dir / 'Gemfile', :optional)
cli_bin_path = main_tmp / "#{Aspera::Cli::Info::CMD_NAME}.#{gem_version}.#{Aspera::Environment.instance.architecture}"
main_gem_version = "#{Aspera::Cli::Info::GEM_NAME}:#{gem_version}"
# tebako_version = '0.13.4'
tebako_version = '0.14.0'
puts "Building: #{cli_bin_path.basename}"

# ---------------------------------------------------------------------------
# Paths & temp directories
# ---------------------------------------------------------------------------

tebako_tmp = main_tmp / 'tebako'
tebako_env   = tebako_tmp / 'env'
tebako_root  = tebako_tmp / 'root'
FileUtils.mkdir_p([tebako_tmp, tebako_env, tebako_root])
ENV['TMPDIR'] = tebako_tmp.realpath.to_s

# ---------------------------------------------------------------------------
# Install gem(s) into a staging directory
# ---------------------------------------------------------------------------

install_tmp = tebako_tmp / 'install'
FileUtils.mkdir_p(install_tmp)
install_gem(main_gem_version, install_tmp)
optional_gems.each{ |spec| install_gem(spec, install_tmp)}

# Move only the .gem files to tebako_root
Dir.glob(install_tmp / 'cache/*.gem').each do |gem_file|
  FileUtils.mv(gem_file, tebako_root)
end
FileUtils.rm_rf(install_tmp)

# ---------------------------------------------------------------------------
# Tebako container configuration
# ---------------------------------------------------------------------------

tebako_container_image = 'ghcr.io/tamatebako/tebako-ubuntu-20.04:0.13.4'
tebako_container_root = Pathname.new('/mnt/w')

tebako_out_path = cli_bin_path
tebako_prefix = []
tebako_opts   = []

# ---------------------------------------------------------------------------
# OS handlers
# ---------------------------------------------------------------------------

case Aspera::Environment.instance.os
when Aspera::Environment::OS_MACOS
  # Homebrew environment setup
  run('brew', 'update')
  run('brew', 'install', 'bash', 'binutils', 'bison', 'flex', 'gnu-sed', 'lz4', 'pkg-config', 'xz')
  run('brew', 'install', 'double-conversion', 'fmt', 'gdbm', 'glog', 'jemalloc', 'libevent', 'libffi', 'libsodium', 'libyaml', 'ncurses', 'openssl@3', 'zlib')
  run('brew', 'install', 'boost@1.85')
  run('brew', 'link', '--force', 'boost@1.85')
  # Enforce flex and bison paths, but remove binutils to force macOS ar
  ENV['PATH'] = [
    File.join(%x(brew --prefix flex), 'bin'),
    File.join(%x(brew --prefix bison), 'bin'),
    ENV['PATH'].split(':').reject{ |p| p.include?('binutils')}
  ].join(':')
  run('gem', 'install', "tebako:#{tebako_version}")
when Aspera::Environment::OS_LINUX
  # For Podman-based Tebako
  local_root = tebako_root
  tebako_prefix = ['podman', 'run', '--rm', '-v', "#{local_root}:#{tebako_container_root}", tebako_container_image]
  tebako_opts   = ['--patchelf']
  tebako_out_path = tebako_container_root / cli_bin_path.basename
else Aspera.error_unexpected_value(Aspera::Environment.instance.os){'OS'}
end

# ---------------------------------------------------------------------------
# Tebako build
# ---------------------------------------------------------------------------

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

# Move file back if podman path was used
FileUtils.mv(local_root.join(tebako_out_path.relative_path_from(tebako_container_root)), cli_bin_path) if tebako_out_path.ascend.include?(tebako_container_root)

puts "✔ Build finished: #{cli_bin_path}"
