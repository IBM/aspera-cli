# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/uri_reader'
require 'aspera/yaml'
require_relative 'paths'

# Test environment configuration and test definition management
# Provides utilities to load test configuration (servers, credentials) and parse test definitions
module TestEnv
  # Environment variable name that contains the URL to fetch test configuration
  # The configuration typically includes server URLs, credentials, and other test parameters
  ENV_VAR_REF_CONF = 'ASPERA_CLI_TEST_CONF_URL'
  # Allowed keys in test definitions: See tests/README.md for detailed documentation
  ALLOWED_KEYS = %i{command args tags depends_on description pre post env $comment stdin expect}.freeze
  # Regular expression pattern that plugin names must match (lowercase alphanumeric and underscores only)
  PLUGIN_NAME_PATTERN = /\A[a-z0-9_]+\z/

  # Load the full test configuration parameters (servers, credentials) from file or other source (e.g. vault)
  # Configuration is loaded from the URL specified in ENV_VAR_REF_CONF environment variable
  # Results are memoized and frozen to prevent accidental modification
  # @return [Hash] Full test configuration parameters (frozen)
  def configuration
    return @configuration if defined?(@configuration)
    # Warn if environment variable is not set (but continue with empty config)
    Aspera.assert(ENV.key?(ENV_VAR_REF_CONF), "Missing env var: #{ENV_VAR_REF_CONF}", type: :warn)
    @configuration =
      if ENV.key?(ENV_VAR_REF_CONF)
        # Load YAML configuration from the URL specified in environment variable
        Aspera::Yaml.safe_load(Aspera::UriReader.read(ENV[ENV_VAR_REF_CONF]))
      else
        # Return empty hash if no configuration URL is provided
        {}
      end.freeze
  end

  # Read and normalize test definitions from tests.yml
  # Normalization includes: converting keys to symbols, validating allowed keys, setting defaults,
  # extracting plugin names from arguments, and managing tags
  # @return [Hash{Symbol=>Hash}] Test definitions with normalized structure
  def descriptions
    tests = Aspera::Yaml.safe_load(Paths::TEST_DEFS.read)
    # Normalize each test definition: validate, set defaults, and enrich with derived properties
    tests.each do |name, properties|
      properties.symbolize_keys!
      unsupported_keys = properties.keys - ALLOWED_KEYS
      raise "Unsupported key(s): #{unsupported_keys} in #{name}" unless unsupported_keys.empty?
      properties[:command] = Aspera::Cli::Info::CMD_NAME unless properties.key?(:command)
      properties[:args] ||= []
      plugin_sym = properties[:args].find{ |s| !s.start_with?('-', '@')}&.to_sym
      raise "Plugin name must match #{PLUGIN_NAME_PATTERN}: #{plugin_sym}" unless plugin_sym.nil? || plugin_sym.to_s.match?(PLUGIN_NAME_PATTERN)
      properties[:plugin] = plugin_sym unless plugin_sym.nil?
      properties[:tags] ||= []
      properties[:tags].map!(&:to_sym)
      properties[:tags].unshift(plugin_sym) unless plugin_sym.nil? || properties[:tags].include?(plugin_sym)
      properties[:tags].push(:ats) if properties[:args].include?('ats') && !properties[:tags].include?(:ats)
      if properties[:args].include?('wizard')
        properties[:env] ||= {}
        properties[:env]['ASCLI_WIZ_TEST'] = 'yes'
      end
    end
    tests
  end
  module_function :configuration, :descriptions
end
