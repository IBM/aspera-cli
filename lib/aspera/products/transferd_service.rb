# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'etc'
require 'fileutils'
require 'socket'
require 'aspera/assert'
require 'aspera/log'
require 'aspera/environment'
require 'aspera/yaml'
require 'aspera/secret/hider'
require 'aspera/schema/registry'
require 'aspera/schema/validator'

module Aspera
  module Products
    # Run the transfer daemon as a system service: configuration of `transferd.json` and systemd unit
    class TransferdService
      # Number of random bytes of a generated API key
      API_KEY_BYTES = 32
      DEFAULT_SERVICE_NAME = 'aspera-transferd'
      DEFAULT_USER = 'asperadaemon'
      DEFAULT_UNIT_DIR = '/etc/systemd/system'
      DEFAULT_AFTER = ['network.target'].freeze
      # Default location of the configuration file, also the default of the daemon
      CONFIG_FILE = '/etc/transferd/transferd.json'
      # Environment variables of the daemon that override the configuration file
      ENV_OVERRIDES = %w[TRANSFERD_ADDRESS TRANSFERD_PORT TRANSFERD_MGMT_ADDRESS TRANSFERD_MGMT_PORT].freeze
      # Mode of files that may contain a secret, and of the folder of the configuration
      FILE_MODE = 0o640
      DIR_MODE = 0o750
      # Seconds between two checks of the port
      WAIT_INTERVAL = 0.5
      # Keys of `transferd.json` that contain a secret
      SECRET_KEYS = %w[api_key].freeze
      # Name of the link to the version in use, in the layout `<prefix>/<version>`
      CURRENT_LINK = 'current'
      # Name of the folder of a version in the layout
      VERSION_PATTERN = /\A\d+(\.\d+)*\z/
      private_constant :API_KEY_BYTES, :FILE_MODE, :DIR_MODE, :WAIT_INTERVAL, :SECRET_KEYS, :VERSION_PATTERN

      # Access to the system: root folder, commands and network. Replaceable in tests.
      class Host
        # @return [String]  Root folder: all files are written below it (`/` for a real installation)
        # @return [Numeric] Seconds to wait for the daemon to listen
        # @return [Symbol]  Operating system, see `Environment::OS_*`
        # @return [Integer] Effective user id of the process
        attr_reader :root, :timeout, :os, :euid

        # @param root      [String]   Root folder of the file system
        # @param runner    [#call]    Receives the command words, returns `[output, success]`, default: run the command
        # @param listening [#call]    Receives address and port, returns `true` if a server listens, default: try to connect
        # @param timeout   [Numeric]  Seconds to wait for the daemon to listen
        # @param os        [Symbol]   Operating system, default: the current one
        # @param euid      [Integer]  Effective user id, default: the one of the process
        # @param systemctl [Boolean]  `true` if `systemctl` is available, default: look for it in `PATH`
        def initialize(root: '/', runner: nil, listening: nil, timeout: 30, os: nil, euid: nil, systemctl: nil)
          @root = root
          @os = os || Environment.instance.os
          @euid = euid || ::Process.euid
          @systemctl = systemctl.nil? ? ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, 'systemctl')) } : systemctl
          @runner = runner || lambda do |*cmd|
            out, err, status = Environment.secure_execute(*cmd, mode: :capture, exception: false)
            [out.to_s + err.to_s, status.success?]
          end
          @listening = listening || lambda do |address, port|
            Socket.tcp(address, port, connect_timeout: 1) { true }
          rescue SystemCallError, IOError
            false
          end
          @timeout = timeout
        end

        # @param path [String] Absolute path in the real file system
        # @return [String] Path below the root folder
        def path(path)
          File.join(@root, path)
        end

        # @param cmd [Array<String>] Command to run
        # @return [Array(String, Boolean)] Output and success
        def run(*cmd)
          @runner.call(*cmd)
        end

        # @return [Boolean] `true` if a server listens on this address and port
        def listening?(address, port)
          @listening.call(address, port)
        end

        # @return [Boolean] `true` if `systemctl` is available
        def systemctl?
          @systemctl
        end
      end

      class << self
        # Generate the text of the systemd unit file.
        # @param options [Hash] Service and execution options (from CONFIG or specific keys)
        # @return [String] systemd unit file content
        def unit(options = {})
          Aspera.assert_type(options, Hash) { 'options' }
          opts = json_hash(options)
          opts = opts['service'].merge(opts) if opts['service'].is_a?(Hash)
          executable = opts['executable'] || opts['exec'] || opts['bin'] ||
            (opts['sdk_folder'] ? File.join(opts['sdk_folder'], 'bin', 'transferd') : '/opt/aspera/transferd/bin/transferd')
          config_file = opts['config_file'] || opts['config'] || opts['config_path'] || opts['file'] || '/etc/transferd/transferd.json'
          user = opts['user'] || DEFAULT_USER
          group = opts['group']
          after = opts['after'] || DEFAULT_AFTER
          after = Array(after).join(' ')
          env = opts['environment'] || {}

          lines = [
            '[Unit]',
            "Description=#{opts['description'] || 'IBM Aspera Transfer Daemon'}",
            "After=#{after}",
            '',
            '[Service]',
            "Type=#{opts['type'] || 'simple'}",
            "User=#{user}"
          ]
          lines << "Group=#{group}" if group && !group.empty?
          lines << "ExecStart=#{executable} --config #{config_file}"
          lines << "Restart=#{opts['restart'] || 'always'}"
          env.keys.sort.each do |k|
            lines << %Q(Environment="#{k}=#{env[k]}")
          end
          lines.push(
            '',
            '[Install]',
            "WantedBy=#{opts['wanted_by'] || 'multi-user.target'}",
            ''
          )
          lines.join("\n")
        end

        # Build the content of `transferd.json`.
        # Order of precedence: values computed from `sdk_folder`, then `existing`, then `overrides`.
        # A key set to `nil` in `overrides` is removed.
        # @param existing   [Hash, nil] Content of the existing configuration file, `nil` or empty if none
        # @param overrides  [Hash]      Values given by the user (section `config` of the user parameter)
        # @param sdk_folder [String]    Folder of the SDK, used for `fasp_runtime`
        # @param file       [String,nil] Path of the existing file, for error messages
        # @return [Hash] Validated configuration, with String keys
        # @raise [ParameterError] if the result does not conform to the schema of the daemon
        def config(existing, overrides, sdk_folder, file: nil)
          Aspera.assert_type(existing, Hash, NilClass) { 'existing' }
          Aspera.assert_type(overrides, Hash) { 'overrides' }
          Aspera.assert_type(sdk_folder, String) { 'sdk_folder' }
          existing = json_hash(existing || {})
          computed = {
            'fasp_runtime' => {
              'use_embedded' => false,
              'user_defined' => {'bin' => sdk_folder, 'etc' => sdk_folder}
            }
          }
          result = merge(merge(computed, existing), json_hash(overrides))
          auth = result['authentication']
          auth['api_key'] = SecureRandom.hex(API_KEY_BYTES) if auth.is_a?(Hash) && auth['enabled'].eql?(true) && !auth.key?('api_key')
          errors = validate(result, existing, file)
          Aspera.assert(errors.empty?, type: ParameterError) { "Invalid transferd configuration:\n#{errors.join("\n")}" }
          return result
        end

        # Layout of versions side by side: `<prefix>/<version>` folders and the link `<prefix>/current`.
        # It is used when the SDK folder is named `current`. The paths in the unit and in `transferd.json` go through the link,
        # so that switching the link and restarting the service is enough to change the version.
        # @param sdk_folder [String] Folder of the SDK
        # @return [Boolean] `true` if the layout is used
        def layout?(sdk_folder)
          File.basename(sdk_folder).eql?(CURRENT_LINK)
        end

        # @param sdk_folder [String] Folder of the SDK
        # @return [String] Folder of the version in use if the layout is used, else `sdk_folder` as is
        def resolve(sdk_folder)
          layout?(sdk_folder) && File.symlink?(sdk_folder) ? File.realpath(sdk_folder) : sdk_folder
        end

        # @param sdk_folder [String] Link `current` of the layout
        # @return [Array<Hash>] Installed versions, oldest first: `version`, `folder`, `current`
        def versions(sdk_folder)
          assert_layout(sdk_folder)
          prefix = File.dirname(sdk_folder)
          current = link_target(sdk_folder)
          names = Dir.exist?(prefix) ? Dir.children(prefix) : []
          return names
              .select { |name| name.match?(VERSION_PATTERN) && File.exist?(executable(File.join(prefix, name))) }
              .sort_by { |name| Gem::Version.new(name) }
              .map { |name| {'version' => name, 'folder' => File.join(prefix, name), 'current' => name.eql?(current)} }
        end

        # Switch the link `current` to an installed version and restart the service.
        # If the restart fails, the link is set back to the previous version and the service is restarted again.
        # @param user_config [Hash]    `CONFIG`
        # @param sdk_folder  [String]  Link `current` of the layout
        # @param version     [String]  Installed version
        # @return [Array<String>] Actions done, or to do with `dry_run`; empty if the version is already in use
        def use(user_config, sdk_folder, version, host: Host.new, dry_run: false)
          assert_layout(sdk_folder)
          folder = version_folder(sdk_folder, version)
          Aspera.assert(File.exist?(executable(folder)), type: ParameterError) { "Version #{version} is not installed in #{folder}" }
          previous = link_target(sdk_folder)
          return [] if previous.eql?(version)
          opts = service_options(user_config)
          steps = [["link #{sdk_folder} to #{version}", -> { switch_link(sdk_folder, version) }]]
          if File.exist?(unit_path(host, opts))
            config_file = host.path(CONFIG_FILE)
            conf = File.exist?(config_file) ? read_config(config_file) : {}
            steps << ["restart #{opts['name']}", -> { systemctl(host, 'restart', opts['name']) }]
            steps.concat(wait_steps(host, opts, conf))
          end
          return with_rollback(sdk_folder, previous, opts, host) { run_steps(steps, dry_run) }
        end

        # Install the SDK if not present, then configure and start the service.
        # With the layout, the SDK is installed in `<prefix>/<version>`, the link `current` is set to it, and
        # it is set back to the previous version if the service cannot be started.
        # @param user_config [Hash]    `CONFIG`: sections `service` and `config`
        # @param sdk_folder  [String]  Folder of the SDK, or link `current` of the layout
        # @param host        [Host]    Access to the system
        # @param dry_run     [Boolean] `true`: change nothing, only return the actions
        # @param install_sdk [#call]   Installs the SDK, called if `transferd` is not there.
        #                              With the layout it receives the folder of the version, else no argument.
        # @param version     [String]  Version to install and use, mandatory with the layout, else ignored
        # @return [Array<String>] Actions done, or to do with `dry_run`
        def install(user_config, sdk_folder, host: Host.new, dry_run: false, install_sdk: nil, version: nil)
          steps = []
          previous = nil
          if layout?(sdk_folder)
            folder = version_folder(sdk_folder, version)
            previous = link_target(sdk_folder)
            unless File.exist?(executable(folder))
              Aspera.assert(!install_sdk.nil?, type: ParameterError) { "SDK is not installed in #{folder}" }
              steps << ["install the SDK in #{folder}", -> { install_sdk.call(folder) }]
            end
            steps << ["link #{sdk_folder} to #{version}", -> { switch_link(sdk_folder, version) }] unless previous.eql?(version)
          elsif !File.exist?(executable(sdk_folder))
            Aspera.assert(!install_sdk.nil?, type: ParameterError) { "SDK is not installed in #{sdk_folder}" }
            steps << ["install the SDK in #{sdk_folder}", install_sdk]
          end
          steps.concat(configure_steps(user_config, sdk_folder, host, dry_run))
          return run_steps(steps, dry_run) unless layout?(sdk_folder)
          with_rollback(sdk_folder, previous, service_options(user_config), host) { run_steps(steps, dry_run) }
        end

        # Merge `CONFIG` in the configuration file, write the unit, then (re)start the service.
        # @return [Array<String>] Actions done, or to do with `dry_run`
        def configure(user_config, sdk_folder, host: Host.new, dry_run: false)
          run_steps(configure_steps(user_config, sdk_folder, host, dry_run), dry_run)
        end

        # State of the service. The API key is never returned.
        # @return [Hash] Version, state of the service, endpoint, and whether it listens
        def status(user_config, sdk_folder, host: Host.new)
          opts = service_options(user_config)
          unit_file = host.path(File.join(opts['unit_dir'], "#{opts['name']}.service"))
          config_file = host.path(CONFIG_FILE)
          # only booleans and the endpoint are read: the API key is never copied in the result
          config = File.exist?(config_file) ? read_config(config_file) : {}
          env = unit_file_environment(unit_file)
          address = env['TRANSFERD_ADDRESS'] || config['address'] || '127.0.0.1'
          port = (env['TRANSFERD_PORT'] || config['port']).to_i
          version = File.exist?(executable(sdk_folder)) ? host.run(executable(sdk_folder), 'version').first : ''
          return {
            'service'        => opts['name'],
            'sdk_folder'     => resolve(sdk_folder),
            'installed'      => File.exist?(unit_file),
            'version'        => version[/\d+\.\d+\.\d+/],
            'enabled'        => host.run('systemctl', 'is-enabled', opts['name']).first.strip,
            'active'         => host.run('systemctl', 'is-active', opts['name']).first.strip,
            'config_file'    => CONFIG_FILE,
            'address'        => address,
            'port'           => port,
            'listening'      => port.positive? && host.listening?(connect_address(address), port),
            'authentication' => config.dig('authentication', 'enabled').eql?(true),
            'tls'            => config.dig('tls', 'enabled').eql?(true),
            'environment'    => env
          }
        end

        # Stop and remove the service.
        # @param purge [Boolean] Also remove the configuration file and the log folder
        # @return [Array<String>] Actions done, or to do with `dry_run`
        def uninstall(user_config, host: Host.new, dry_run: false, purge: false)
          opts = service_options(user_config)
          unit_file = host.path(File.join(opts['unit_dir'], "#{opts['name']}.service"))
          steps = []
          if File.exist?(unit_file)
            steps << ["stop and disable #{opts['name']}", -> { systemctl(host, 'disable', '--now', opts['name'], check: false) }]
            steps << ["remove #{unit_file}", -> { File.delete(unit_file) }]
            steps << ['reload systemd', -> { systemctl(host, 'daemon-reload') }]
          end
          steps.concat(purge_steps(host)) if purge
          run_steps(steps, dry_run)
        end

        # @param user_config [Hash] `CONFIG`
        # @return [Hash] Validated `service` section with defaults, plus `config` section as `overrides`
        def service_options(user_config)
          Aspera.assert_type(user_config, Hash) { 'CONFIG' }
          conf = json_hash(user_config)
          service = conf['service'] || {}
          errors = Schema::Validator.instance.errors(service, Schema::Registry::SERVICE_OPTIONS)
          Aspera.assert(errors.empty?, type: ParameterError) { "Invalid service parameters:\n#{errors.join("\n")}" }
          return {
            'name'        => DEFAULT_SERVICE_NAME,
            'user'        => DEFAULT_USER,
            'unit_dir'    => DEFAULT_UNIT_DIR,
            'after'       => DEFAULT_AFTER,
            'environment' => {}
          }.merge(service).merge('overrides' => conf['config'] || {})
        end

        # Refuse to run on a host that cannot run the service: systemd on Linux, as root.
        # Not checked with `dry_run`: the actions are only shown, so that it works everywhere.
        # @param host    [Host]    Access to the system
        # @param dry_run [Boolean] `true`: change nothing, no check
        # @raise [Error] if the host is not supported or the user is not root
        def assert_supported(host, dry_run: false)
          return if dry_run
          Aspera.assert(host.os.eql?(Environment::OS_LINUX), type: Error) { "The service requires Linux with systemd, this is: #{host.os}" }
          Aspera.assert(host.systemctl?, type: Error) { 'The service requires systemd: command systemctl not found' }
          Aspera.assert(host.euid.zero?, type: Error) { 'The service must be managed as root (use sudo), or use --dry-run=yes to only see the actions' }
        end

        # @return [String] Version of transferd that the configuration schema matches
        def schema_version
          schema_hash['$comment'].to_s[/transferd (\d+\.\d+\.\d+)/, 1]
        end

        # Warn (never fail) if the SDK is not the version that the configuration schema matches.
        # @param sdk_folder [String] Folder of the SDK, or link `current` of the layout
        # @param host       [Host]   Access to the system
        # @return [String, nil] The warning, or `nil` if versions are the same or the version is unknown
        def check_version(sdk_folder, host: Host.new)
          exe = executable(sdk_folder)
          return unless File.exist?(exe)
          sdk_version = host.run(exe, 'version').first[/\d+\.\d+\.\d+/]
          return if sdk_version.nil? || sdk_version.eql?(schema_version)
          relation = Gem::Version.new(sdk_version) > Gem::Version.new(schema_version) ? 'newer' : 'older'
          message = "transferd #{sdk_version} is #{relation} than the version of the configuration schema (#{schema_version}): some settings may be unknown or refused"
          Log.log.warn(message)
          return message
        end

        private

        def assert_layout(sdk_folder)
          Aspera.assert(layout?(sdk_folder), type: ParameterError) { "The SDK folder must be named #{CURRENT_LINK} to use versions: #{sdk_folder}" }
        end

        # @return [String] Folder of a version, next to the link `current`
        def version_folder(sdk_folder, version)
          Aspera.assert(version.is_a?(String) && version.match?(VERSION_PATTERN), type: ParameterError) { "Invalid version: #{version.inspect}" }
          File.join(File.dirname(sdk_folder), version)
        end

        # @return [String, nil] Name of the folder the link points to, or `nil` if there is no link
        def link_target(link)
          File.symlink?(link) ? File.basename(File.readlink(link)) : nil
        end

        # Atomically set the link to a version (relative target)
        def switch_link(link, version)
          Aspera.assert(File.symlink?(link) || !File.exist?(link), type: Error) { "#{link} exists and is not a link" }
          temporary = "#{link}.new"
          FileUtils.rm_f(temporary)
          File.symlink(version, temporary)
          File.rename(temporary, link)
        end

        # @return [String] Path of the unit file
        def unit_path(host, opts)
          host.path(File.join(opts['unit_dir'], "#{opts['name']}.service"))
        end

        # Run the block, and if it fails, set back the link to the previous version and restart the service.
        def with_rollback(sdk_folder, previous, opts, host)
          yield
        rescue StandardError
          Log.log.error { "Failed, going back to version #{previous || 'none'}" }
          if previous.nil?
            File.delete(sdk_folder) if File.symlink?(sdk_folder)
          else
            switch_link(sdk_folder, previous)
            systemctl(host, 'restart', opts['name'], check: false) if File.exist?(unit_path(host, opts))
          end
          raise
        end

        # @return [String] Path of `transferd` in the SDK
        def executable(sdk_folder)
          File.join(sdk_folder, 'transferd')
        end

        # @return [Hash] Content of the configuration file (JSON or YAML)
        def read_config(file)
          Yaml.safe_load(File.read(file)) || {}
        end

        # @return [Hash] Copy of the configuration without secret
        def hidden(config)
          Secret::Hider.instance.hidden_copy(config)
        end

        # @return [Hash] Environment variables of the daemon found in the unit file
        def unit_file_environment(unit_file)
          return {} unless File.exist?(unit_file)
          File.readlines(unit_file, chomp: true).filter_map do |line|
            name, value = line.match(/^Environment="([A-Z_]+)=(.*)"$/)&.captures
            [name, value] if ENV_OVERRIDES.include?(name)
          end.to_h
        end

        # @return [String] Address to connect to, to reach a server that listens on `address`
        def connect_address(address)
          %w[0.0.0.0 ::].include?(address) ? '127.0.0.1' : address
        end

        # @param host [Host]
        # @param args [Array<String>] Arguments of `systemctl`
        # @param check [Boolean] Fail if the command fails
        # @return [String] Output
        def systemctl(host, *args, check: true)
          out, success = host.run('systemctl', *args)
          Aspera.assert(success || !check, type: Error) { "systemctl #{args.join(' ')} failed: #{out}" }
          out
        end

        # @param steps   [Array<Array(String, #call)>] Description and action
        # @param dry_run [Boolean] `true`: do not call the actions
        # @return [Array<String>] Descriptions
        def run_steps(steps, dry_run)
          steps.each do |description, action|
            Log.log.info(description)
            action.call unless dry_run
          end
          steps.map(&:first)
        end

        # @return [Array<Array(String, #call)>] Steps to write the files and (re)start the service
        def configure_steps(user_config, sdk_folder, host, dry_run)
          opts = service_options(user_config)
          user = opts['user']
          pw = account(user)
          steps = []
          if pw.nil?
            message = "Account #{user} does not exist, create it with: useradd --system --no-create-home --shell /usr/sbin/nologin #{user}"
            Aspera.assert(dry_run, type: ParameterError) { message }
            steps << [message, -> {}]
          end
          uid = pw&.uid
          gid = group_id(opts['group'], pw)
          config_file = host.path(CONFIG_FILE)
          conf = config(File.exist?(config_file) ? read_config(config_file) : nil, opts['overrides'], sdk_folder, file: config_file)
          Secret::Hider.instance.add_secret_keys(SECRET_KEYS)
          Secret::Hider.instance.add_secret_values(conf.dig('authentication', 'api_key'))
          unit_file = host.path(File.join(opts['unit_dir'], "#{opts['name']}.service"))
          unit_text = unit(
            executable:  executable(sdk_folder),
            config_file: CONFIG_FILE,
            user:        user,
            group:       opts['group'],
            after:       opts['after'],
            environment: opts['environment']
          )
          owner = "#{user}:#{opts['group'] || 'primary group'}"
          steps << ["create folder #{File.dirname(config_file)} (mode #{DIR_MODE.to_s(8)}, owner #{owner})",
                    -> { write_dir(File.dirname(config_file), DIR_MODE, uid, gid) }]
          log_directory = conf['log_directory']
          if log_directory.is_a?(String) && log_directory.start_with?('/')
            log_dir = host.path(log_directory)
            steps << ["create folder #{log_dir} (owner #{owner})", -> { write_dir(log_dir, DIR_MODE, uid, gid) }]
          end
          steps << ["write #{config_file} (mode #{FILE_MODE.to_s(8)}, owner #{owner}):\n#{JSON.pretty_generate(hidden(conf))}",
                    -> { write_file(config_file, "#{JSON.pretty_generate(conf)}\n", uid, gid) }]
          steps << ["write #{unit_file} (mode #{FILE_MODE.to_s(8)}):\n#{unit_text}", -> { write_file(unit_file, unit_text, nil, nil) }]
          steps << ['reload systemd', -> { systemctl(host, 'daemon-reload') }]
          steps << ["enable and restart #{opts['name']}", -> { %w[enable restart].each { |action| systemctl(host, action, opts['name']) } }]
          steps.concat(wait_steps(host, opts, conf))
          return steps
        end

        # @return [Array<Array(String, #call)>] Step to wait for the daemon, none if the port is dynamic
        def wait_steps(host, opts, conf)
          port = (opts['environment']['TRANSFERD_PORT'] || conf['port']).to_i
          return [] unless port.positive?
          address = connect_address(opts['environment']['TRANSFERD_ADDRESS'] || conf['address'] || '127.0.0.1')
          return [["wait for #{address}:#{port}", -> { wait_listening(host, address, port, opts['name']) }]]
        end

        # @return [Array<Array(String, #call)>] Steps to remove the configuration file and the log folder
        def purge_steps(host)
          config_file = host.path(CONFIG_FILE)
          steps = []
          log_directory = read_config(config_file)['log_directory'] if File.exist?(config_file)
          steps << ["remove #{host.path(log_directory)}", -> { FileUtils.rm_rf(host.path(log_directory)) }] if log_directory.is_a?(String) && log_directory.start_with?('/') && log_directory.length > 1
          steps << ["remove #{config_file}", -> { FileUtils.rm_f(config_file) }]
          steps << ["remove folder #{File.dirname(config_file)} if empty", -> { Dir.rmdir(File.dirname(config_file)) if Dir.empty?(File.dirname(config_file)) }]
          return steps
        end

        # @return [Etc::Passwd, nil] The account, or `nil` if it does not exist
        def account(user)
          Etc.getpwnam(user)
        rescue ArgumentError
          nil
        end

        # @return [Integer, nil] Id of the group, or primary group of the account
        def group_id(group, account)
          return account&.gid if group.nil?
          Etc.getgrnam(group).gid
        rescue ArgumentError
          raise ParameterError, "Group #{group} does not exist"
        end

        def write_dir(path, mode, uid, gid)
          FileUtils.mkdir_p(path)
          Environment.restrict_file_access(path, mode: mode)
          File.chown(uid, gid, path) if uid
        end

        def write_file(path, content, uid, gid)
          FileUtils.mkdir_p(File.dirname(path))
          Environment.write_file_restricted(path, force: true, mode: FILE_MODE) { content }
          File.chown(uid, gid, path) if uid
        end

        def wait_listening(host, address, port, name)
          deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + host.timeout
          until host.listening?(address, port)
            Aspera.assert(::Process.clock_gettime(::Process::CLOCK_MONOTONIC) < deadline, type: Error) do
              "Service #{name} does not listen on #{address}:#{port} after #{host.timeout} seconds, see: journalctl -u #{name}"
            end
            sleep(WAIT_INTERVAL)
          end
        end

        # @param value [Object] Value with Symbol or String keys
        # @return [Object] JSON view of value: String keys
        def json_hash(value)
          JSON.parse(JSON.generate(value))
        end

        # Deep merge, entries set to `nil` in `over` are removed
        # @param base [Hash] Initial values
        # @param over [Hash] Values to apply
        # @return [Hash] New Hash
        def merge(base, over)
          over.each_with_object(base.dup) do |(key, value), result|
            if value.nil?
              result.delete(key)
            elsif value.is_a?(Hash)
              result[key] = merge(result[key].is_a?(Hash) ? result[key] : {}, value)
            else
              result[key] = value
            end
          end
        end

        # @return [JSONSchemer::Schema] compiled schema of `transferd.json`
        def schema
          @schema ||=
            begin
              require 'json_schemer'
              JSONSchemer.schema(schema_hash)
            end
        end

        # @return [Hash] Schema of `transferd.json`
        def schema_hash
          # JSON is read with the YAML loader: it accepts the header comment added by `rake tools:openapi`
          @schema_hash ||= Yaml.safe_load(File.read(File.join(File.expand_path('../..', __dir__), Schema::Registry::LOCATIONS[:transferd])))
        end

        # @param config   [Hash]        Configuration to validate
        # @param existing [Hash]        Content of the existing file
        # @param file     [String, nil] Path of the existing file
        # @return [Array<String>] error messages, empty if valid
        def validate(config, existing, file)
          schema.validate(config).map do |error|
            # tell the user when the faulty value comes from a file that was not written by this call
            path = error['data_pointer'].to_s.split('/').drop(1)
            origin = file && in_hash?(existing, path) ? " (existing file: #{file})" : ''
            "#{error['error']}#{origin}"
          end
        end

        # @param hash [Hash]  Hash to look into
        # @param path [Array] Keys of nested Hashes
        # @return [Boolean] `true` if the path exists in hash
        def in_hash?(hash, path)
          return false if path.empty?
          path.reduce(hash) do |node, key|
            return false unless node.is_a?(Hash) && node.key?(key)
            node[key]
          end
          true
        end
      end
    end
  end
end
