# frozen_string_literal: true

module Aspera
  module Cli
    # Mixin for Config plugin: preset CRUD actions
    module PresetActions
      # Used to identify the global default preset keyword
      GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
      # Display columns for preset overview
      CONF_OVERVIEW_KEYS = %w[preset parameter value].freeze
      # Legacy actions available globally
      PRESET_GBL_ACTIONS = %i[list overview lookup secure].freeze
      # Operations requiring that preset exists
      PRESET_EXIST_ACTIONS = %i[show delete get unset].freeze
      # require id
      PRESET_INSTANCE_ACTIONS = %i[initialize update ask set].concat(PRESET_EXIST_ACTIONS).freeze
      PRESET_ALL_ACTIONS = (PRESET_GBL_ACTIONS + PRESET_INSTANCE_ACTIONS).freeze

      def execute_preset(action: nil, name: nil)
        cp = presets.config_presets
        action = options.get_next_command(PRESET_ALL_ACTIONS) if action.nil?
        name = options.instance_identifier if name.nil? && PRESET_INSTANCE_ACTIONS.include?(action)
        name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
        # Those operations require existing option
        raise "no such preset: #{name}" if PRESET_EXIST_ACTIONS.include?(action) && !cp.key?(name)
        case action
        when :list
          return Result::ValueList.new(cp.keys, name: 'name')
        when :overview
          # Display process modifies the value (hide secrets): we do not want to save removed secrets
          data = PresetManager.deep_clone(cp)
          formatter.hide_secrets(data)
          result = []
          data.each do |config, preset|
            preset.each do |parameter, value|
              result.push(CONF_OVERVIEW_KEYS.zip([config, parameter, value]).to_h)
            end
          end
          return Result::ObjectList.new(result, fields: CONF_OVERVIEW_KEYS)
        when :show
          return Result::SingleObject.new(PresetManager.deep_clone(cp[name]))
        when :delete
          cp.delete(name)
          return Result::Status.new("Deleted: #{name}")
        when :get
          param_name = options.get_next_argument('parameter name')
          value = cp[name][param_name]
          raise "no such option in preset #{name} : #{param_name}" if value.nil?
          case value
          when Numeric, String then return Result::Text.new(ExtendedValue.instance.evaluate(value.to_s, context: 'preset'))
          end
          return Result::SingleObject.new(value)
        when :unset
          param_name = options.get_next_argument('parameter name')
          cp[name].delete(param_name)
          return Result::Status.new("Removed: #{name}: #{param_name}")
        when :set
          param_name = options.get_next_argument('parameter name')
          param_name = Manager.option_line_to_name(param_name)
          param_value = options.get_next_argument('parameter value', validation: nil)
          set_preset_key(name, param_name, param_value)
          return Result::Nothing.new
        when :initialize
          config_value = options.get_next_argument('extended value', validation: Hash)
          Log.log.warn{"configuration already exists: #{name}, overwriting"} if cp.key?(name)
          cp[name] = config_value
          return Result::Status.new("Modified: #{@option_config_file}")
        when :update
          unprocessed_options = options.unprocessed_options_with_value
          Log.log.debug{"opts=#{unprocessed_options}"}
          cp[name] ||= {}
          cp[name].merge!(unprocessed_options)
          return Result::Status.new("Updated: #{name}")
        when :ask
          options.ask_missing_mandatory = true
          cp[name] ||= {}
          options.get_next_argument('option names', multiple: true).each do |option_name|
            option_value = options.get_interactive(option_name, check_option: true)
            cp[name][option_name] = option_value
          end
          return Result::Status.new("Updated: #{name}")
        when :lookup
          Plugins::BasicAuth.declare_options(options)
          url = options.get_option(:url, mandatory: true)
          user = options.get_option(:username, mandatory: true)
          result = lookup_preset(url: url, username: user)
          raise Error, 'no such config found' if result.nil?
          return Result::SingleObject.new(result)
        when :secure
          identifier = options.get_next_argument('config name', mandatory: false)
          preset_names = identifier.nil? ? cp.keys : [identifier]
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
          return Result::Status.new('Secrets secured in vault: Make sure to save the vault password securely.')
        end
      end
    end
  end
end
