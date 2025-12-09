# frozen_string_literal: true

# Rakefile
require 'rake'
require 'uri'
require 'zlib'
require 'fileutils'
require 'aspera/environment'
require_relative '../package/build_tools'
require_relative '../package/paths'

include Paths
include BuildTools

PATH_CONF_FILE = config_file_path

PATH_TESTS_STATES = TMP / 'state.yml'

# override $HOME/.aspera/ascli
PATH_CLI_HOME = TMP / "#{Aspera::Cli::Info::CMD_NAME}_home"
PATH_CLI_CMD = BIN / Aspera::Cli::Info::CMD_NAME

# -----------------
# Used in tests.yml
CONF_DATA = yaml_safe_load(PATH_CONF_FILE.read)
PATH_VERSION_CHECK_PERSIST = PATH_CLI_HOME / 'persist_store/version_last_check.txt'
# package title for faspex and aoc
PACKAGE_TITLE_BASE = Time.now.to_s
# testing file generated locally (special shell characters must be escaped for shell, special makefile characters escaped)
PATH_TST_ASC_LCL = TMP / CONF_DATA['file']['asc_name']
# default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
PATH_DOWN_TST_ASC = Pathname.new(Dir.home) / 'Downloads' / CONF_DATA['file']['asc_name']
# This file name contains special characters, it must be quoted when used in shell
PATH_TST_UTF_LCL = TMP / CONF_DATA['file']['utf_name']
# a medium sized file for testing
TST_MED_FILENAME = CONF_DATA['file']['utf_name']
# needs to be quoted, as there is shell special character: "?"
TST_MED_LCL_PATH = "faux:///#{URI.encode_www_form_component(TST_MED_FILENAME)}?100m"
TEMPORIZE_CREATE = 10
TEMPORIZE_FILE = 30
# sync dir must be an absolute path, but tmp dir may not exist yet, while its enclosing folder should exist
TMP_SYNCS = TMP / 'syncs'
PATH_SHARES_SYNC = TMP_SYNCS / 'shares_sync'
PATH_TST_LCL_FOLDER = TMP_SYNCS / 'sendfolder'
PATH_VAULT_FILE = TOP / 'tmp/sample_vault.bin'
NEW_VAULT_PASS = 'my_other_pass_here'
PKCS_P = 'YourExportPassword'
PATH_FILE_LIST = TMP / 'filelist.txt'
PATH_FILE_PAIR_LIST = TMP / 'file_pair_list.txt'
# ------------------

# give waring and stop on first warning in this gem code
CMD_FAIL_WARN = ['ruby', '-w', TST / 'warning_exit_wrapper.rb']
# CLI with default config file
CLI_NOCONF = CMD_FAIL_WARN + [PATH_CLI_CMD, "--home=#{PATH_CLI_HOME}"]
# "CLI_TEST" is used to call the tool in the testing environment
CLI_TEST = CLI_NOCONF + ["--config-file=#{PATH_CONF_FILE}"]
# JRuby does not support some encryptions
CLI_TEST.push('-Pjns') if defined?(JRUBY_VERSION)
# temp configuration file that is modified, to avoid changing the main configuration file
PATH_TEST_CONFIG = TMP / 'sample.conf'
# "CLI_TMP_CONF" is used for commands that modify the config file
CLI_TMP_CONF = CLI_NOCONF + ["--config-file=#{PATH_TEST_CONFIG}"]
# Folder where test case states (generated files) are stored
PATH_TMP_STATES = TMP / 'states'
# Test states to not re-execute
SKIP_STATES = %w[passed skipped].freeze
# Rake namespace for all test cases
TEST_CASE_NS = :case

