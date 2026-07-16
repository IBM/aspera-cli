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
  ALLOWED_KEYS = %i{command args tags depends_on description pre post env $comment stdin expect template instanciate vars}.freeze

  # Execution context for a running test case, injected as `t` in every eval binding.
  #
  # Holds the current test's full name and its optional instance prefix (set when the
  # test was generated from a template instantiation, e.g. `aoc_test` → `aocwa_user_suite`).
  #
  # All file-based helpers operate on test-case names → state files under PATH_TMP_STATES.
  # When called without argument they target the current test; when called with a bare
  # sibling name from `tests.yml` they qualify it with the instance prefix first:
  #
  #   t.out_file                        # PATH_TMP_STATES/aoc_test.current_test.out
  #   t.out_file('other_test')          # PATH_TMP_STATES/aoc_test.other_test.out
  #   t.saved_output('other_test')   # reads  aoc_test.other_test.out
  #   t.stop_process('background')      # kills  aoc_test.background
  class Context
    # @param name   [String] fully-qualified name of the current test case
    # @param prefix [String, nil] instance prefix for cross-references, or nil
    def initialize(name, prefix)
      @name   = name
      @prefix = prefix
    end

    # Resolve a test-case name to its fully-qualified form.
    # When called without argument (nil sentinel), returns the current test name unchanged.
    # When called with a bare sibling name from tests.yml, prepends the instance prefix.
    # @param name [String, Symbol, nil] bare sibling name, or nil to mean the current test
    # @return [String] fully-qualified test-case name
    def resolve(name)
      return @name if name.nil?
      @prefix ? "#{@prefix}.#{name}" : name.to_s
    end

    # @return [Pathname] .out file for the current test (no arg) or a named sibling
    def out_file(name = nil)
      PATH_TMP_STATES / "#{resolve(name)}.out"
    end

    # @return [Pathname] .err file for the current test (no arg) or a named sibling
    def err_file(name = nil)
      PATH_TMP_STATES / "#{resolve(name)}.err"
    end

    # @return [Pathname] .pid file for the current test (no arg) or a named sibling
    def pid_file(name = nil)
      PATH_TMP_STATES / "#{resolve(name)}.pid"
    end

    # @return [Integer] PID stored by a `noblock` test case
    def pid_of_test(name = nil)
      pid_file(name).read.to_i
    end

    # Read the value saved by a `save_output` test case
    def saved_output(name = nil)
      state_file = out_file(name)
      value = state_file.read.chomp
      Aspera::Log.instance.logger.info("Read: #{state_file}: #{value}")
      value
    end

    # Terminate the process started by a `noblock` test case
    def stop_process(name = nil)
      Aspera::Log.instance.logger.info("Stopping process for test case: #{resolve(name)}")
      pid = pid_of_test(name)
      Process.kill('TERM', pid)
      _, status = Process.waitpid2(pid)
      Aspera::Log.instance.logger.info("Status: #{status}")
    rescue Errno::ECHILD
      nil
    end

    # Check that the process started by a `noblock` test case is still running
    def check_process(name = nil)
      pid = pid_of_test(name)
      r = Process.kill(0, pid)
      Aspera::Log.instance.logger.info("Kill 0 : #{r}")
    end
  end
  # Regular expression pattern that plugin names must match (lowercase alphanumeric and underscores only)
  PLUGIN_NAME_PATTERN = /\A[a-z0-9_]+\z/

  # Load the full test configuration parameters (servers, credentials) from file or other source (e.g. vault)
  # Configuration is loaded from the URL specified in ENV_VAR_REF_CONF environment variable
  # Results are memoized and frozen to prevent accidental modification
  # @return [Hash] Full test configuration parameters (frozen)
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

  # Normalize one raw test definition loaded from [`tests.yml`](tests/tests.yml).
  #
  # This step validates supported keys and applies per-definition defaults, but it
  # intentionally does not derive the plugin tag from the first command yet.
  # Plugin/tag derivation is deferred until after template instantiation in
  # [`descriptions()`](build/lib/test_env.rb:60).
  #
  # @param name [String] Test definition name as found in the YAML file
  # @param properties [Hash] Mutable raw test definition properties
  # @return [Hash] The normalized properties hash
  def normalize_test(name, properties)
    properties.symbolize_keys!
    unsupported_keys = properties.keys - ALLOWED_KEYS
    raise "Unsupported key(s): #{unsupported_keys} in #{name}" unless unsupported_keys.empty?
    properties[:command] = Aspera::Cli::Info::CMD_NAME unless properties.key?(:command)
    properties[:args] ||= []
    properties[:tags] ||= []
    properties[:tags].map!(&:to_sym)
    properties[:tags].push(:ats) if properties[:args].include?('ats') && !properties[:tags].include?(:ats)
    if properties[:args].include?('wizard')
      properties[:env] ||= {}
      properties[:env]['ASCLI_WIZ_TEST'] = 'yes'
    end
    properties
  end

  # Load test definitions, expand template instances, and finalize derived tags.
  #
  # Loading is performed in three steps:
  # - normalize each raw YAML entry
  # - keep template members and template instances in separate hashes
  # - build executable tests named `<instance>.<template>` for each instantiated template
  #
  # Templates and instance declarations are not returned as executable tests.
  # Only the generated tests and regular tests are included in the final result.
  #
  # @return [Hash{String=>Hash}] Executable test definitions indexed by final test name
  def descriptions
    tests = Aspera::Yaml.safe_load(Paths::TEST_DEFS.read)
    templates = {}
    instances = {}
    normalized_tests = {}
    tests.each do |name, properties|
      normalize_test(name, properties)
      if properties.key?(:template)
        templates[properties[:template]] ||= {}
        templates[properties[:template]][name] = properties
      elsif properties.key?(:instanciate)
        instances[name] = properties
      else
        normalized_tests[name] = properties
      end
    end
    instances.each do |instance_name, instance_properties|
      template_name = instance_properties[:instanciate]
      raise "Unknown template suite: #{template_name} in #{instance_name}" unless templates.key?(template_name)
      template_names = templates[template_name].keys
      templates[template_name].each do |template_test_name, template_properties|
        test_name = "#{instance_name}.#{template_test_name}"
        generated_properties = Marshal.load(Marshal.dump(template_properties))
        generated_properties.delete(:template)
        generated_properties.delete(:instanciate)
        generated_properties[:tags].unshift(instance_name.to_sym) unless generated_properties[:tags].include?(instance_name.to_sym)
        generated_properties[:args] = instance_properties[:args] + generated_properties[:args]
        generated_properties[:vars] = instance_properties[:vars] if instance_properties.key?(:vars)
        if generated_properties.key?(:depends_on)
          generated_properties[:depends_on] = generated_properties[:depends_on].map do |dependency|
            template_names.include?(dependency) ? "#{instance_name}.#{dependency}" : dependency
          end
        end
        generated_properties[:instance_prefix] = instance_name
        normalized_tests[test_name] = generated_properties
      end
    end
    normalized_tests.each_value do |properties|
      plugin_sym = properties[:args].find{ |s| !s.start_with?('-', '@')}&.to_sym
      raise "Plugin name must match #{PLUGIN_NAME_PATTERN}: #{plugin_sym}" unless plugin_sym.nil? || plugin_sym.to_s.match?(PLUGIN_NAME_PATTERN)
      properties[:plugin] = plugin_sym unless plugin_sym.nil?
      properties[:tags].unshift(plugin_sym) unless plugin_sym.nil? || properties[:tags].include?(plugin_sym)
    end
    normalized_tests
  end
  module_function :configuration, :normalize_test, :descriptions
end
