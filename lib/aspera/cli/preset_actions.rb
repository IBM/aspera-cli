# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative '../dot_container'
require_relative '../hash_ext'
require_relative '../secret/hider'
require_relative 'security'
require_relative 'preset_manager'
require_relative 'deprecation'
require_relative 'info'
require 'json'

module Aspera
  module Cli
    # Mixin for Config plugin: preset CRUD actions
    module PresetActions
      # Used to identify the global default preset keyword
      GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
      # Display columns for preset overview
      CONF_OVERVIEW_KEYS = %w[preset parameter value].freeze
      # Keys of the criteria for preset lookup
      LOOKUP_KEYS = %w[url username].freeze
      # Last released version without deprecation of preset commands `update`, `initialize` and `unset`
      PRESET_DEPRECATED_LAST = '4.28.0'
      # Default of an argument not given (`omit_absent`), different from `nil` (`@none:`)
      NOT_GIVEN = Object.new.freeze

      def action_preset_overview(**)
        # Secrets hidden by key name here: the key becomes the value of column `parameter`
        data = formatter.hide_secrets(presets.config_presets)
        result = []
        data.each do |config, preset|
          preset.each do |parameter, value|
            result.push(CONF_OVERVIEW_KEYS.zip([config, parameter, value]).to_h)
          end
        end
        Result::ObjectList.new(result, fields: CONF_OVERVIEW_KEYS)
      end

      # @param criteria [Hash] `url` and `username` of the preset to find
      def action_preset_lookup(criteria:, **)
        Aspera.assert((criteria.keys - LOOKUP_KEYS).empty? && (LOOKUP_KEYS - criteria.keys).empty?, type: BadArgument) { "Expected keys: #{LOOKUP_KEYS.join(', ')}" }
        result = presets.lookup_preset(url: criteria['url'], username: criteria['username'])
        Aspera.assert(!result.nil?, type: EntityNotFound) { 'no such config found' }
        Result::SingleObject.new(result)
      end

      def action_preset_secure(config_name: nil, **)
        cp = presets.config_presets
        preset_names = config_name.nil? ? cp.keys : [config_name]
        preset_names.each do |preset_name|
          preset = cp[preset_name]
          next unless preset.is_a?(Hash)
          preset.each_key do |option_name|
            secure_preset_option(preset, preset_name, option_name)
          end
        end
        Result::Status.new('Secrets secured in vault: Make sure to save the vault password securely.')
      end

      private

      SECRET_KEYWORDS = %w[password secret].freeze

      # @param name   [String]  preset name, or `GLOBAL` for the global default preset
      # @param create [Boolean] `true` for an action writing in the preset: the global default preset is declared and created if needed
      # @return [String] preset name
      def preset_name(name, create: false)
        return name unless name.eql?(GLOBAL_DEFAULT_KEYWORD)
        presets.global_default_preset(create: create)
      end

      # If `option_name` ends with a secret keyword and the vault is configured,
      # move the clear-text value into the vault and replace it with a @vault: reference.
      # @param preset      [Hash]   the preset hash (modified in place)
      # @param preset_name [String] name used as base for the vault label
      # @param option_name [String] option key to inspect
      # A preset is evaluated when used, maybe at a lower security level (e.g. on the command line): it cannot hold what the current level refuses.
      # @param param_name  [String, Symbol] Option name, or dot-path in an option (e.g. `ui.command`)
      # @param param_value [Object] Value to store
      # @raise [BadArgument] If the option, a sub-option (`x-security` in schema), or the value, is refused at current security level
      def check_preset_entry(param_name, param_value)
        path = param_name.to_s.tr('-', '_').split(DotContainer::SEPARATOR)
        option_name = path.first.to_sym
        if options.option_declared?(option_name)
          # Value of the option, from the sub-option given by dot-path
          option_value = path.drop(1).reverse.inject(param_value) { |value, key| {key => value} }
          options.option_def(option_name).check_security(option_value)
        end
        Security.instance.check_stored_value(param_value, "preset option #{option_name}")
      end

      def secure_preset_option(preset, preset_name, option_name)
        return unless SECRET_KEYWORDS.any? { |kw| option_name.end_with?(kw) }
        # Vault password is not saved in vault
        return if option_name.eql?('vault_password')
        # Never auto-secure the global preset: it holds vault credentials themselves
        # Checked before opening the vault, which may not be usable yet (e.g. vault_password not set)
        return if presets.global_preset?(preset_name)
        return if vault.nil?
        value = preset[option_name]
        # Already a vault reference or nil - nothing to do
        return if value.nil? || value.to_s.start_with?('@vault:')
        vault_label = preset_name
        incr = 0
        until vault.get(label: vault_label, exception: false).nil?
          vault_label = "#{preset_name}#{incr}"
          incr += 1
        end
        Log.log.info { "Securing #{preset_name}.#{option_name} -> vault label: #{vault_label}" }
        vault.set({label: vault_label, password: value}) # HashiCorpIgnore
        preset[option_name] = "@vault:#{vault_label}.password"
      end

      public

      def action_preset_show(name:, **)
        name = preset_name(name)
        cp = presets.config_presets
        raise Cli::BadArgument, "no such preset: #{name}" unless cp.key?(name)
        Result::SingleObject.new(cp[name])
      end

      def action_preset_delete(name:, **)
        name = preset_name(name)
        raise Cli::BadArgument, "no such preset: #{name}" unless presets.config_presets.key?(name)
        delete_preset(name)
        Result::Status.new("Deleted: #{name}")
      end

      def action_preset_get(name:, param_name:, **)
        name = preset_name(name)
        cp = presets.config_presets
        raise Cli::BadArgument, "no such preset: #{name}" unless cp.key?(name)
        value = cp[name][param_name]
        raise Cli::BadArgument, "no such option in preset #{name}: #{param_name}" if value.nil?
        case value
        when Numeric, String
          value = ExtendedValue.instance.evaluate(value.to_s, context: 'preset')
          # A secret has no key name in a text result: declared, so that it is hidden
          Secret::Hider.instance.add_secret_values(value) if Secret::Hider.instance.secret?(param_name, value)
          return Result::Text.new(value)
        end
        Result::SingleObject.new(value)
      end

      def action_preset_unset(name:, param_name:, **)
        Log.log.warn { "Command preset unset is #{Deprecation.new(last: PRESET_DEPRECATED_LAST, message: "use: #{Info::CMD_NAME} config preset set #{shell_word(name)} #{shell_word(param_name)} @none:")}" }
        name = preset_name(name)
        cp = presets.config_presets
        raise Cli::BadArgument, "no such preset: #{name}" unless cp.key?(name)
        cp[name].delete(param_name)
        Result::Status.new("Removed: #{name}: #{param_name}")
      end

      # Merge into presets (JSON Merge Patch: a value `nil` removes the key), with one of:
      # - `name` is a Hash: presets by name (a preset `nil` is deleted)
      # - `name` and `param_name` is a Hash: parameters of the preset
      # - `name`, `param_name` and `param_value`: one parameter (dot-path), asked if not given
      # @param name        [String, Hash] Preset name, or presets
      # @param param_name  [String, Hash] Parameter name (dot-path), or parameters, not given for presets
      # @param param_value [Object]       Value of the parameter, `nil` removes it
      def action_preset_set(name:, param_name: NOT_GIVEN, param_value: NOT_GIVEN, **)
        if name.is_a?(Hash)
          raise Cli::BadArgument, 'set <presets>: no other argument expected' unless param_name.equal?(NOT_GIVEN)
          name.each { |preset, values| merge_preset(preset, values) }
          return Result::Status.new("Updated: #{name.keys.join(', ')}")
        end
        raise Cli::BadArgument, 'set <name>: expecting <Hash> of parameters, or <param> <value>' if param_name.equal?(NOT_GIVEN)
        if param_name.is_a?(Hash)
          raise Cli::BadArgument, 'set <name> <Hash>: no other argument expected' unless param_value.equal?(NOT_GIVEN)
          merge_preset(name, param_name)
          return Result::Status.new("Updated: #{preset_name(name)}")
        end
        param_value = options.get_next_argument('param_value', validation: nil, evaluate: :smart) if param_value.equal?(NOT_GIVEN)
        name = preset_name(name, create: true)
        # Key names are not secrets: converted, or split with dot-notation, a secret would not be hidden in results
        Security.instance.check_secret_processing('preset parameter name', hint: 'give a name that is not a secret') do
          Secret::Hider.instance.contains_secret?(param_name)
        end
        param_name = Parser.option_line_to_name(param_name)
        check_preset_entry(param_name, param_value) unless param_value.nil?
        presets.set_key(name, param_name, param_value)
        secure_preset_option(presets.config_presets[name], name, param_name)
        Result::Nothing.new
      end

      def action_preset_initialize(name:, preset:, **)
        Log.log.warn { "Command preset initialize is #{Deprecation.new(last: PRESET_DEPRECATED_LAST, message: "use: #{Info::CMD_NAME} config preset delete #{shell_word(name)}, then: #{Info::CMD_NAME} config preset set #{shell_word(name)} <Hash>")}" }
        name = preset_name(name, create: true)
        cp = presets.config_presets
        Log.log.warn { "configuration already exists: #{name}, overwriting" } if cp.key?(name)
        Aspera.assert_type(preset, Hash, type: Cli::BadArgument) { 'preset' }
        preset.each { |k, v| check_preset_entry(k, v) }
        cp[name] = preset
        Result::Status.new("Initialized: #{name}")
      end

      # Deprecated: options placed after `update` are merged into the preset.
      def action_preset_update(name:, **)
        values = options.unprocessed_options_with_value(after_command: true)
        Log.log.warn { "Command preset update is #{Deprecation.new(last: PRESET_DEPRECATED_LAST, message: "use: #{set_command_hint(name, values)}")}" }
        merge_preset(name, values)
        Result::Status.new("Updated: #{preset_name(name)}")
      end

      def action_preset_ask(name:, option_names:, **)
        name = preset_name(name, create: true)
        cp = presets.config_presets
        cp[name] ||= {}
        # Option names are only known at runtime: cannot be declared as interactive arguments
        options.with_interactive do
          option_names.each do |option_name|
            option_value = options.get_interactive(option_name)
            cp[name][option_name] = option_value
            secure_preset_option(cp[name], name, option_name)
          end
        end
        Result::Status.new("Updated: #{name}")
      end

      private

      # Merge parameters into a preset (JSON Merge Patch), or delete it.
      # @param name   [String]    Preset name
      # @param values [Hash, nil] Parameters: option names, a value `nil` removes the parameter. `nil`: delete the preset.
      def merge_preset(name, values)
        raise Cli::BadArgument, "section #{PresetManager::Key::CONFIG} is managed by #{Info::CMD_NAME}" if name.to_s.eql?(PresetManager::Key::CONFIG)
        name = preset_name(name.to_s, create: !values.nil?)
        return delete_preset(name) if values.nil?
        Aspera.assert_type(values, Hash, type: Cli::BadArgument) { "parameters of preset #{name}" }
        values = values.transform_keys { |k| Parser.option_line_to_name(k.to_s) }
        Log.dump(:values, values)
        values.each { |k, v| check_preset_entry(k, v) unless v.nil? }
        cp = presets.config_presets
        cp[name] ||= {}
        Aspera.assert_type(cp[name], Hash, type: Cli::BadArgument) { "preset #{name}" }
        merge_patch!(cp[name], PresetManager.stringify_secrets(nil, values))
        values.each { |k, v| secure_preset_option(cp[name], name, k) unless v.nil? }
        nil
      end

      # Merge `patch` into `target` (RFC 7396 JSON Merge Patch): a value `nil` removes the key, a `Hash` is merged.
      # @param target [Hash] Modified in place
      # @param patch  [Hash]
      # @return [Hash] target
      def merge_patch!(target, patch)
        patch.each do |key, value|
          if value.nil? then target.delete(key)
          elsif value.is_a?(Hash) then target[key] = merge_patch!(target[key].is_a?(Hash) ? target[key] : {}, value)
          else target[key] = value
          end
        end
        target
      end

      # Delete a preset, and default declarations referring to it.
      # @param name [String] Preset name
      def delete_preset(name)
        cp = presets.config_presets
        cp.delete(name)
        defaults = cp[PresetManager::Key::DEFAULTS]
        defaults&.select { |_, preset_name| preset_name.eql?(name) }&.each_key do |plugin|
          defaults.delete(plugin)
          Log.log.info { "Removed: #{PresetManager::Key::DEFAULTS}: #{plugin}" }
        end
        nil
      end

      # Command to use instead of the deprecated `preset update`, without secret values.
      # Secret parameters are named after the command: in logs, the value of a secret parameter is hidden.
      # @param name   [String] Preset name
      # @param values [Hash]   Values taken from options
      # @return [String] e.g. `ascli config preset set p1 @: url=https://example.com username=bob, and secret parameters: password`
      def set_command_hint(name, values)
        secrets, others = DotContainer.new(values).to_dotted.partition do |path, value|
          Secret::Hider.instance.secret?(path.to_s.split(DotContainer::SEPARATOR).last, value)
        end
        assignments = others.map do |path, value|
          value = "@json:#{JSON.generate(value)}" if value.is_a?(Array) || value.is_a?(Hash)
          shell_word("#{path}=#{value}")
        end
        hint = [Info::CMD_NAME, 'config', 'preset', 'set', shell_word(name), '@:', *assignments].join(' ')
        hint = "#{hint}, and secret parameters (e.g. with @secret: or @val:@vault:): #{secrets.map(&:first).join(', ')}" unless secrets.empty?
        hint
      end

      # @param word [String] Word of a command line
      # @return [String] Word, quoted for a shell only if needed
      def shell_word(word)
        word.match?(%r{\A[\w@:/.,=+%-]+\z}) ? word : "'#{word.gsub("'") { %q('\\'') }}'"
      end
    end
  end
end
