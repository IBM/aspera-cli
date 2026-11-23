# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/environment'
require_relative '../../lib/aspera/log'
require_relative '../../lib/aspera/rest'
require_relative '../../lib/aspera/products/transferd'
require_relative '../../lib/aspera/products/desktop'
require_relative '../../lib/aspera/products/connect'
require_relative '../../lib/aspera/products/other'
require_relative 'paths'
require_relative 'test_env'
require 'uri'
require 'xmlsimple'

# Detect versions of servers and transfer agents used by the test suite, for the release notes.
# Servers: plugins of the `default` preset of the test configuration, detected with their test preset.
# Agents: products installed on this computer, found as `ascli` finds them.
module TestedVersions
  # Product name of each server plugin (detected names are not consistent)
  SERVER_PRODUCTS = {
    aoc:          'IBM Aspera on Cloud',
    console:      'IBM Aspera Console',
    faspex5:      'IBM Aspera Faspex',
    faspio:       'IBM Aspera faspio Gateway',
    httpgw:       'IBM Aspera HTTP Gateway',
    node:         'IBM Aspera High-Speed Transfer Server (Node API)',
    orchestrator: 'IBM Aspera Orchestrator',
    server:       'IBM Aspera High-Speed Transfer Server (SSH)',
    shares:       'IBM Aspera Shares'
  }.freeze
  # Agents that use a server: same product and version as the server of this plugin
  AGENT_SERVERS = {node: :node, httpgw: :httpgw}.freeze
  # Detection results that are not a version
  NOT_VERSIONS = ['unknown', 'requires authentication'].freeze
  # Leading letters of a version (e.g. `F5.0.19`)
  VERSION_PREFIX = /\A[A-Za-z]+(?=\d)/
  private_constant :SERVER_PRODUCTS, :AGENT_SERVERS, :NOT_VERSIONS, :VERSION_PREFIX

  class << self
    # @return [Hash] `servers`, `agents` and `tested_with`, as stored in `Paths::SERVERS_TESTED`
    def detect
      servers = detect_servers
      {
        'servers'     => servers.sort_by { |s| s['plugin'] },
        'agents'      => detect_agents(servers).sort_by { |a| a['agent'] },
        'tested_with' => {
          'ruby'     => RUBY_VERSION,
          'platform' => Aspera::Environment.instance.architecture
        }
      }
    end

    private

    # @return [Hash] Test configuration
    def config
      TestEnv.configuration
    end

    # Value of a test preset parameter, with references `@preset:<name>.<param>` (and `@extend:`) resolved
    # @return [String, nil]
    def preset_param(preset, param)
      value = config.dig(preset, param)
      return value unless value.is_a?(String)
      value = value.delete_prefix('@extend:')
      if (m = value.match(/\A@preset:(\w+)\.(\w+)\z/))
        return preset_param(*m.captures)
      end
      value.gsub(/@preset:(\w+)\.(\w+)@/) { preset_param(Regexp.last_match(1), Regexp.last_match(2)) }
    end

    # @return [String, nil] Version without prefix, or nil if not a version
    def normalize(version)
      return if version.nil? || NOT_VERSIONS.include?(version.to_s)
      version.to_s.sub(VERSION_PREFIX, '')
    end

    # @return [Array<Hash>] `plugin`, `product`, `version`
    def detect_servers
      Aspera::Rest::Parameters.instance.session_cb = lambda do |http|
        http.open_timeout = 5
        http.read_timeout = 5
      end
      Aspera::Rest::Parameters.instance.retry_max = 0
      Aspera::Rest::Parameters.instance.retry_on_timeout = false
      Aspera::Rest::Parameters.instance.retry_on_error = false
      defaults = config['default'] || {}
      versions = {}
      urls = {}
      # `server` last: it uses the version of `node` on the same host
      (SERVER_PRODUCTS.keys - [:server]).push(:server).each do |plugin|
        preset = defaults[plugin.to_s]
        url = preset && preset_param(preset, 'url')
        next Aspera::Log.log.warn("#{plugin}: no preset with url in test configuration") if url.nil?
        urls[plugin] = url
        versions[plugin] = detect_server(plugin, preset, url, versions, urls)
        Aspera::Log.log.info("#{plugin}: #{versions[plugin] || 'not detected'}")
      rescue StandardError => e
        Aspera::Log.log.warn("#{plugin}: detection failed: #{e.message}")
      end
      versions.filter_map do |plugin, version|
        {'plugin' => plugin.to_s, 'product' => SERVER_PRODUCTS[plugin], 'version' => version} unless version.nil?
      end
    end

    # @return [String, nil] Version of the server
    def detect_server(plugin, preset, url, versions, urls)
      case plugin
      when :server
        # SSH detection gives the version of SSH: HSTS version is the one of its Node API
        return versions[:node] if urls.key?(:node) && URI.parse(urls[:node]).host.eql?(URI.parse(url).host)
        Aspera::Log.log.warn('server: no Node API on the same host')
        nil
      when :node
        require_relative '../../lib/aspera/plugins/node/api'
        normalize(Aspera::Plugins::Node::Api.new(
          base_url: url,
          auth:     {type: :basic, username: preset_param(preset, 'username'), password: preset_param(preset, 'password')}
        ).read('info')['version'])
      else
        normalize(plugin_class(plugin).detect(url)&.dig(:version))
      end
    end

    # @param plugin [Symbol] Name of a plugin that provides commands (single file or bundle)
    # @return [Class] Commands class of the plugin
    def plugin_class(plugin)
      require 'aspera/cli/plugins/config'
      factory = Aspera::Cli::Plugins::Factory.instance
      unless @plugins_scanned
        factory.add_lookup_folder(Aspera::Cli::Plugins::Config.gem_plugins_folder)
        factory.add_plugins_from_lookup_folders
        @plugins_scanned = true
      end
      factory.plugin_class(plugin)
    end

    # @return [Array<Hash>] `agent`, `product`, `version`
    def detect_agents(servers)
      agents = []
      # Default SDK folder, as `ascli` (the test configuration does not set `sdk_folder`)
      require 'aspera/cli/plugins/config'
      Aspera::Products::Transferd.sdk_directory = Aspera::Cli::Plugins::Config.default_app_main_folder(app_name: Aspera::Plugins::TransferAgents::AscpActions::TRANSFERD_APP_NAME)
      sdk = find_product(Aspera::Products::Transferd)
      if sdk
        # `ascp` of the SDK (the SDK version is the one of `transferd`)
        agents.push(agent(:direct, 'IBM Aspera ascp', exe_versions(sdk[:ascp_path], '-A')['ascp']))
        daemon = Aspera::Products::Transferd.transferd_path
        agents.push(agent(:transferd, Aspera::Products::Transferd::APP_NAME, exe_versions(daemon, 'version').values.first)) if File.exist?(daemon)
      end
      {connect: Aspera::Products::Connect, desktop: Aspera::Products::Desktop}.each do |name, product_class|
        product = find_product(product_class)
        agents.push(agent(name, product_class::APP_NAME, product[:version] || app_version(product))) if product
      end
      AGENT_SERVERS.each do |name, plugin|
        server = servers.find { |s| s['plugin'].eql?(plugin.to_s) }
        agents.push(agent(name, server['product'], server['version'])) if server
      end
      agents.compact
    end

    # @return [Hash, nil] Agent entry, or nil without version
    def agent(name, product, version)
      if version.nil? || version.empty?
        Aspera::Log.log.warn("agent #{name}: version not found")
        return
      end
      Aspera::Log.log.info("agent #{name}: #{version}")
      {'agent' => name.to_s, 'product' => product, 'version' => version}
    end

    # @return [Hash, nil] First installed product of this class (with `ascp`)
    def find_product(product_class)
      Aspera::Products::Other.find(product_class.locations).first
    rescue StandardError => e
      Aspera::Log.log.warn(e.message)
      nil
    end

    # Versions printed by an executable: lines `<name> version <version>`
    # @return [Hash] name => version
    def exe_versions(path, arg)
      out, err, = Aspera::Environment.secure_execute(path, arg, mode: :capture, exception: false)
      "#{out}#{err}".lines.filter_map do |line|
        m = line.match(/\A(.+) version ([0-9][0-9.]*)/)
        [m[1], m[2].chomp('.')] if m
      end.to_h
    end

    # Version of a product: from its executable, else of the macOS application bundle
    # @return [String, nil]
    def app_version(product)
      version = exe_versions(product[:ascp_path], '-A').reject { |name, _| name.eql?('ascp') }.values.first
      return version unless version.nil?
      plist = File.join(product[:app_root], 'Contents', 'Info.plist')
      return unless File.exist?(plist)
      out, = Aspera::Environment.secure_execute('plutil', '-extract', 'CFBundleShortVersionString', 'raw', plist, mode: :capture, exception: false)
      out.strip.then { |v| v.empty? ? nil : v }
    end
  end
end
