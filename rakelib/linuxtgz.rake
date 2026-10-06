# Rakefile
# frozen_string_literal: true

require 'rake'
require 'etc'
require 'fileutils'
require 'pathname'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/rest'
require 'aspera/cli/info'
require 'aspera/cli/transfer_progress'

require_relative '../build/lib/build_tools'
include BuildTools

Aspera::Rest::Parameters.instance.progress_bar = Aspera::Cli::TransferProgress.new

# Folder with files specific to the Linux portable package
LINUX_PORTABLE_SRC = Paths::LINUX_TGZ_SRC / 'portable'
# Ruby source code archives
RUBY_SOURCE_BASE_URL = 'https://cache.ruby-lang.org/pub/ruby'
# Shared libraries of glibc (without `.so...`): provided by the system, so not bundled
GLIBC_LIBRARIES = %w[linux-vdso ld-linux-x86-64 ld-linux-aarch64 ld64 libc libm libmvec libpthread libdl librt libresolv libutil libanl].freeze
# Environment of the Ruby running rake (e.g. `bundle exec`): must not be used by the Ruby of the package
HOST_RUBY_ENV = %w[RUBYLIB RUBYOPT GEM_HOME GEM_PATH BUNDLE_GEMFILE BUNDLER_SETUP BUNDLE_BIN_PATH BUNDLER_VERSION].to_h { |var| [var, nil] }.freeze

# @param path [Pathname] File path
# @return [Boolean] `true` if file is an ELF executable or shared library (not an object file)
def elf_file?(path)
  return false unless path.file? && !path.symlink?
  header = path.binread(18)
  return false unless header&.start_with?("\x7FELF".b) && header.length.eql?(18)
  # e_type, with byte order of EI_DATA: ET_EXEC or ET_DYN
  [2, 3].include?(header[16, 2].unpack1(header.getbyte(5).eql?(2) ? 'n' : 'v'))
end

# Shared libraries needed by an ELF file, except the ones of glibc
# @param path [Pathname] ELF file
# @return [Hash{String => Pathname}] Library name (`soname`) => path on the build system
def library_dependencies(path)
  stdout, = Aspera::Environment.secure_execute('ldd', path.to_s, mode: :capture)
  stdout.each_line.filter_map do |line|
    soname, location = line.strip.split(' => ', 2)
    # e.g. `linux-vdso.so.1 (0x...)`, `/lib64/ld-linux-x86-64.so.2 (0x...)`
    next if location.nil? || GLIBC_LIBRARIES.include?(soname.sub(/\.so.*\z/, ''))
    raise "Library not found: #{soname} (needed by #{path})" if location.start_with?('not found')
    [soname, Pathname(location.sub(/\s*\(0x\h+\)\z/, ''))]
  end.to_h
end

# @param gem_version [String]   Version of gem
# @param folder      [Pathname] Download folder
# @return [Pathname] Path to the .gem file
def package_gem_file(gem_version, folder)
  location = package_gem_location(gem_version)
  return Pathname(location) unless location.eql?("#{Aspera::Cli::Info::GEM_NAME}:#{gem_version}")
  run('gem', 'fetch', Aspera::Cli::Info::GEM_NAME, '--version', gem_version, chdir: folder)
  folder / "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version}.gem"
end

