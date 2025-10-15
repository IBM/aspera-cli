# frozen_string_literal: true

require 'aspera/oauth/jwt'
require 'aspera/assert'

module Aspera
  module Cli
    # The wizard detects applications and generates a config
    class Wizard
      WIZARD_RESULT_KEYS = %i[preset_value test_args].freeze
      DEFAULT_PRIV_KEY_FILENAME = 'my_private_key.pem' # pragma: allowlist secret
      private_constant :WIZARD_RESULT_KEYS,
        :DEFAULT_PRIV_KEY_FILENAME

      def initialize(parent, main_folder)
        @parent = parent
        @main_folder = main_folder
        # Wizard options
        options.declare(:override, 'Wizard: override existing value', values: :bool, default: :no)
        options.declare(:default, 'Wizard: set as default configuration for specified plugin (also: update)', values: :bool, default: true)
        options.declare(:key_path, 'Wizard: path to private key for JWT')
      end

      # @return false if in test mode to avoid interactive input
      def required
        !ENV['ASCLI_WIZ_TEST']
      end

      def options
        @parent.options
      end

      def formatter
        @parent.formatter
      end

      def config
        @parent.config
      end

      def check_email(email)
        Aspera.assert(email =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i, type: ParameterError){"Username shall be an email: #{email}"}
      end

      # Find a plugin, and issue the "require"
      # @return [Hash] plugin info: { product:, name:, url:, version: }
      def identify_plugins_for_url
        app_url = options.get_next_argument('url', mandatory: true)
        check_only = options.get_next_argument('plugin name', mandatory: false)
        check_only = check_only.to_sym unless check_only.nil?
        found_apps = []
        my_self_plugin_sym = self.class.name.split('::').last.downcase.to_sym
        PluginFactory.instance.plugin_list.each do |plugin_name_sym|
          # No detection for internal plugin
          next if plugin_name_sym.eql?(my_self_plugin_sym)
          next if check_only && !check_only.eql?(plugin_name_sym)
          # Load plugin class
          plugin_klass = PluginFactory.instance.plugin_class(plugin_name_sym)
          # Requires detection method
          next unless plugin_klass.respond_to?(:detect)
          detection_info = nil
          begin
            Log.log.debug{"detecting #{plugin_name_sym} at #{app_url}"}
            formatter.long_operation_running("#{plugin_name_sym}\r")
            detection_info = plugin_klass.detect(app_url)
          rescue OpenSSL::SSL::SSLError => e
            Log.log.warn(e.message)
            Log.log.warn('Use option --insecure=yes to allow unchecked certificate') if e.message.include?('cert')
          rescue StandardError => e
            Log.log.debug{"detect error: [#{e.class}] #{e}"}
            next
          end
          next if detection_info.nil?
          Aspera.assert_type(detection_info, Hash)
          Aspera.assert_type(detection_info[:url], String) if detection_info.key?(:url)
          app_name = plugin_klass.respond_to?(:application_name) ? plugin_klass.application_name : plugin_klass.name.split('::').last
          # If there is a redirect, then the detector can override the url.
          found_apps.push({product: plugin_name_sym, name: app_name, url: app_url, version: 'unknown'}.merge(detection_info))
        end
        raise "No known application found at #{app_url}" if found_apps.empty?
        Aspera.assert(found_apps.all?{ |a| a.keys.all?(Symbol)})
        return found_apps
      end

      # To be called in public wizard method to get private key
      # @return [Array] Private key path, pub key PEM
      def ask_private_key(user:, url:, page:)
        # Lets see if path to priv key is provided
        private_key_path = options.get_option(:key_path)
        # Give a chance to provide
        if private_key_path.nil?
          formatter.display_status('Path to private RSA key (leave empty to generate):')
          private_key_path = options.get_option(:key_path, mandatory: true).to_s
        end
        # Else generate path
        private_key_path = File.join(@main_folder, DEFAULT_PRIV_KEY_FILENAME) if private_key_path.empty?
        if File.exist?(private_key_path)
          formatter.display_status('Using existing key:')
        else
          formatter.display_status("Generating #{OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH} bit RSA key...")
          OAuth::Jwt.generate_rsa_private_key(path: private_key_path)
          formatter.display_status('Created key:')
        end
        formatter.display_status(private_key_path)
        private_key_pem = File.read(private_key_path)
        pub_key_pem = OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s
        options.set_option(:private_key, private_key_pem)
        formatter.display_status("Please Log in as user #{user.red} at: #{url.red}")
        formatter.display_status("Navigate to: #{page}")
        formatter.display_status("Check or update the value to (#{'including BEGIN/END lines'.red}):".blink)
        formatter.display_status(pub_key_pem, hide_secrets: false)
        formatter.display_status('Once updated or validated, press [Enter].')
        Environment.instance.open_uri(url)
        $stdin.gets if required
        private_key_path
      end

      # Wizard function, creates configuration
      # @param apps [Array] list of detected apps
      def find(apps)
        identification = if apps.length.eql?(1)
          Log.log.debug{"Detected: #{identification}"}
          apps.first
        else
          formatter.display_status('Multiple applications detected, please select from:')
          formatter.display_results(type: :object_list, data: apps, fields: %w[product url version])
          answer = options.prompt_user_input_in_list('product', apps.map{ |a| a[:product]})
          apps.find{ |a| a[:product].eql?(answer)}
        end
        wiz_preset_name = options.get_next_argument('preset name', default: '')
        Log.dump(:identification, identification)
        wiz_url = identification[:url]
        formatter.display_status("Using: #{identification[:name]} at #{wiz_url}".bold)
        # Set url for instantiation of plugin
        options.add_option_preset({url: wiz_url}, 'wizard')
        # Instantiate plugin: command line options will be known, e.g. private_key, and wizard can be called
        plugin_instance = PluginFactory.instance.plugin_class(identification[:product]).new(context: @parent.context)
        Aspera.assert(plugin_instance.respond_to?(:wizard), type: Cli::BadArgument) do
          "Detected: #{identification[:product]}, but this application has no wizard"
        end
        # Call the wizard
        wizard_result = plugin_instance.wizard(self, wiz_url)
        Log.log.debug{"wizard result: #{wizard_result}"}
        Aspera.assert(WIZARD_RESULT_KEYS.eql?(wizard_result.keys.sort)){"missing or extra keys in wizard result: #{wizard_result.keys}"}
        # Get preset name from user or default
        if wiz_preset_name.empty?
          elements = [
            identification[:product],
            URI.parse(wiz_url).host
          ]
          elements.push(options.get_option(:username, mandatory: true)) unless wizard_result[:preset_value].key?(:link) rescue nil
          wiz_preset_name = elements.join('_').strip.downcase.gsub(/[^a-z0-9]/, '_').squeeze('_')
        end
        # Write configuration file
        formatter.display_status("Preparing preset: #{wiz_preset_name}")
        # Init defaults if necessary
        option_override = options.get_option(:override, mandatory: true)
        option_default = options.get_option(:default, mandatory: true)
        config.defaults_set(identification[:product], wiz_preset_name, wizard_result[:preset_value].stringify_keys, option_default, option_override)
        test_args = wizard_result[:test_args]
        test_args = "-P#{wiz_preset_name} #{test_args}" unless option_default
        # TODO: actually test the command
        test_cmd = "#{Info::CMD_NAME} #{identification[:product]} #{test_args}"
        return Main.result_status("You can test with:\n#{test_cmd.red}")
      end
    end
  end
end
