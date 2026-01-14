# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/uri_reader'
require_relative 'build_tools'

# Fixed paths in project
module TestEnv
  ENV_VAR_REF_CONF = 'ASPERA_CLI_TEST_CONF_FILE'

  # Load the full test configuration from file or other (e.g. vault)
  # @return [Hash] Full test configuration parameters
  def test_configuration
    return @test_configuration if defined?(@test_configuration)
    Aspera.assert(ENV.key?(ENV_VAR_REF_CONF), "Missing env var: #{ENV_VAR_REF_CONF}", type: :warn)
    @test_configuration =
      if ENV.key?(ENV_VAR_REF_CONF)
        BuildTools.yaml_safe_load(Aspera::UriReader.read("file:///#{ENV[ENV_VAR_REF_CONF]}"))
      else
        {}
      end.freeze
  end

  module_function :test_configuration
end
