# Rakefile
# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/assert'
require_relative '../lib/aspera/cli/info'
require_relative '../lib/aspera/cli/version'
require_relative '../build/lib/build_tools'
require 'rake'
require 'erb'
require 'fileutils'
require 'json'
include BuildTools

CONTAINER_TOOL = ENV['CONTAINER_TOOL'] || 'podman'
# Name of the MCP server in the MCP Registry (registry.modelcontextprotocol.io), in label of the image
MCP_REGISTRY_NAME = 'io.github.IBM/aspera-cli'
# Label of the image checked by the MCP Registry
MCP_REGISTRY_LABEL = 'io.modelcontextprotocol.server.name'
# Schema of server.json
MCP_SERVER_SCHEMA = 'https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json'
# Configuration folder in the container
CONTAINER_CONFIG_FOLDER = "/home/cliuser/.aspera/#{Aspera::Cli::Info::CMD_NAME}".freeze

# Extract optional gems
def optional_gems
  gems_in_group(Paths::GEMFILE, :optional).map { |i| "'#{i}'" }.join(' ')
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
    gem_version = args[:version].to_s.empty? ? build_version : args[:version]
    use_specific_version(gem_version)
    docker_context = Paths::TOP
    arg_gem = if source.equal?(:remote)
      "#{Aspera::Cli::Info::GEM_NAME}:#{gem_version}"
    else
      # Gem file placed in pkg/ (e.g. downloaded from GitHub release), else built from sources
      Rake::Task['unsigned'].invoke unless built_gem_file.exist?
      built_gem_file.relative_path_from(docker_context).to_s
    end
    docker_file = TMP / 'Dockerfile'
    docker_file.write(process_template(
      Paths::DOCKERFILE_TEMPLATE,
      arg_gem:  arg_gem,
      arg_opt:  optional_gems,
      arg_ruby:     Aspera::Cli::Info::RUBY_TESTED_VERSION,
      arg_mcp_name: MCP_REGISTRY_NAME
    ))
    run(CONTAINER_TOOL, 'build', '--squash', '--tag', tag(gem_version), '--tag', tag(:latest), '--file', docker_file, docker_context)
  end

  desc 'Test the container'
  task :test do
    image_tag = tag(build_version)
    # No terminal: also runs in CI
    version = run(CONTAINER_TOOL, 'run', '--rm', image_tag, '-v', mode: :capture).first.strip
    raise "Unexpected version: #{version}, expected: #{build_version}" unless version.eql?(build_version)
    run(CONTAINER_TOOL, 'run', '--rm', image_tag, 'config', 'ascp', 'info')
    label = run(CONTAINER_TOOL, 'image', 'inspect', '--format', "{{index .Labels \"#{MCP_REGISTRY_LABEL}\"}}", image_tag, mode: :capture).first.strip
    raise "Unexpected label #{MCP_REGISTRY_LABEL}: #{label}, expected: #{MCP_REGISTRY_NAME}" unless label.eql?(MCP_REGISTRY_NAME)
  end

  desc 'Generate server.json for the MCP Registry (image of the version), in tmp/, empty or no version for current'
  task :server_json, %i[version] do |_t, args|
    version = args[:version].to_s.empty? ? build_version : args[:version]
    server = {
      '$schema'     => MCP_SERVER_SCHEMA,
      'name'        => MCP_REGISTRY_NAME,
      'title'       => 'IBM Aspera CLI',
      'description' => 'Operate IBM Aspera products: transfers, packages, files and administration',
      'repository'  => {'url' => Aspera::Cli::Info::SRC_URL, 'source' => 'github'},
      'websiteUrl'  => Aspera::Cli::Info::SITE_URL,
      'version'     => version,
      'packages'    => [{
        'registryType'     => 'oci',
        'identifier'       => tag(version),
        'transport'        => {'type' => 'stdio'},
        'runtimeArguments' => [{
          'type'        => 'named',
          'name'        => '--mount',
          'description' => 'Configuration folder of ascli (presets, vault), mounted in the container',
          'value'       => "type=bind,src={config_folder},dst=#{CONTAINER_CONFIG_FOLDER}",
          'isRequired'  => true,
          'variables'   => {
            'config_folder' => {
              'description' => "Configuration folder of ascli on the host, e.g. $HOME/.aspera/#{Aspera::Cli::Info::CMD_NAME}",
              'format'      => 'filepath',
              'isRequired'  => true
            }
          }
        }],
        'packageArguments' => %w[mcp server].map { |v| {'type' => 'positional', 'value' => v} }
      }]
    }
    file = Paths::TMP / 'server.json'
    file.write(JSON.pretty_generate(server))
    log.info { "Generated #{file}" }
  end

  desc 'Push only the version tag'
  task :push_version do
    run(CONTAINER_TOOL, 'push', tag(build_version))
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
