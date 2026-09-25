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
  # Allowed keys in test definitions (regular tests and template members, without `template`): See tests/README.md for detailed documentation
  ALLOWED_KEYS = %i{command args tags depends_on description pre post env $comment stdin expect vars}.freeze
  # Allowed keys in template instance definitions (entries with `instantiate`)
  INSTANCE_KEYS = %i{instantiate args tags vars description $comment}.freeze

  # Execution context for a running test case, injected as `t` in every eval binding.
  #
  # Holds the current test's full name and, for a test generated from a template instance,
  # the instance name and the names of the template members (siblings).
  #
  # All file-based helpers operate on test-case names → state files under PATH_TMP_STATES.
  # When called without argument they target the current test; when called with the name
  # of a sibling template member, they qualify it with the instance name. Other names are
  # used unchanged:
  #
  #   t.out_file                        # PATH_TMP_STATES/aoc_user_suite.current_test.out
  #   t.out_file('sibling_test')        # PATH_TMP_STATES/aoc_user_suite.sibling_test.out
  #   t.saved_output('sibling_test')    # reads  aoc_user_suite.sibling_test.out
  #   t.saved_output('regular_test')    # reads  regular_test.out
  #   t.stop_process('background')      # kills  aoc_user_suite.background (if sibling)
  class Context
    # @param name     [String] fully-qualified name of the current test case
    # @param prefix   [String, nil] instance name for cross-references, or nil
    # @param siblings [Array<String>] names of template members qualified with prefix
    def initialize(name, prefix = nil, siblings = [])
      @name     = name
      @prefix   = prefix
      @siblings = siblings
    end

    # Resolve a test-case name to its fully-qualified form.
    # When called without argument (nil sentinel), returns the current test name unchanged.
    # When called with a sibling template member name, prepends the instance name.
    # @param name [String, Symbol, nil] test name, or nil to mean the current test
    # @return [String] fully-qualified test-case name
    def resolve(name)
      return @name if name.nil?
      name = name.to_s
      @siblings.include?(name) ? "#{@prefix}.#{name}" : name
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
  # Plugin/tag derivation is done on all tests in [`descriptions()`](build/lib/test_env.rb).
  # Template members are normalized once instantiated, i.e. with the instance arguments.
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

  # Generate the tests of one template instance.
  #
  # Each member of the template gives a test `<instance>.<member>`, with the instance
  # arguments prepended, the instance name and tags added, and the instance vars merged.
  # References to sibling members in `depends_on` are qualified with the instance name.
  #
  # @param instance_name [String] Name of the `instantiate` entry
  # @param instance [Hash] Properties of the `instantiate` entry
  # @param templates [Hash{String=>Hash{String=>Hash}}] Template members by template name
  # @return [Hash{String=>Hash}] Generated test definitions indexed by test name
  def instantiate(instance_name, instance, templates)
    unsupported_keys = instance.keys - INSTANCE_KEYS
    raise "Unsupported key(s): #{unsupported_keys} in #{instance_name}" unless unsupported_keys.empty?
    members = templates.fetch(instance[:instantiate]) { raise "Unknown template: #{instance[:instantiate]} in #{instance_name}" }
    siblings = members.keys
    members.to_h do |member_name, member|
      test_name = "#{instance_name}.#{member_name}"
      context = Context.new(test_name, instance_name, siblings)
      properties = Marshal.load(Marshal.dump(member))
      properties[:args] = (instance[:args] || []) + (properties[:args] || [])
      properties[:tags] = [instance_name, *properties[:tags], *instance[:tags]].map(&:to_sym).uniq
      properties[:vars] = (properties[:vars] || {}).merge(instance[:vars]) if instance.key?(:vars)
      properties[:depends_on] = properties[:depends_on].map { |dependency| context.resolve(dependency) } if properties.key?(:depends_on)
      normalize_test(test_name, properties)
      properties[:instance_prefix] = instance_name
      properties[:siblings] = siblings
      [test_name, properties]
    end
  end

  # Load test definitions, expand template instances, and finalize derived tags.
  #
  # An entry with `template` is a member of that template and is not executable by itself.
  # An entry with `instantiate` is replaced, at its position, by the tests generated from
  # the members of that template. So execution order is the order of `tests.yml`.
  #
  # @return [Hash{String=>Hash}] Executable test definitions indexed by final test name
  def descriptions
    entries = Aspera::Yaml.safe_load(Paths::TEST_DEFS.read).transform_values(&:symbolize_keys)
    templates = {}
    entries.each do |name, properties|
      next unless properties.key?(:template)
      raise "Template member cannot instantiate a template: #{name}" if properties.key?(:instantiate)
      (templates[properties[:template]] ||= {})[name] = properties.except(:template)
    end
    unused = templates.keys - entries.values.filter_map { |properties| properties[:instantiate] }
    raise "Template(s) never instantiated: #{unused.join(', ')}" unless unused.empty?
    tests = {}
    entries.each do |name, properties|
      next if properties.key?(:template)
      if properties.key?(:instantiate)
        tests.merge!(instantiate(name, properties, templates))
      else
        tests[name] = normalize_test(name, properties)
      end
    end
    tests.each_value do |properties|
      plugin_sym = properties[:args].find { |s| !s.start_with?('-', '@') }&.to_sym
      raise "Plugin name must match #{PLUGIN_NAME_PATTERN}: #{plugin_sym}" unless plugin_sym.nil? || plugin_sym.to_s.match?(PLUGIN_NAME_PATTERN)
      properties[:plugin] = plugin_sym unless plugin_sym.nil?
      properties[:tags].unshift(plugin_sym) unless plugin_sym.nil? || properties[:tags].include?(plugin_sym)
    end
    tests
  end
  module_function :configuration, :normalize_test, :instantiate, :descriptions
end
