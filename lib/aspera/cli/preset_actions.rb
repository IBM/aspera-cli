# frozen_string_literal: true

require 'aspera/assert'

module Aspera
  module Cli
    # Mixin for Config plugin: preset CRUD actions
    module PresetActions
      # Used to identify the global default preset keyword
      GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
      # Display columns for preset overview
      CONF_OVERVIEW_KEYS = %w[preset parameter value].freeze

      def action_preset_list(**)
        Result::ValueList.new(presets.config_presets.keys, name: 'name')
      end

      def action_preset_overview(**)
        cp = presets.config_presets
        # Display process modifies the value (hide secrets): we do not want to save removed secrets
        data = PresetManager.deep_clone(cp)
        formatter.hide_secrets(data)
        result = []
        data.each do |config, preset|
          preset.each do |parameter, value|
            result.push(CONF_OVERVIEW_KEYS.zip([config, parameter, value]).to_h)
          end
        end
        Result::ObjectList.new(result, fields: CONF_OVERVIEW_KEYS)
      end

      def action_preset_lookup(**)
        Plugins::BasicAuth.declare_options(options)
        url = options.get_option(:url, mandatory: true)
        user = options.get_option(:username, mandatory: true)
        result = presets.lookup_preset(url: url, username: user)
        Aspera.assert(!result.nil?, type: Error){'no such config found'}
        Result::SingleObject.new(result)
      end

      def action_preset_secure(config_name: nil, **)
        cp = presets.config_presets
        preset_names = config_name.nil? ? cp.keys : [config_name]
        secret_keywords = %w[password secret].freeze
        preset_names.each do |preset_name|
          preset = cp[preset_name]
          next unless preset.is_a?(Hash)
          preset.each_key do |option_name|
            secret_keywords.each do |keyword|
              next unless option_name.end_with?(keyword)
              vault_label = preset_name
              incr = 0
              until vault.get(label: vault_label, exception: false).nil?
                vault_label = "#{preset_name}#{incr}"
                incr += 1
              end
              to_set = {label: vault_label, password: preset[option_name]}
              puts "need to encode #{preset_name}.#{option_name} -> #{vault_label} -> #{to_set}"
              vault.set(to_set)
              preset[option_name] = "@vault:#{vault_label}.password"
            end
          end
        end
        Result::Status.new('Secrets secured in vault: Make sure to save the vault password securely.')
      end

      def action_preset_show(name:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        cp = presets.config_presets
        raise "no such preset: #{name}" unless cp.key?(name)
        Result::SingleObject.new(PresetManager.deep_clone(cp[name]))
      end

      def action_preset_delete(name:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        cp = presets.config_presets
        raise "no such preset: #{name}" unless cp.key?(name)
        cp.delete(name)
        Result::Status.new("Deleted: #{name}")
      end

      def action_preset_get(name:, param_name:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        cp = presets.config_presets
        raise "no such preset: #{name}" unless cp.key?(name)
        value = cp[name][param_name]
        raise "no such option in preset #{name} : #{param_name}" if value.nil?
        case value
        when Numeric, String then return Result::Text.new(ExtendedValue.instance.evaluate(value.to_s, context: 'preset'))
        end
        Result::SingleObject.new(value)
      end

      def action_preset_unset(name:, param_name:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        cp = presets.config_presets
        raise "no such preset: #{name}" unless cp.key?(name)
        cp[name].delete(param_name)
        Result::Status.new("Removed: #{name}: #{param_name}")
      end

      def action_preset_set(name:, param_name:, param_value:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        param_name = Options.option_line_to_name(param_name)
        presets.set_key(name, param_name, param_value)
        Result::Nothing.new
      end

      def action_preset_initialize(name:, config_value:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        cp = presets.config_presets
        Log.log.warn{"configuration already exists: #{name}, overwriting"} if cp.key?(name)
        cp[name] = config_value
        Result::Status.new("Modified: #{@option_config_file}")
      end

      def action_preset_update(name:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        unprocessed_options = options.unprocessed_options_with_value
        Log.log.debug{"opts=#{unprocessed_options}"}
        cp = presets.config_presets
        cp[name] ||= {}
        cp[name].merge!(unprocessed_options)
        Result::Status.new("Updated: #{name}")
      end

      def action_preset_ask(name:, option_names:, **)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        cp = presets.config_presets
        cp[name] ||= {}
        option_names.each do |option_name|
          option_value = options.get_interactive(option_name, check_option: true)
          cp[name][option_name] = option_value
        end
        Result::Status.new("Updated: #{name}")
      end
    end
  end
end
