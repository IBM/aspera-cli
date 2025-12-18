# Rakefile
# frozen_string_literal: true

require 'rake'
require 'erb'
require 'fileutils'
require 'aspera/cli/info'
require 'aspera/cli/version'
require_relative '../build/lib/build_tools'

PATH_GEMFILE = Paths::TOP / 'aspera-cli.gem'
TOOL = ENV['TOOL'] || 'podman'
TAG_VERSION = "#{Aspera::Cli::Info::CONTAINER}:#{GEM_VERSION}"
TAG_LATEST  = "#{Aspera::Cli::Info::CONTAINER}:latest"

# Extract optional gems
def optional_gems
  BuildTools.gems_in_group(File.join(Paths::TOP, 'Gemfile'), :optional).map{ |i| "'#{i}'"}.join(' ')
end

# Template processing (Makefile PROCESS_TEMPLATE)
#
# Replace "#erb: ..." with ERB tags, then run ERB.
def process_template(template_path, args = {})
  content = File.read(template_path)
    .gsub(/^#erb:(.*)/, '<%\1%>')

  ERB.new(content, trim_mode: '-').result_with_hash(args)
end

##################################
# DEFAULT
##################################
task default: :build

##################################
# BUILD
##################################

desc 'Build the container (default)'
task build: ['Dockerfile.tmpl.erb'] do
  out = process_template(
    'Dockerfile.tmpl.erb',
    arg_gem: "#{Aspera::Cli::Info::GEM_NAME}:#{GEM_VERSION}",
    arg_opt: optional_gems
  )
  File.write('Dockerfile', out)
  run(TOOL, 'build', '--squash', '--tag', TAG_VERSION, '--tag', TAG_LATEST, '.')
end

desc 'Test the container'
task :test do
  run(TOOL, 'run', '--tty', '--interactive', '--rm', TAG_VERSION, Aspera::Cli::Info::CMD_NAME, '-v')
end

##################################
# PUSH
##################################

desc 'Push only the version tag'
task :push_version do
  run(TOOL, 'push', TAG_VERSION)
end

desc 'Push only the latest tag'
task :push_latest do
  run(TOOL, 'push', TAG_LATEST)
end

desc 'Push version and latest tags'
task push: %i[push_version push_latest]

##################################
# BETA BUILD
##################################

task PATH_GEMFILE do
  Dir.chdir(Paths::TOP){run('make', 'unsigned_gem')}
end

task beta_build_target: ['Dockerfile.tmpl.erb', PATH_GEMFILE] do
  FileUtils.cp(PATH_GEMFILE, 'aspera-cli-beta.gem')
  out = process_template(
    'Dockerfile.tmpl.erb',
    arg_gem: 'aspera-cli-beta.gem',
    arg_opt: optional_gems
  )
  File.write('Dockerfile', out)
  run(TOOL, 'build', '--squash', '--tag', TAG_VERSION, '.')
end

task :beta_build do
  gem_vers_beta = ENV['GEM_VERS_BETA'] || raise('GEM_VERS_BETA required')
  FileUtils.mkdir_p(Paths::TMP)
  File.write(File.join(Paths::TMP, 'beta.txt'), gem_vers_beta)
  run('rake', "GEM_VERSION=#{gem_vers_beta}", 'beta_build_target')
end

task :beta_push do
  gem_ver = File.read(File.join(Paths::TMP, 'beta.txt')).strip
  run('rake', "GEM_VERSION=#{gem_ver}", 'push_version')
end

task :beta_test do
  gem_ver = File.read(File.join(Paths::TMP, 'beta.txt')).strip
  run('rake', "GEM_VERSION=#{gem_ver}", 'test')
end

##################################
# CLEAN
##################################

task :clean do
  FileUtils.rm_f('Dockerfile')
  FileUtils.rm_f('aspera-cli-beta.gem')
  FileUtils.rm_f(File.join(Paths::TMP, 'beta.txt'))
end

##################################
# INFO
##################################

task :info do
  puts "Repo: #{Aspera::Cli::Info::CONTAINER}"
end