TMP.mkpath
FileUtils.cp(PATH_CONF_FILE, PATH_TEST_CONFIG) unless PATH_TEST_CONFIG.exist?
PATH_TST_ASC_LCL.write('This is a small test file') unless  PATH_TST_ASC_LCL.exist?
PATH_TST_UTF_LCL.write('This is a small test file') unless  PATH_TST_UTF_LCL.exist?
PATH_FILE_LIST.write(PATH_TST_ASC_LCL.to_s)
# @preset:server.inside_folder@/other_name
PATH_FILE_PAIR_LIST.write([
  PATH_TST_ASC_LCL,
  File.join(CONF_DATA['server']['inside_folder'], 'other_name')
].map(&:to_s).join("\n"))
PATH_SHARES_SYNC.mkpath
PATH_TMP_STATES.mkpath
(PATH_SHARES_SYNC / 'sample_file.txt').write('Some sample file')
(PATH_TST_LCL_FOLDER / 'sub').mkpath
%w[1 2 3 sub/1 sub/2].each do |f|
  (PATH_TST_LCL_FOLDER / f).write('Some sample file')
end
TEST_DEFS = yaml_safe_load(PATH_TEST_DEFS.read)
ALLOWED_KEYS = %w{command tags depends_on description pre post env $comment stdin expect}
unsupported_keys = TEST_DEFS.values.map(&:keys).flatten.uniq - ALLOWED_KEYS
raise "Unsupported keys: #{unsupported_keys}" unless unsupported_keys.empty?
state = PATH_TESTS_STATES.exist? ? YAML.load_file(PATH_TESTS_STATES) : {}

def save_state(state)
  File.write(PATH_TESTS_STATES, state.to_yaml)
end

def eval_macro(value)
  # value.gsub(/\$\((.*?)\)/) do
  value.gsub(/\$\((?<inner>(?:[^()]+|\((?:[^()]+|\g<inner>)*\))*)\)/) do
    Aspera::Environment.secure_eval(Regexp.last_match(1), __FILE__, __LINE__).to_s
  end
  # puts "Eval: #{value} -> [#{x}]"
end

# @return the Pathname to pid file generated for the given test case
def pid_file(name)
  PATH_TMP_STATES / "#{name}.pid"
end

# @return the Pathname to output file generated for the given test case
def out_file(name)
  PATH_TMP_STATES / "#{name}.out"
end

# Read the value generated in output for the given test case
def read_value_from(name)
  state_file = out_file(name)
  value = state_file.read.chomp
  puts("Read: #{state_file}: #{value}")
  value
end

# Terminates the process of previous test case
def stop_process(name)
  pid = pid_file(name).read.to_i
  Process.kill('TERM', pid)
  Process.wait(pid)
end

def check_process(name)
  pid = pid_file(name).read.to_i
  r = Process.kill(0, pid)
  puts("Kill 0 : #{r}")
end

namespace :test do
  # List tests with metadata
  desc 'List all tests with tags'
  task :list do
    TEST_DEFS.each do |name, info|
      puts "#{name.ljust(20)} #{info['tags']&.join(', ')}"
    end
  end

  desc 'Skip a given test by name'
  task :skip do
    ENV['T'].split(',').each do |k|
      state[k] = 'skipped'
      puts "[SKIP] #{k}"
    end
    save_state(state)
  end

  desc 'Clear a given test by name'
  task :clear do
    ENV['T'].split(',').each{ |k| state.delete(k)}
    save_state(state)
    puts "[CLEAR] #{ENV['T']}"
  end

  # Reset persistent state
  desc 'Clear all stored test results'
  task :reset do
    PATH_TESTS_STATES.delete if PATH_TESTS_STATES.exist?
    PATH_TEST_CONFIG.delete if PATH_TEST_CONFIG.exist?
    puts 'State cleared.'
  end

  # Run tests filtered by tag
  desc 'Run only tests matching tag'
  task :tags, [:tag] do |_, args|
    tag = args[:tag]
    abort 'Usage: rake test:tags[download]' unless tag

    selected = TEST_DEFS.select{ |_, info| info['tags']&.include?(tag)}
    Rake::Task['test:run'].invoke if selected.empty?

    selected.each_key do |name|
      Rake::Task["test:#{name}"].invoke
    end
  end
  # Run all tests in declared order
  desc 'Run all tests'
  task :all do
    TEST_DEFS.each_key{ |name| Rake::Task["#{TEST_CASE_NS}:#{name}"].invoke}
  end