namespace :linuxtgz do
  desc 'Create portable archive for Linux (extract and run, no installation). ' \
    'Builds Ruby: requires gcc, make, patchelf, and development files of openssl, libyaml, zlib, libffi'
  task :portable, [:version] do |_t, args|
    Aspera.assert(Aspera::Environment.instance.os.eql?(Aspera::Environment::OS_LINUX)) { 'The Linux portable package must be built on Linux' }
    gem_version_build = args[:version] || build_version
    platform = Aspera::Environment.instance.architecture
    # Same naming as the single executable: the package requires a glibc at least as recent as the one of the build system
    package_name = "#{Aspera::Cli::Info::GEM_NAME}-#{gem_version_build}-#{platform}-glibc#{glibc_version}-portable"
    path_build_dir = Paths::TMP / 'build_linux_portable'
    path_download_dir = path_build_dir / 'download'
    path_package_dir = path_build_dir / package_name
    path_build_dir.rmtree if path_build_dir.exist?
    path_download_dir.mkpath
    path_package_dir.mkpath

    log.info("Generating Linux portable package for #{Aspera::Cli::Info::GEM_NAME} v#{gem_version_build}")
    log.info("Building in #{path_build_dir}")

    gem_file = package_gem_file(gem_version_build, path_download_dir)
    sdk_version, ruby_version = package_versions(gem_file, gem_version_build)

    log.info("Building Ruby #{ruby_version}")
    ruby_source = download_file("#{RUBY_SOURCE_BASE_URL}/#{ruby_version[/\A\d+\.\d+/]}/ruby-#{ruby_version}.tar.gz", path_download_dir / "ruby-#{ruby_version}.tar.gz")
    run('tar', '-xzf', ruby_source, '-C', path_download_dir)
    path_ruby_source_dir = path_download_dir / "ruby-#{ruby_version}"
    path_ruby_dir = path_package_dir / 'ruby'
    # --enable-load-relative: Ruby finds its libraries relative to its executable, so the package can be extracted anywhere
    # libruby is static (default): no libruby.so to locate
    # --without-gmp: one less shared library to bundle (GMP only speeds up operations on very large integers)
    run('./configure', "--prefix=#{path_ruby_dir}", '--enable-load-relative', '--disable-install-doc', '--without-gmp', chdir: path_ruby_source_dir, env: HOST_RUBY_ENV)
    run('make', "-j#{Etc.nprocessors}", chdir: path_ruby_source_dir, env: HOST_RUBY_ENV)
    run('make', 'install', chdir: path_ruby_source_dir, env: HOST_RUBY_ENV)

    log.info('Installing gems')
    path_gems_dir = path_package_dir / 'gems'
    # Dependencies are resolved, and native extensions built, by the Ruby of the package, with the gem path of the launcher
    run(
      path_ruby_dir / 'bin' / 'gem', 'install', gem_file, '--no-document', '--install-dir', path_gems_dir, '--bindir', path_gems_dir / 'bin',
      env: HOST_RUBY_ENV.merge('GEM_HOME' => path_gems_dir.to_s, 'GEM_PATH' => path_gems_dir.to_s)
    )
    # Not needed at runtime: documentation, C headers, static library, cached gem files, object files of native extensions
    [
      path_ruby_dir / 'share', path_ruby_dir / 'include', path_ruby_dir / 'lib' / 'pkgconfig', *path_ruby_dir.glob('lib/libruby*-static.a'),
      *path_ruby_dir.glob('lib/ruby/gems/*/cache'), path_gems_dir / 'cache', *path_package_dir.glob('**/*.o')
    ].each { |path| FileUtils.rm_rf(path) }

    log.info('Bundling shared libraries')
    # The package runs on Linux systems with a glibc at least as recent as the one of the build system.
    # Other shared libraries (e.g. OpenSSL) may be missing on the target system, or of another version: they are bundled.
    path_lib_dir = path_ruby_dir / 'lib'
    elf_files = path_package_dir.glob('**/*').select { |path| elf_file?(path) }
    elf_files.map { |path| library_dependencies(path) }.reduce({}, :merge).each do |soname, location|
      log.info("Bundling #{soname} from #{location}")
      FileUtils.cp(location.realpath, path_lib_dir / soname)
      (path_lib_dir / soname).chmod(0o755)
      elf_files.push(path_lib_dir / soname)
    end
    # Debug symbols are not needed
    run('strip', '--strip-unneeded', *elf_files)
    # Each binary finds the bundled libraries relative to its own location
    elf_files.group_by(&:dirname).each do |folder, files|
      relative = path_lib_dir.relative_path_from(folder).to_s
      run('patchelf', '--set-rpath', relative.eql?('.') ? '$ORIGIN' : "$ORIGIN/#{relative}", *files)
    end

    log.info('Installing Transfer SDK')
    path_sdk_dir = path_package_dir / 'sdk'
    install_package_sdk(download_sdk_archive(sdk_version, platform, path_download_dir), sdk_version, path_sdk_dir)
    # Archive extraction does not keep file modes
    path_sdk_dir.glob('**/*').select { |path| elf_file?(path) }.each { |path| path.chmod(0o755) }

    log.info('Adding launcher and README')
    LINUX_PORTABLE_SRC.each_child { |path| FileUtils.cp(path, path_package_dir, preserve: true) }

    log.info('Generating archive')
    Paths::RELEASE.mkpath
    tgz_target = Paths::RELEASE / "#{package_name}.tgz"
    # Files in a folder named after the archive
    run('tar', '-czf', tgz_target, package_name, chdir: path_build_dir)

    log.info("Created: #{tgz_target}")
  end
end
