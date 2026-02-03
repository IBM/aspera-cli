# Rakefile
# frozen_string_literal: true

require 'rake'
require 'erb'
require 'fileutils'
require 'aspera/assert'
require 'aspera/cli/info'
require 'aspera/cli/version'
require_relative '../build/lib/build_tools'
include BuildTools

CONTAINER_TOOL = ENV['CONTAINER_TOOL'] || 'podman'

# Extract optional gems
def optional_gems
  gems_in_group(Paths::GEMFILE, :optional).map{ |i| "'#{i}'"}.join(' ')
end

# Template processing (Makefile PROCESS_TEMPLATE)
#
# Replace "#erb: ..." with ERB tags, then run ERB.
def process_template(template_path, args = {})
  content = File.read(template_path)
    .gsub(/^#erb:(.*)/, '<%\1%>')
  ERB.new(content, trim_mode: '-').result_with_hash(args)
end

# Tag for container
def tag(version)
  "#{Aspera::Cli::Info::CONTAINER}:#{version}"
end

namespace :container do
  desc 'Build the container, save version built for next tasks, empty or no version for current.'
  task :build, %i[source version] => [Paths::DOCKERFILE_TEMPLATE] do |_t, args|
    source = args[:source]&.to_sym || :remote
    Aspera.assert_values(source, %i[local remote])
    gem_version = args[:version].to_s.empty? ? specific_version : args[:version]
    use_specific_version(gem_version)
    docker_context = Paths::TOP
    arg_gem = if source.equal?(:remote)
      "#{Aspera::Cli::Info::GEM_NAME}:#{gem_version}"
    else
      Rake::Task['unsigned'].invoke
      Paths::GEM_PACK_FILE.relative_path_from(docker_context).to_s
    end
    docker_file = TMP / 'Dockerfile'
    docker_file.write(process_template(
      Paths::DOCKERFILE_TEMPLATE,
      arg_gem: arg_gem,
      arg_opt: optional_gems
    ))
    run(CONTAINER_TOOL, 'build', '--squash', '--tag', tag(gem_version), '--tag', tag(:latest), '--file', docker_file, docker_context)
  end

  desc 'Test the container'
  task :test do
    run(CONTAINER_TOOL, 'run', '--tty', '--interactive', '--rm', tag(specific_version), '-v')
    run(CONTAINER_TOOL, 'run', '--tty', '--interactive', '--rm', tag(specific_version), 'config', 'ascp', 'info')
  end

  desc 'Push only the version tag'
  task :push_version do
    run(CONTAINER_TOOL, 'push', tag(specific_version))
  end

  desc 'Push only the latest tag'
  task :push_latest do
    run(CONTAINER_TOOL, 'push', tag(:latest))
  end

  desc 'Push version and latest tags'
  task push: %i[push_version push_latest]

  desc 'Show repo.'
  task :repo do
    puts Aspera::Cli::Info::CONTAINER
  end
end
