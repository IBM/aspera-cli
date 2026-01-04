# Rakefile
# frozen_string_literal: true

require 'rake'
require 'erb'
require 'fileutils'
require 'aspera/cli/info'
require 'aspera/cli/version'
require_relative '../build/lib/build_tools'

CONTAINER_TOOL = ENV['CONTAINER_TOOL'] || 'podman'
TAG_VERSION = "#{Aspera::Cli::Info::CONTAINER}:#{GEM_VERSION}"
TAG_LATEST  = "#{Aspera::Cli::Info::CONTAINER}:latest"
CONTAINER_FOLDER = Paths::TOP / 'build/container'
TEMPLATE_DOCKERFILE = CONTAINER_FOLDER / 'Dockerfile.tmpl.erb'

# Extract optional gems
def optional_gems
  BuildTools.gems_in_group(Paths::GEMFILE, :optional).map{ |i| "'#{i}'"}.join(' ')
end

# Template processing (Makefile PROCESS_TEMPLATE)
#
# Replace "#erb: ..." with ERB tags, then run ERB.
def process_template(template_path, args = {})
  content = File.read(template_path)
    .gsub(/^#erb:(.*)/, '<%\1%>')
  ERB.new(content, trim_mode: '-').result_with_hash(args)
end

namespace :container do
  desc 'Build the container'
  task build: [TEMPLATE_DOCKERFILE] do
    docker_file = TMP / 'Dockerfile'
    docker_context = Paths::TOP
    arg_gem = if GEM_BETA
      Rake::Task['unsigned'].invoke
      run('ls', '-al', Paths::GEM_PACK_FILE)
      Paths::GEM_PACK_FILE.relative_path_from(docker_context).to_s
    else
      "#{Aspera::Cli::Info::GEM_NAME}:#{GEM_VERSION}"
    end
    docker_file.write(process_template(
      TEMPLATE_DOCKERFILE,
      arg_gem: arg_gem,
      arg_opt: optional_gems
    ))
    run(CONTAINER_TOOL, 'build', '--squash', '--tag', TAG_VERSION, '--tag', TAG_LATEST, '--file', docker_file, docker_context)
  end

  desc 'Test the container'
  task :test do
    run(CONTAINER_TOOL, 'run', '--tty', '--interactive', '--rm', TAG_VERSION, Aspera::Cli::Info::CMD_NAME, '-v')
  end

  desc 'Push only the version tag'
  task :push_version do
    run(CONTAINER_TOOL, 'push', TAG_VERSION)
  end

  desc 'Push only the latest tag'
  task :push_latest do
    run(CONTAINER_TOOL, 'push', TAG_LATEST)
  end

  desc 'Push version and latest tags'
  task push: %i[push_version push_latest]

  desc 'Show repo.'
  task :repo do
    puts Aspera::Cli::Info::CONTAINER
  end
end