end

namespace TEST_CASE_NS do
  # Create a Rake task for each test
  TEST_DEFS.each do |name, info|
    # puts "-> #{name}"
    desc info['description'] || '-'

    deps = info['depends_on'] || []
    Aspera.assert_array_all(deps, String)
    task name => deps.map{ |d| "#{TEST_CASE_NS}:#{d}"} do
      if SKIP_STATES.include?(state[name]) && !ENV['FORCE']
        # puts "[SKIP] #{name}"
        next
      end
      puts "[RUN]  #{name}: #{info['command']&.join(' ')}"
      info['pre']&.each do |cmd|
        cmd = eval_macro(cmd)
        puts("Executing: #{cmd}")
        Aspera::Environment.secure_eval(cmd, __FILE__, __LINE__)
      end
      must_fail = info['tags']&.include?('must_fail')
      hide_fail = info['tags']&.include?('hide_fail')
      ignore_fail = info['tags']&.include?('ignore_fail')
      save_output = info['tags']&.include?('save_output') || info['expect']
      wait_non_empty_output = info['tags']&.include?('wait_non_empty_output')
      tmp_conf = info['tags']&.include?('tmp_conf')
      if info['command'].include?('wizard')
        info['env'] ||= {}
        info['env']['ASCLI_WIZ_TEST'] = 'yes'
      end
      loop do
        full_args = CLI_TEST
        full_args = CLI_TMP_CONF if info['command'][0..1].eql?(%w[config wizard]) || tmp_conf
        full_args += info['command'].map{ |i| eval_macro(i.to_s)}
        full_args += ["--output=#{out_file(name)}"] if save_output
        kwargs = {}
        if info['tags']&.include?('noblock')
          kwargs['background'] = true
          full_args.push("--pid-file=#{pid_file(name)}")
        end
        if info['stdin']
          stdinfile = TMP / "#{name}.stdin"
          input = eval_macro(info['stdin'])
          stdinfile.write(input)
          kwargs[:in] = stdinfile.to_s
          puts("Input: #{input}")
        end
        run(*full_args, env: info['env'], **kwargs)
        info['post']&.each do |cmd|
          puts("Executing: #{cmd}")
          Aspera::Environment.secure_eval(cmd, __FILE__, __LINE__)
        end
        puts("Saved: #{out_file(name).read}") if save_output
        next if wait_non_empty_output && out_file(name).empty?
        if info['expect']
          raise "not match[#{info['expect']}][#{out_file(name).read}]" unless info['expect'].eql?(out_file(name).read.chomp)
        end
        state[name] = 'passed'
        raise 'Must fail' if must_fail
        puts "[OK]   #{name}"
        break
      rescue RuntimeError
        puts "[FAIL] #{name}"
        state[name] = 'failed'
        if must_fail || hide_fail || ignore_fail
          state[name] = 'passed'
        else
          raise
        end
        save_state(state)
        break
      end
      save_state(state)
    end
  end
end

# default: run all tests
# task default: 'test:run'

# TODO: separately in rake task
# asession:
#	set -x&&\
#	remote_host=$$( config preset get server_user url)&&\
#	remote_host=$${remote_host#*://}&&\
#	remote_port=$${remote_host#*:}&&\
#	remote_host=$${remote_host%:*}&&\
#	remote_user=$$( config preset get server_user username)&&\
#	remote_pass=$$( config preset get server_user password)&&\
#	$(DIR_BIN)asession @json:@extend:{"loglevel":"info","spec":{"remote_host":"'"$${remote_host}"'","remote_user":"'"$${remote_user}"'","ssh_port":'$${remote_port}',"remote_password":"'"$${remote_pass}"'","direction":"receive","destination_root":"$(TMP)","resume_policy":"none","paths":[{"source":"/aspera-test-dir-large/100MB"}]}}
