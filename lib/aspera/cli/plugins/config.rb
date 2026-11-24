# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../completion_actions'
require_relative '../deprecation'
require_relative '../error'
require_relative '../gem_checker'
require_relative '../http'
require_relative '../info'
require_relative '../option/type'
require_relative '../parser'
require_relative '../preset_actions'
require_relative '../preset_manager'
require_relative '../result'
require_relative '../security'
require_relative '../special_values'
require_relative '../terminal_formatter'
require_relative '../vault_actions'
require_relative '../version'
require_relative '../wizard'
require_relative 'base'
require_relative 'factory'
require_relative '../../assert'
require_relative '../../bundle_registry'
require_relative '../../environment'
require_relative '../../hash_ext'
require_relative '../../log'
require_relative '../../oauth/client/factory'
require_relative '../../oauth/client/jwt'
require_relative '../../prompt'
require_relative '../../rest'
require_relative '../../schema/registry'
require_relative '../../string_ext'
require_relative '../../sealed_hash'
require_relative '../../web_auth/relay'
require 'openssl'

module Aspera
  module Cli
    module Plugins
      # Manage the CLI config file
      class Config < Base
        include VaultActions
        include GemChecker
        include PresetActions
        include CompletionActions

        class << self
          # Folder containing plugins in the gem's main folder
          def gem_plugins_folder
            File.dirname(File.expand_path(__FILE__))
          end

          # @return [String] main folder where code is, i.e. .../lib
          # Go up as many times as englobing modules (not counting class, as it is a file)
          def gem_src_root
            # Module.nesting[2] is Cli::Plugins
            File.expand_path(Module.nesting[2].to_s.gsub('::', '/').gsub(%r{[^/]+}, '..'), gem_plugins_folder)
          end

          # @return [String] product family folder (~/.aspera)
          def module_family_folder
            user_home_folder = Dir.home
            Aspera.assert(Dir.exist?(user_home_folder), type: Cli::Error) { "Home folder does not exist: #{user_home_folder}. Check your user environment." }
            return File.join(user_home_folder, ASPERA_HOME_FOLDER_NAME)
          end

          # @return [String] Product config folder (~/.aspera/<name>)
          def default_app_main_folder(app_name:)
            Aspera.assert_type(app_name, String)
            Aspera.assert(!app_name.empty?, 'app_name must not be empty')
            return File.join(module_family_folder, app_name)
          end
        end

        DEFAULT_CHECK_NEW_VERSION_DAYS = 7
        # Last released version with `config transferd`, `config ascp install` and `config transfer` not deprecated
        DEPRECATED_LAST = '4.28.0'
        private_constant :DEFAULT_CHECK_NEW_VERSION_DAYS

        def initialize(**_)
          super
          @sdk_default_location = false
          @wizard = Wizard.new(self, context.main_folder)
          # Values set through `on_set` callbacks are used below (sdk_folder)
          options.parse_options!
          # Method of the module `AscpActions` mounted by bundle `transfer_agents`: config still works if this mount failed (see `include_mounts`)
          set_sdk_dir if respond_to?(:set_sdk_dir)
        end

        command :preset, description: 'Manage configuration presets'
        commands_under :preset do
          command :list,     description: 'List all presets', action: ->(**) { Result::ValueList.new(presets.config_presets.keys, name: 'name') }
          command :overview, description: 'Show all options from all presets'
          command :lookup,   description: 'Find preset matching URL and username',
            arguments: [{name: :criteria, type: Hash, schema: Schema::Registry::PRESET_LOOKUP_CRITERIA}]
          command :secure,   description: 'Move secrets to vault',
            arguments: [{name: :config_name, mandatory: false, complete: :preset}]
          command :show,       description: 'Show a preset',
            arguments: [{name: :name, type: :identifier, complete: :preset}]
          command :delete,     description: 'Delete a preset',
            arguments: [{name: :name, type: :identifier, complete: :preset}]
          command :get,        description: 'Show a single parameter of a preset',
            arguments: [{name: :name, type: :identifier, complete: :preset}, {name: :param_name, complete: :preset_parameter}]
          command :unset,      description: "Remove a parameter from a preset (#{Deprecation.new(last: DEPRECATED_LAST, message: 'use set <name> <param> @none:')})",
            arguments: [{name: :name, type: :identifier, complete: :preset}, {name: :param_name, complete: :preset_parameter}]
          command :set, description: 'Merge into presets: <Hash> of presets, <name> <Hash>, or <name> <param> <value> (@none: removes)',
            arguments: [{name: :name, type: [String, Hash], complete: :preset},
                        {name: :param_name, type: [String, Hash], mandatory: false, omit_absent: true, complete: :preset_parameter},
                        {name: :param_value, type: nil, mandatory: false, omit_absent: true, evaluate: :smart}]
          command :initialize, description: "Initialize a preset with a value (#{Deprecation.new(last: DEPRECATED_LAST, message: 'use delete, then set <name> <Hash>')})",
            arguments: [{name: :name, type: :identifier, complete: :preset}, {name: :preset, type: Hash}]
          command :update,     description: "Update a preset with option values (#{Deprecation.new(last: DEPRECATED_LAST, message: 'use set <name> <Hash>')})",
            arguments: [{name: :name, type: :identifier, complete: :preset}]
          command :ask,        description: 'Ask for option values interactively',
            arguments: [{name: :name, type: :identifier, complete: :preset},
                        {name: :option_names, multiple: true, interactive: true}]
        end
        command(
          :open, description: 'Open the configuration file in the default editor',
          action: lambda do |**|
            Environment.instance.open_editor(context.presets.config_file.to_s)
            Result::Nothing.new
          end
        )
        command :documentation, description: 'Open the documentation in the default browser',
          arguments: [
            {name: :location, type: Symbol, mandatory: false, default: :github, allowed: %i[github local toc]},
            {name: :section, mandatory: false}
          ]
        command(
          :skill, description: 'Display the agent skill: how an AI drives IBM Aspera products with ascli (same as llms.txt)',
          action: lambda do |**|
            skill_file = File.join(self.class.gem_src_root, '..', 'skills', 'ascli', 'SKILL.md')
            Aspera.assert(File.exist?(skill_file), type: Cli::Error) { "Agent skill not found: #{skill_file}" }
            Result::Text.new(File.read(skill_file))
          end
        )
        command(
          :genkey, description: 'Generate a new RSA private key',
          arguments: [
            {name: :private_key_path, complete: :file},
            {name: :private_key_length, type: Integer, mandatory: false, default: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH}
          ],
          action: lambda do |private_key_path:, private_key_length: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH, **|
            OAuth::Jwt.generate_rsa_private_key(path: private_key_path, length: private_key_length)
            Result::Status.new("Generated #{private_key_length} bit RSA key: #{private_key_path}")
          end
        )
        command :pubkey, description: 'Show the public key of an RSA private key',
          arguments: [{name: :private_key_pem}],
          action: ->(private_key_pem:, **) { Result::Text.new(OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s) }
        command :remote_certificate, description: 'Retrieve the certificate chain of a remote HTTPS server'
        command :echo, read_only: true, description: 'Show the value of a given argument',
          arguments: [{name: :value, type: nil}],
          action: ->(value:, **) { Result.auto(value) }
        command :download, description: 'Download a file from a URL',
          arguments: [
            {name: :file_url},
            {name: :file_dest, mandatory: false, complete: :file}
          ]
        command :web_login, description: 'Web login for ascli on another host (option ui.web_auth=paste): open the login page, show a code to paste there',
          security: :low,
          arguments: [{name: :code}]
        command :tokens, description: 'Manage OAuth tokens'
        command :plugins, description: 'Manage CLI plugins'
        command(
          :detect, description: 'Detect the Aspera product from a URL (interactive)',
          arguments: [{name: :params, type: Hash, mandatory: false, default: {}, schema: Schema::Registry::DETECT_OPTIONS}],
          action: lambda do |params:, **|
            Result::ObjectList.new(@wizard.identify_plugins_for_url(url: ask_url(params), plugin_name: params['plugin']).freeze)
          end
        )
        command(
          :wizard, description: 'Run the setup wizard for an Aspera product (interactive)',
          arguments: [{name: :params, type: Hash, mandatory: false, default: {}, schema: Schema::Registry::WIZARD_OPTIONS}],
          action: lambda do |params:, **|
            apps = @wizard.identify_plugins_for_url(url: ask_url(params), plugin_name: params['plugin']).freeze
            # Options of the plugin (`--username`, `--password`, `--private-key`, ...) are read from the command line.
            # The product wizard prompts for missing mandatory options (username, password, ...)
            options.with_interactive do
              @wizard.find(
                apps,
                preset_name: params['preset'] || '',
                override:    params.fetch('override', false),
                default:     params.fetch('default', true)
              )
            end
          end
        )
        command :coffee, description: 'Show a coffee image', action: ->(**) { Result::Image.new(COFFEE_IMAGE_URL) }
        command :image, description: 'Show an image',
          arguments: [{name: :image_uri, type: nil}],
          action: ->(image_uri:, **) { Result::Image.new(image_uri) }
        command :gem, description: 'Show gem information'
        command :folder, description: 'Show the configuration folder path', action: ->(**) { Result::Text.new(context.main_folder) }
        command :file, description: 'Show the configuration file path', action: ->(**) { Result::Text.new(context.presets.config_file) }
        command(
          :email_test, description: 'Send a test email',
          action: lambda do |**|
            context.mailer.send_email_template(email_template_default: EMAIL_TEST_TEMPLATE)
            Result::Nothing.new
          end
        )
        command :smtp_settings, description: 'Show the current SMTP settings', action: ->(**) { Result::SingleObject.new(context.mailer.email_settings) }
        command(
          :proxy_check, description: 'Check the proxy returned by the PAC script for a given URL',
          arguments: [{name: :server_url}],
          action: lambda do |server_url:, **|
            Aspera.assert(!context.pac_executor.nil?, type: Cli::BadArgument) { 'No PAC script configured, use --fpac' }
            Result::ValueList.new(context.pac_executor.get_proxies(server_url), name: 'proxy')
          end
        )
        command :check_update, description: 'Check if a newer version of the gem is available', action: ->(**) { Result::SingleObject.new(check_gem_version) }
        command :initdemo, description: 'Initialize the demo server preset'
        command :vault, description: 'Manage secrets in the vault'
        commands_under :vault do
          command :info,     description: 'Show vault information',
            action: ->(**) { Result::SingleObject.new(vault_required.info) }
          command :stores,   description: 'List stores of option vault, with their type and whether it is the default one, without parameters',
            action: ->(**) { Result::ObjectList.new(context.vault.stores) }
          command :ids,      description: 'List secret labels in the vault',
            action: ->(**) { Result::ObjectList.new(vault_required.ids) }
          command :list,     description: 'List all secrets with full details',
            action: ->(**) { Result::ObjectList.new(vault_required.all) }
          command :overview, description: 'List labels of all secrets with their field names, without values',
            action: ->(**) { Result::ObjectList.new(vault_required.ids.map { |i| {'label' => i[:label], 'fields' => context.vault.fields(i[:label])} }) }
          command(
            :field,    description: 'List field names of a secret by label, without values',
            arguments: [{name: :label}],
            action: ->(label:, **) { Result::ValueList.new(context.vault.fields(label), name: 'field') }
          )
          command(
            :show,     description: 'Show a secret by label (or id)',
            arguments: [{name: :label}, {name: :id, mandatory: false, default: nil}],
            action: lambda do |label:, id: nil, **|
              v = vault_required
              kwargs = id && v.method(:get).parameters.any? { |_t, n| n == :id } ? {id: id} : {}
              Result::SingleObject.new(v.get(label: label, **kwargs))
            end
          )
          command(
            :create,   description: 'Add a new secret to the vault',
            arguments: [{name: :secret, type: Hash, schema: Schema::Registry::VAULT_SECRET}],
            action: lambda do |secret:, **|
              vault_required.set(secret.symbolize_keys)
              Result::Status.new('Secret added')
            end
          )
          command :delete, description: 'Delete a secret by label (or id)',
            arguments: [{name: :label}, {name: :id, mandatory: false, default: nil}]
          command(
            :password, description: 'Set a new password for the vault',
            arguments: [{name: :new_password}],
            action: lambda do |new_password:, **|
              Aspera.assert(vault_required.respond_to?(:change_password), 'Vault does not support password change', type: Cli::BadArgument)
              vault_required.change_password(new_password)
              Result::Status.new('Vault password updated')
            end
          )
          command :import, description: 'Import secrets from a JSON array (supports --bulk)',
            arguments: [{name: :secrets, type: Array, schema: {type: 'array', items: {'$ref' => Schema::Registry::VAULT_SECRET}}}]
          command :check, description: 'Check that a reference to a store of option vault can be read, without its value',
            arguments: [{name: :reference, evaluate: :none}]
        end
        command :commands, description: 'List all available commands, of all plugins or only the given one, optionally under a command path',
          arguments: [{name: :plugin_name, mandatory: false, default: nil},
                      {name: :command_path, multiple: true, mandatory: false, default: nil}]
        command :options, description: 'List all options available for a plugin',
          arguments: [{name: :plugin_name}]
        command :test, description: 'Internal test commands'
        command :platform, description: 'Show the current platform/architecture', action: ->(**) { Result::Text.new(Environment.instance.architecture) }
        command :completion, description: 'Shell completion: activation scripts and next words'

        # remote_certificate sub-commands
        commands_under :remote_certificate do
          command(
            :chain, description: 'Show the full certificate chain as PEM',
            arguments: [{name: :remote_url}],
            action: lambda do |remote_url:, **|
              remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
              Aspera.assert(remote_chain&.first, type: Cli::Error) { "No certificate found for #{remote_url}" }
              Result::Text.new(remote_chain.map(&:to_pem).join("\n"))
            end
          )
          command(
            :only, description: 'Show only the server certificate as PEM',
            arguments: [{name: :remote_url}],
            action: lambda do |remote_url:, **|
              remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
              Aspera.assert(remote_chain&.first, type: Cli::Error) { "No certificate found for #{remote_url}" }
              Result::Text.new(remote_chain.first.to_pem)
            end
          )
          command(
            :name, description: 'Show the CN of the server certificate',
            arguments: [{name: :remote_url}],
            action: lambda do |remote_url:, **|
              remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
              Aspera.assert(remote_chain&.first, type: Cli::Error) { "No certificate found for #{remote_url}" }
              Result::Text.new(remote_chain.first.subject.to_a.find { |name, _, _| name == 'CN' }[1])
            end
          )
        end

        # tokens sub-commands
        commands_under :tokens do
          command(
            :flush, description: 'Delete all cached OAuth tokens',
            action: lambda do |**|
              Result::ValueList.new(OAuth::Factory.instance.flush_tokens, name: 'file')
            end
          )
          command(
            :list, description: 'List all cached OAuth tokens',
            action: lambda do |**|
              Result::ObjectList.new(OAuth::Factory.instance.persisted_tokens)
            end
          )
          command :show, description: 'Show details of a cached OAuth token',
            arguments: [{name: :token_id, type: :identifier}]
        end

        # plugins sub-commands
        commands_under :plugins do
          command :list, description: 'List all plugins, with their status'
          command :show, description: 'Show the details of a plugin: source, form, capabilities, dependencies, gems, security level',
            arguments: [{name: :name}]
          command :create, description: 'Create a new plugin skeleton file', security: :low,
            arguments: [
              {name: :name},
              {name: :folder, mandatory: false, complete: :folder}
            ]
        end

        # Commands of the modules that bundles mount on config (manifest `mounts`), here: bundle `transfer_agents` adds `ascp`, `agents`, `transfer`, and `sync` (before `gem`),
        # then bundle `transferd` adds the deprecated `transferd`
        include_mounts

        # Options of config come after the options of the mounted modules (`sql`, `ascp_logs`): same order as when config included them.
        # Mounted modules may place theirs before an option of config (`option ..., before:`).
        option :preset,             description: 'Load the named option preset from current config file',             short: 'P', on_set: :load_preset, complete: :preset
        option :version_check_days, description: 'Period in days to check new version (zero to disable)',             allowed: Option::Type::INTEGER, default: DEFAULT_CHECK_NEW_VERSION_DAYS
        option :plugin_folder,      description: "Folders where to find additional plugins (#{SpecialValues::DEF}: folder plugins of the configuration folder)", allowed: Option::Type::STRING_ARRAY, default: [SpecialValues::DEF], complete: :folder, security: :low
        option :smtp,               schema: Schema::Registry::SMTP_OPTIONS
        option :notify_to,          description: 'Email: Recipient for notification of transfers'
        option :notify_template,    description: 'Email: ERB template for notification of transfers', security: :low
        option :cache_tokens,       description: 'Save and reuse OAuth tokens', allowed: Option::Type::BOOLEAN, default: true
        option :expand_mounts,      description: 'Commands: list commands of sub-trees provided by another plugin', allowed: Option::Type::BOOLEAN, default: false
        option :no_default,         description: 'Do not load default configuration for plugin', allowed: Option::Type::NONE, short: 'N', on_set: -> { presets.use_plugin_defaults = false }
        # `on_set` callbacks of HTTP options are methods of `http_config`
        use_options Http, target: -> { http_config }

        # gem sub-commands
        commands_under :gem do
          command :path,    description: 'Show the gem source root path',    action: ->(**) { Result::Text.new(self.class.gem_src_root) }
          command :version, description: 'Show the gem version',             action: ->(**) { Result::Text.new(Cli::VERSION) }
          command :name,    description: 'Show the gem name',                action: ->(**) { Result::Text.new(Info::GEM_NAME) }
        end

        # test sub-commands
        commands_under :test do
          command(
            :throw, description: 'Raise an exception (for testing)',
            arguments: [
              {name: :exception_class_name},
              {name: :exception_text}
            ],
            action: lambda do |exception_class_name:, exception_text:, **|
              type = Object.const_get(exception_class_name)
              Aspera.assert(type <= Exception) { "#{type} is not an exception: #{type.class}" }
              raise type, exception_text
            end
          )
          command :web, description: 'Test web browser interaction', action: ->(**) {}
        end

        # completion sub-commands
        commands_under :completion do
          command :words, description: 'List words that can follow the given words',
            arguments: [{name: :words, multiple: true, mandatory: false, evaluate: :none}]
          command :candidates, description: 'Complete the last word, with descriptions and a directive for the shell (used by completion scripts)',
            arguments: [{name: :words, multiple: true, mandatory: false, evaluate: :none}]
          COMPLETION_SHELLS.each_key do |shell|
            command shell, description: "Generate #{shell} completion script, to evaluate in shell",
              action: ->(**) { completion_script(shell) }
          end
        end

        attr_reader :gem_url

        # Add the folders of option `plugin_folder` to the plugin lookup: `DEF` is the folder `plugins` of the configuration folder.
        # Called once options are final, before plugins are looked up: the last folder has priority.
        # @return [nil]
        def add_plugin_lookup_folders
          home_plugins = File.join(context.main_folder, ASPERA_PLUGINS_FOLDERNAME)
          folders = options.get_option(:plugin_folder)
          # Before 4.30, this folder was always used: plugins there would silently stop working
          unused_home = !folders.include?(SpecialValues::DEF) && Dir.glob(["*#{Environment::RB_EXT}", "*/#{BundleRegistry::MANIFEST}"], base: home_plugins).any?
          Log.log.warn { "Plugins of #{home_plugins} are not used: add #{SpecialValues::DEF} to option plugin_folder" } if unused_home
          folders.each { |f| Plugins::Factory.instance.add_lookup_folder(f.eql?(SpecialValues::DEF) ? home_plugins : f, security: :low) }
          nil
        end

        # `on_set` callback of option `preset`
        # @param value [String, Hash] preset name, or set of option values
        def load_preset(value)
          case value
          when Hash
            options.add_option_preset(value, 'set')
          when String
            options.add_option_preset(presets.by_name(value), 'set_by_name')
          else
            raise BadArgument, 'Preset definition must be a String for preset name, or Hash for set of values'
          end
        end

        # DSL handlers - one method per leaf command

        # URL of the application to detect or configure: from `params`, else asked to the user
        # @param params [Hash] parameters of `detect` or `wizard`
        # @return [String] URL
        def ask_url(params)
          params['url'] || options.with_interactive { options.get_interactive('url') }
        end

        def action_documentation(location: :github, section: nil, **)
          case location
          when :github
            section = "##{section}" unless section.nil?
            Environment.instance.open_uri("#{Info::DOC_URL}#{section}")
            return Result::Nothing.new
          when :toc, :local
            require_relative '../../markdown'
            local_doc = File.join(self.class.gem_src_root, '..', 'docs', 'README.md')
            Aspera.assert(File.exist?(local_doc), type: Cli::Error) { "Local documentation not found: #{local_doc}" }
            content = File.read(local_doc)
            if location == :toc
              entries = Markdown.toc(content)
              return Result::ObjectList.new(entries, fields: %w[level title anchor])
            end
            # :local
            if section
              text = Markdown.extract_section(content, section)
              Aspera.assert(!text.nil?, type: Cli::Error) { "Section not found: #{section}" }
              return Result::Text.new(text)
            end
            if Environment.instance.url_method.eql?(:graphical)
              Environment.instance.open_uri("file://#{local_doc}")
              return Result::Nothing.new
            end
            return Result::Text.new(content)
          end
        end

        # Web login for `ascli` that runs on another host, started with `--ui.web_auth=paste`.
        # The code comes from another host, or from a message: the host of the login page is confirmed by the user the first time.
        # @param code [String] Code of type login, given by the remote `ascli`
        def action_web_login(code:, **)
          data = SealedHash.unseal(code, base_key: Cli::Info::CMD_NAME)
          raise BadArgument, 'This code is for ascli that waits for the login: run this command with the code that ascli gives' unless data.is_a?(Hash) && data.key?('login_url')
          login = WebAuth::Relay.parse(data)
          confirm_web_login_host(login.host)
          Log.log.debug { "Redirection to #{login.redirect_uri}" }
          WebAuth::Relay.run(login)
          Result::Status.new('Login done: paste the code shown by the browser in the terminal of ascli that waits for it')
        rescue ParameterError => e
          raise BadArgument, e.message
        rescue Errno::EADDRINUSE
          raise Cli::Error, "Cannot listen on #{login.redirect_uri}: the port is used. The URL is registered for the login, it cannot be changed: free the port, and retry."
        end

        # The login page opened by `web_login` comes from a code given by another host (or in a message): ask the user to accept its host the first time.
        # Accepted hosts are kept in persistency. Without a terminal, an unknown host is refused.
        # @param host [String] Host of the login page
        # @raise [BadArgument] if the host is not accepted
        def confirm_web_login_host(host)
          persist = context.persistency
          hosts = persist.get(WEB_LOGIN_HOSTS_ID).to_s.split("\n")
          return if hosts.include?(host)
          raise BadArgument, "Host of the login page is not known: #{host}. Run this command in a terminal to accept it." unless $stdin.tty?
          Log.log.warn { "This code opens the login page of: #{host}" }
          answer = Prompt.prompt_user_input("Open it, and trust this host for next logins? (yes/no)")
          raise BadArgument, "Host of the login page refused: #{host}" unless %w[y yes].include?(answer.strip.downcase)
          persist.put(WEB_LOGIN_HOSTS_ID, (hosts + [host]).join("\n"))
        end

        def action_download(file_url:, file_dest: nil, **)
          file_url = file_url.chomp
          # Default: destination folder of downloads of the service `transfer` (option `to_folder`)
          file_dest = File.join(transfer.destination_folder(:receive), file_url.rpartition('/').last) if file_dest.nil?
          file_dest = Security.instance.writable_path(file_dest)
          Log.log.info("Downloading: #{file_url}")
          Rest::Client.new(base_url: file_url).call(operation: 'GET', save_to: file_dest)
          Result::Status.new("Saved to: #{file_dest}")
        end

        def action_tokens_show(token_id:, **)
          data = OAuth::Factory.instance.get_token_info(token_id)
          Aspera.assert(!data.nil?, type: Cli::Error) { 'Unknown identifier' }
          Result::SingleObject.new(data)
        end

        def action_plugins_list(**)
          factory = Plugins::Factory.instance
          result = factory.listed_plugins.map do |name|
            status = factory.status(name)
            loaded = status.eql?('available') ? factory.plugin_class(name) : nil
            {
              plugin: name,
              detect: loaded.nil? ? nil : TerminalFormatter.tick(loaded.respond_to?(:detect)),
              wizard: loaded.nil? ? nil : TerminalFormatter.tick(loaded.method_defined?(:wizard)),
              status: status,
              path:   factory.registry[name].path
            }
          end
          Result::ObjectList.new(result, fields: %w[plugin detect wizard status path])
        end

        def action_plugins_show(name:, **)
          Result::SingleObject.new(Plugins::Factory.instance.describe(name.to_sym))
        end

        def action_plugins_create(name:, folder: nil, **)
          plugin_name = name.downcase
          # The name is inserted in Ruby code and in a file name
          Aspera.assert(plugin_name.match?(/\A[a-z][a-z0-9_]*\z/), type: BadArgument) { "plugin name must be lowercase letters, digits and underscores: #{name}" }
          destination_folder = folder || File.join(context.main_folder, ASPERA_PLUGINS_FOLDERNAME)
          plugin_file = File.join(destination_folder, "#{plugin_name}.rb")
          content = <<~END_OF_PLUGIN_CODE
            require 'aspera/cli/plugins/base'
            module Aspera
              module Cli
                module Plugins
                  class #{plugin_name.snake_to_capital} < Base
                    command :example, description: 'example command', action: ->(**) { Result::Status.new('You called plugin #{plugin_name}') }
                  end
                end
              end
            end
          END_OF_PLUGIN_CODE
          File.write(plugin_file, content)
          Result::Status.new("Created #{plugin_file}")
        end

        def action_initdemo(**)
          cp = presets.config_presets
          if cp.key?(DEMO_PRESET)
            Log.log.warn { "Demo server preset already present: #{DEMO_PRESET}" }
          else
            Log.log.info { "Creating Demo server preset: #{DEMO_PRESET}" }
            cp[DEMO_PRESET] = {
              'url'                                    => "ssh://#{DEMO_SERVER}.asperasoft.com:33001",
              'username'                               => ASPERA,
              'ssAP'.downcase.reverse + 'drow'.reverse => DEMO_SERVER + ASPERA,
              # The demo server offers only host key `ssh-rsa` (SHA-1), not enabled by default in `Net::SSH` (browse, delete...)
              'ssh_options'                            => {'host_key' => DEMO_SERVER_HOST_KEYS}
            }
          end
          cp[PresetManager::Key::DEFAULTS] ||= {}
          if cp[PresetManager::Key::DEFAULTS].key?(SERVER_COMMAND)
            Log.log.warn { "Server default preset already set to: #{cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND]}" }
            Log.log.warn { "Use #{DEMO_PRESET} for demo: -P#{DEMO_PRESET}" } unless
              DEMO_PRESET.eql?(cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND])
          else
            cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND] = DEMO_PRESET
            Log.log.info { "Setting server default preset to : #{DEMO_PRESET}" }
          end
          Result::Status.new('Done')
        end

        def action_commands(plugin_name: nil, command_path: nil, **)
          plugin_names = Plugins::Factory.instance.plugin_list
          unless plugin_name.nil?
            Aspera.assert_values(plugin_name.to_sym, plugin_names, type: Cli::BadArgument)
            plugin_names = [plugin_name.to_sym]
          end
          words = Array(command_path).map(&:to_sym)
          Aspera.assert(words.empty? || plugin_names.length.eql?(1), type: Cli::BadArgument) { 'command path requires a plugin name' }
          expand_mounts = options.get_option(:expand_mounts)
          commands = plugin_names.flat_map do |name|
            reg = Plugins::Factory.instance.plugin_class(name).command_registry
            prefix = listed_command_path(name, reg, words)
            paths = prefix.empty? || reg.children_of(prefix).any? ? reg.leaf_paths(prefix, expand_mounts: expand_mounts) : [prefix]
            # Commands refused by security level are not proposed
            paths = paths.select { |path| path.each_index.all? { |i| Security.instance.allowed?(reg[path[0, i + 1]]&.security) } }
            paths.map do |path|
              mount = expand_mounts ? nil : reg.mount_at(path)
              description = reg[path]&.description.to_s
              if mount
                target = mount.plugin.plugin_name
                description = "#{description} (see: #{command_syntax(target, mount.registry, mount.at)})"
              end
              {
                syntax:      command_syntax(name, reg, path) + (mount ? ' <command...>' : ''),
                description: description
              }
            end
          end
          Result::ObjectList.new(commands, fields: %w[syntax description])
        end

        # Command path to list, from words that may include positional arguments, as on a command line.
        # e.g. `faspex5 packages receive ALL` lists `faspex5 packages receive`.
        # @param name  [Symbol]          plugin name
        # @param reg   [Command::Registry] registry of plugin
        # @param words [Array<Symbol>]   sub-commands (or aliases), possibly mixed with their arguments
        # @return [Array<Symbol>] command path
        # @raise [Cli::BadArgument] if a word is neither a sub-command nor an expected argument
        def listed_command_path(name, reg, words)
          path, unknown = reg.command_path(words)
          raise Cli::BadArgument, Parser.multi_choice_assert_msg("no such command: #{[name, *path, unknown].join(' ')}", reg.children_of(path).keys) unless unknown.nil?
          path
        end

        # Build syntax by interleaving each path segment with the arguments declared on that node
        # @param name [String, Symbol]       plugin name
        # @param reg  [Command::Registry]      registry of plugin
        # @param path [Array<Symbol>]        command path
        # @return [String] e.g. `node access_keys do <access_key_id> ls <path>`
        def command_syntax(name, reg, path)
          tokens = [name.to_s]
          path.each_index do |i|
            tokens << path[i].to_s
            reg.arguments_at(path[0, i + 1]).each { |a| tokens << a.syntax }
          end
          tokens.join(' ')
        end

        def action_options(plugin_name:, **)
          # Instantiate the plugin so that it registers all its options in context.options
          Plugins::Factory.instance.create(plugin_name.to_sym, context: context)
          rows = context.options.declared_options.map do |sym, opt|
            row = {
              'option'      => "--#{sym.to_s.tr('_', '-')}",
              'description' => opt.description.to_s
            }
            row['allowed']     = opt.allowed_info unless opt.allowed_info.nil?
            row['deprecated']  = opt.deprecation.last if opt.deprecation
            row['replacement'] = opt.deprecation.message if opt.deprecation
            row
          end
          Result::ObjectList.new(rows, fields: %w[option description allowed deprecated replacement])
        end

        # Folder in $HOME for application files (~/.aspera)
        ASPERA_HOME_FOLDER_NAME = '.aspera'
        # Default config file name
        DEFAULT_CONFIG_FILENAME = 'config.yaml'
        CONF_GLOBAL_SYM = :config
        # Folder containing custom plugins in user's config folder
        ASPERA_PLUGINS_FOLDERNAME = 'plugins'
        PERSISTENCY_FOLDER = 'persist_store'
        # Persistency identifier of the hosts of login pages that the user accepted for `web_login`
        WEB_LOGIN_HOSTS_ID = 'web_login_hosts'
        REST_EXCEPTIONS_LOG_FILENAME = 'rest_exceptions.log'
        ASPERA = 'aspera'
        SERVER_COMMAND = 'server'
        DEMO_SERVER = 'demo'
        DEMO_PRESET = 'demoserver'
        # SSH host key algorithms for the demo server: `ssh-rsa` last, used only if the server offers nothing better
        DEMO_SERVER_HOST_KEYS = %w[rsa-sha2-512 rsa-sha2-256 ssh-rsa].freeze
        EMAIL_TEST_TEMPLATE = <<~END_OF_TEMPLATE.freeze
          From: <%=from_name%> <<%=from_email%>>
          To: <<%=to%>>
          Subject: #{Info::GEM_NAME} email test

          This email was sent to test #{Info::CMD_NAME}.
        END_OF_TEMPLATE
        # Special extended values
        EXTEND_PRESET = :preset
        EXTEND_VAULT = :vault
        COFFEE_IMAGE_URL = 'https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg'
        private_constant :ASPERA_HOME_FOLDER_NAME,
          :DEFAULT_CONFIG_FILENAME,
          :CONF_GLOBAL_SYM,
          :ASPERA_PLUGINS_FOLDERNAME,
          :PERSISTENCY_FOLDER,
          :WEB_LOGIN_HOSTS_ID,
          :REST_EXCEPTIONS_LOG_FILENAME,
          :ASPERA,
          :SERVER_COMMAND,
          :DEMO_SERVER,
          :DEMO_PRESET,
          :DEMO_SERVER_HOST_KEYS,
          :EMAIL_TEST_TEMPLATE,
          :EXTEND_PRESET,
          :EXTEND_VAULT,
          :COFFEE_IMAGE_URL
      end
    end
  end
end
