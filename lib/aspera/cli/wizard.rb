# frozen_string_literal: true

require 'aspera/oauth/jwt'

module Aspera
  module Cli
    class Wizard
      WIZARD_RESULT_KEYS = %i[preset_value test_args].freeze
      DEFAULT_PRIV_KEY_FILENAME = 'my_private_key.pem' # pragma: allowlist secret
      private_constant :WIZARD_RESULT_KEYS,
        :DEFAULT_PRIV_KEY_FILENAME

      def initialize(parent, main_folder)
        @parent = parent
        @main_folder = main_folder
        # wizard options
        options.declare(:override, 'Wizard: override existing value', values: :bool, default: :no)
        options.declare(:default, 'Wizard: set as default configuration for specified plugin (also: update)', values: :bool, default: true)
        options.declare(:test_mode, 'Wizard: skip private key check step', values: :bool, default: false)
        options.declare(:key_path, 'Wizard: path to private key for JWT')
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

      # Find a plugin, and issue the "require"
      # @return [Hash] plugin info: { product:, name:, url:, version: }
      def identify_plugins_for_url
        app_url = options.get_next_argument('url', mandatory: true)
        check_only = options.get_next_argument('plugin name', mandatory: false)
        check_only = check_only.to_sym unless check_only.nil?
        found_apps = []
        my_self_plugin_sym = self.class.name.split('::').last.downcase.to_sym
        PluginFactory.instance.plugin_list.each do |plugin_name_sym|
          # no detection for internal plugin
          next if plugin_name_sym.eql?(my_self_plugin_sym)
          next if check_only && !check_only.eql?(plugin_name_sym)
          # load plugin class
          detect_plugin_class = PluginFactory.instance.plugin_class(plugin_name_sym)
          # requires detection method
          next unless detect_plugin_class.respond_to?(:detect)
          detection_info = nil
          begin
            Log.log.debug{"detecting #{plugin_name_sym} at #{app_url}"}
            formatter.long_operation_running("#{plugin_name_sym}\r")
            detection_info = detect_plugin_class.detect(app_url)
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
          app_name = detect_plugin_class.respond_to?(:application_name) ? detect_plugin_class.application_name : detect_plugin_class.name.split('::').last
          # if there is a redirect, then the detector can override the url.
          found_apps.push({product: plugin_name_sym, name: app_name, url: app_url, version: 'unknown'}.merge(detection_info))
        end
        raise "No known application found at #{app_url}" if found_apps.empty?
        Aspera.assert(found_apps.all?{ |a| a.keys.all?(Symbol)})
        return found_apps
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
        # set url for instantiation of plugin
        options.add_option_preset({url: wiz_url}, 'wizard')
        # instantiate plugin: command line options will be known and wizard can be called
        wiz_plugin_class = PluginFactory.instance.plugin_class(identification[:product])
        Aspera.assert(wiz_plugin_class.respond_to?(:wizard), type: Cli::BadArgument) do
          "Detected: #{identification[:product]}, but this application has no wizard"
        end
        # instantiate plugin: command line options will be known, e.g. private_key
        plugin_instance = wiz_plugin_class.new(context: @parent.context)
        wiz_params = {
          object: plugin_instance
        }
        # is private key needed ?
        if options.known_options.key?(:private_key) &&
            (!wiz_plugin_class.respond_to?(:private_key_required?) || wiz_plugin_class.private_key_required?(wiz_url))
          # lets see if path to priv key is provided
          private_key_path = options.get_option(:key_path)
          # give a chance to provide
          if private_key_path.nil?
            formatter.display_status('Please provide the path to your private RSA key, or nothing to generate one:')
            private_key_path = options.get_option(:key_path, mandatory: true).to_s
          end
          # else generate path
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
          options.set_option(:private_key, private_key_pem)
          wiz_params[:private_key_path] = private_key_path
          wiz_params[:pub_key_pem] = OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s
        end
        Log.dump(:wiz_params, wiz_params)
        # finally, call the wizard
        wizard_result = wiz_plugin_class.wizard(**wiz_params)
        Log.log.debug{"wizard result: #{wizard_result}"}
        Aspera.assert(WIZARD_RESULT_KEYS.eql?(wizard_result.keys.sort)){"missing or extra keys in wizard result: #{wizard_result.keys}"}
        # get preset name from user or default
        if wiz_preset_name.empty?
          elements = [
            identification[:product],
            URI.parse(wiz_url).host
          ]
          elements.push(options.get_option(:username, mandatory: true)) unless wizard_result[:preset_value].key?(:link) rescue nil
          wiz_preset_name = elements.join('_').strip.downcase.gsub(/[^a-z0-9]/, '_').squeeze('_')
        end
        # test mode does not change conf file
        return Main.result_single_object(wizard_result) if options.get_option(:test_mode)
        # Write configuration file
        formatter.display_status("Preparing preset: #{wiz_preset_name}")
        # init defaults if necessary
        option_override = options.get_option(:override, mandatory: true)
        option_default = options.get_option(:default, mandatory: true)
        config.defaults_set(identification[:product], wiz_preset_name, wizard_result[:preset_value].stringify_keys, option_default, option_override)
        test_args = wizard_result[:test_args]
        test_args = "-P#{wiz_preset_name} #{test_args}" unless option_default
        # TODO: actually test the command
        return Main.result_status("You can test with:\n#{Info::CMD_NAME} #{identification[:product]} #{test_args}")
      end
    end
  end
end
