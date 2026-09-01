# frozen_string_literal: true

require 'aspera/log'

module Aspera
  module Cli
    # Resolves the secret (password) for a given URL + username pair.
    # Injected into Context as :secret_finder so that any component
    # (plugins, Api::AoC, ...) can look up secrets without going through Plugins::Config.
    class SecretFinder
      # Special value for the :secret option that triggers a preset lookup
      PRESET_MAGIC = 'PRESET'

      # @param options [Parser]       CLI options manager (provides :secret)
      # @param presets [PresetManager] preset resolver (provides #lookup_preset)
      def initialize(options, presets)
        @options = options
        @presets = presets
      end

      # Return the secret for the given URL + username.
      # If the :secret option equals 'PRESET', the preset store is searched for a
      # matching url/username entry and its 'password' field is returned.
      # @param url      [String]
      # @param username [String]
      # @return [String, nil]
      def lookup(url:, username:)
        secret = @options.get_option(:secret)
        if secret.eql?(PRESET_MAGIC)
          conf = @presets.lookup_preset(url: url, username: username)
          if conf.is_a?(Hash)
            Log.log.debug{"Found preset #{conf} with URL and username"}
            secret = conf['password']
          end
        end
        secret
      end
    end
  end
end
