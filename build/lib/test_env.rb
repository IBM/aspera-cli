# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/uri_reader'
require 'aspera/yaml'

# Fixed paths in project
module TestEnv
  ENV_VAR_REF_CONF = 'ASPERA_CLI_TEST_CONF_URL'

  # Load the full test configuration from file or other (e.g. vault)
  # @return [Hash] Full test configuration parameters
  def configuration
    return @configuration if defined?(@configuration)
    Aspera.assert(ENV.key?(ENV_VAR_REF_CONF), "Missing env var: #{ENV_VAR_REF_CONF}", type: :warn)
    @configuration =
      if ENV.key?(ENV_VAR_REF_CONF)
        Aspera::Yaml.safe_load(Aspera::UriReader.read(ENV[ENV_VAR_REF_CONF]))
      else
        {}
      end.freeze
  end
  # Allowed keys in test defs: See tests/README.md
  ALLOWED_KEYS = %i{command args tags depends_on description pre post env $comment stdin expect}.freeze

  # Read and normalize test definitions from TEST_DEFS file
  # @return [Hash{Symbol=>Hash}] Test definitions
  def descriptions
    tests = Aspera::Yaml.safe_load(TEST_DEFS.read)
    # Normalize test definitions
    tests.each do |name, properties|
      properties.symbolize_keys!
      unsupported_keys = properties.keys - ALLOWED_KEYS
      raise "Unsupported key(s): #{unsupported_keys} in #{name}" unless unsupported_keys.empty?
      properties[:command] = Aspera::Cli::Info::CMD_NAME unless properties.key?(:command)
      properties[:args] ||= []
      plugin = properties[:args].find{ |s| !s.start_with?('-', '@')}
      raise "Wrong plugin name: #{plugin}" unless plugin.nil? || plugin.match?(/^[a-z0-9_]+$/)
      properties[:plugin] = plugin unless plugin.nil?
      properties[:tags] ||= []
      properties[:tags].unshift(plugin) unless plugin.nil? || properties[:tags].include?(plugin)
      if properties[:args].include?('wizard')
        properties[:env] ||= {}
        properties[:env]['ASCLI_WIZ_TEST'] = 'yes'
      end
    end
    tests
  end
  module_function :configuration, :descriptions
end
