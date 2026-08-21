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
require 'aspera/rest'
require 'aspera/cli/transfer_progress'

require_relative '../build/lib/build_tools'
include BuildTools

TEBAKO_VERSION = '0.13.4'
TEBAKO_LINUX_CONTAINER_IMAGE = 'ghcr.io/tamatebako/tebako-ubuntu-20.04:0.13.4'
PATH_WORKDIR = Paths::TMP / 'tebako'

# Build environment
TBK_PREFIX_DIRNAME = 'env'
# Place gem files there
TBK_ROOT_DIRNAME = 'root'

OCRAN_VERSION = '1.4.5'
PATH_WORKDIR_OCRAN = Paths::TMP / 'ocran'
# Gems that are only `require`d lazily (inside methods, not at load time), so Ocran's
# default dependency detection never sees them loaded and would otherwise omit them.
OCRAN_LAZY_GEMS = %w[websocket vault marcel jwt execjs rubyzip].freeze
# Latest CosmoRuby release: a self-contained cosmopolitan Ruby (APE) usable with
# `ocran --cosmo-ruby`, needed for single-file executables that run unmodified
# on Linux, macOS and Windows.
COSMO_RUBY_URL = 'https://github.com/Largo/cosmoruby/releases/latest/download/ruby.com'

# Download CosmoRuby's `ruby.com` into the given folder and make it executable.
# @param into [Pathname] destination folder
# @return [Pathname] path to the downloaded `ruby.com`
def download_cosmo_ruby(into)
  cosmo_ruby_path = into / 'ruby.com'
  Aspera::RestParameters.instance.progress_bar = Aspera::Cli::TransferProgress.new
  Aspera::Rest.new(base_url: File.dirname(COSMO_RUBY_URL), redirect_max: 5)
    .read(File.basename(COSMO_RUBY_URL), save_to_file: cosmo_ruby_path)
  cosmo_ruby_path.chmod(0o755)
  cosmo_ruby_path
end

def install_gem(name, into)
  run('gem', 'install', name, '--no-document', '--install-dir', into)
end

# Path to Ocran's own exe/ocran script (as opposed to its RubyGems bin stub), once
# Ocran has been installed with `install_gem` into the given staging folder.
#
# Invoking this file directly with `ruby` (instead of running the `ocran`
# executable) avoids RubyGems' Gem.activate_and_load_bin_path, which activates
# Ocran's own runtime dependency (fiddle) before Ocran's dependency-detection
# run even starts. That leaks fiddle into Gem.loaded_specs, where Ocran
# mistakes it for an application dependency, fatal under --cosmo-ruby, which
# rejects any native gem the cosmopolitan Ruby payload does not itself provide.
#
# Built from the staging folder directly (rather than looked up through
# Gem::Specification) because under `bundle exec` RubyGems is restricted to the
# gems locked in this project's Gemfile.lock, so a gem installed into a
# separate staging folder is invisible to Gem::Specification lookups here.
# @param staging_dir [Pathname] folder Ocran was installed into
def ocran_exe_path(staging_dir)
  staging_dir / 'gems' / "ocran-#{OCRAN_VERSION}" / 'exe' / 'ocran'
end

# @return path to the built .tgz archive for a given version
def built_tgz_path(version)
  Paths::RELEASE / "#{Aspera::Cli::Info::CMD_NAME}-#{version}-#{Aspera::Environment.instance.architecture}.tgz"
end

namespace :binary do
  desc 'Build the single executable'
  task :build, [:version] do |_t, args|
    gem_version_build = args[:version] || build_version

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

    # Package artifact into a .tgz archive in the release folder
    exec_file = PATH_WORKDIR / Aspera::Cli::Info::CMD_NAME
    exec_file.chmod(0o755)
    path_tgz_target = built_tgz_path(gem_version_build)
    Dir.chdir(PATH_WORKDIR) do
      run('tar', 'czf', path_tgz_target.to_s, Aspera::Cli::Info::CMD_NAME)
    end
    exec_file.delete
    puts "Build finished: #{path_tgz_target}"
  end

  desc 'Build the single executable using Ocran (alternative to :build, same .tgz output). ' \
    'Pass "cosmo" as 2nd arg to produce a single binary that runs unmodified on Linux/macOS/Windows'
  task :ocran, [:version, :cosmo] do |_t, args|
    use_cosmo_ruby = args[:cosmo].eql?('cosmo')
    gem_version_build = args[:version] || build_version

    log.info('Creating Ocran staging area')
    # Final destination folder
    Paths::RELEASE.mkpath
    # Temp folder used as GEM_HOME for staging, and as Ocran's working directory
    PATH_WORKDIR_OCRAN.rmtree
    PATH_WORKDIR_OCRAN.mkpath
    ENV['TMPDIR'] = PATH_WORKDIR_OCRAN.realpath.to_s

    log.info('Installing gems into staging area')
    install_gem("#{Aspera::Cli::Info::GEM_NAME}:#{gem_version_build}", PATH_WORKDIR_OCRAN)

    log.info('Installing Ocran')
    # Installed into the same staging folder as aspera-cli (rather than a global
    # `gem install`), so its exe/ocran script can be found at a deterministic path:
    # under `bundle exec`, RubyGems only sees the gems locked in this project's
    # Gemfile.lock, so a gem installed elsewhere afterwards stays invisible to
    # Gem::Specification lookups in this process.
    install_gem("ocran:#{OCRAN_VERSION}", PATH_WORKDIR_OCRAN)

    # Options appended to the ocran command line
    ocran_extra_options = []
    if use_cosmo_ruby
      log.info('Downloading CosmoRuby')
      ocran_extra_options += ['--cosmo-ruby', download_cosmo_ruby(PATH_WORKDIR_OCRAN).to_s]
    end

    puts 'Building executable'
    exec_file = PATH_WORKDIR_OCRAN / Aspera::Cli::Info::CMD_NAME
    # Only expose the staging area as a gem path: unlike running the `ocran`
    # executable (a RubyGems bin stub), invoking exe/ocran directly does not need
    # the host's default gem locations to find Ocran or its dependencies. Leaving
    # them out also keeps host-only gems (e.g. ed25519, a development-only
    # dependency of net-ssh present on this dev machine's system gem path) from
    # leaking into the dependency-detection run, where Ocran would otherwise
    # mistake them for application dependencies -- fatal under --cosmo-ruby.
    #
    # GEM_HOME must be pointed here too, not just cleared: unset (nil), RubyGems
    # falls back to the host Ruby's compiled-in default gem directory, and
    # Gem.path always includes Gem.dir -- so the host's default gem directory
    # would leak back in regardless of GEM_PATH.
    ocran_gem_path = PATH_WORKDIR_OCRAN.to_s
    # `aspera-cli` plugins and some of its gems (websocket, vault, marcel, jwt, execjs,
    # rubyzip) are only `require`d lazily, so Ocran's dependency detection never sees
    # them: force them in entirely with --gem-full.
    gem_full_list = ([Aspera::Cli::Info::GEM_NAME] + OCRAN_LAZY_GEMS).join(',')
    run(
      # Invoke Ocran's exe/ocran script directly with `ruby`, instead of running the
      # `ocran` executable (a RubyGems bin stub): the bin stub uses
      # Gem.activate_and_load_bin_path, which activates Ocran's own runtime
      # dependency (fiddle) up front. That leaks fiddle into Gem.loaded_specs, where
      # Ocran's dependency detection mistakes it for an application dependency --
      # fatal under --cosmo-ruby, which rejects any native gem the cosmopolitan Ruby
      # payload does not itself provide.
      'ruby', ocran_exe_path(PATH_WORKDIR_OCRAN).to_s,
      (PATH_WORKDIR_OCRAN / 'bin' / Aspera::Cli::Info::CMD_NAME).to_s,
      "--gem-full=#{gem_full_list}",
      *ocran_extra_options,
      '--output', exec_file.to_s,
      env: {
        'GEM_PATH'        => ocran_gem_path,
        'GEM_HOME'        => ocran_gem_path,
        # Must be cleared: they would leak into Ocran's dependency-detection run and
        # get baked into the packaged app instead of the staged gem files
        'RUBYLIB'         => nil,
        'RUBYOPT'         => nil,
        # This rake task runs under `bundle exec`: without clearing these, Bundler's
        # RubyGems patch would refuse to run a command outside its Gemfile
        'BUNDLE_GEMFILE'  => nil,
        'BUNDLER_SETUP'   => nil,
        'BUNDLE_BIN_PATH' => nil
      }
    )

    # Package artifact into the same .tgz archive as binary:build
    exec_file.chmod(0o755)
    path_tgz_target = built_tgz_path(gem_version_build)
    Dir.chdir(PATH_WORKDIR_OCRAN) do
      run('tar', 'czf', path_tgz_target.to_s, Aspera::Cli::Info::CMD_NAME)
    end
    exec_file.delete
    puts "Build finished: #{path_tgz_target}"
  end

  # Release on GitHub
  desc 'Release the executable on GitHub: args: version'
  task :release, [:version] do |_t, args|
    version = args[:version] || build_version
    asset_path = built_tgz_path(version)
    run('gh', 'release', 'upload', "v#{version}", asset_path)
  end
end
