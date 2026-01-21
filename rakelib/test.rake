# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/rest'
require 'aspera/log'
require 'aspera/hash_ext'
require 'rake'
require 'uri'
require 'zlib'
require 'etc'
require 'fileutils'
require 'securerandom'
require 'yaml'
require_relative '../build/lib/build_tools'
require_relative '../build/lib/paths'
require_relative '../build/lib/test_env'
# spec tests (only if rspec is available)
begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new
rescue LoadError
  # rspec not available (e.g., in production/deploy environment)
end

include Paths
include BuildTools

CLOBBER.push(Paths::GEMFILE_LOCK)

# -----------------
# Used in tests.yml
# override $HOME/.aspera/ascli
PATH_CLI_HOME = TMP / "#{Aspera::Cli::Info::CMD_NAME}_home"
PATH_VERSION_CHECK_PERSIST = PATH_CLI_HOME / 'persist_store/version_last_check.txt'
# Package title for faspex and aoc
PACKAGE_TITLE_BASE = Time.now.to_s
FILENAME_ASCII = 'data_file.bin'
# A medium sized file for testing
FILENAME_UNICODE = "\u{1242B}spécial{#\u{1F600}تツ"
# Testing file generated locally
PATH_TST_ASC_LCL = TMP / FILENAME_ASCII
# Default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
PATH_WEB_DOWNLOAD = Pathname.new(Dir.home) / 'Downloads'
PATH_DOWN_TST_ASC = PATH_WEB_DOWNLOAD / FILENAME_ASCII
# This file name contains special characters, it must be quoted when used in shell
PATH_TST_UTF_LCL = TMP / FILENAME_UNICODE
# local path, using `faux:`
PATH_TST_LCL_FILE = "faux:///#{URI.encode_www_form_component(FILENAME_UNICODE)}?100m"
# sync dir must be an absolute path, but tmp dir may not exist yet, while its enclosing folder shall exist
PATH_TMP_SYNCS = TMP / 'syncs'
PATH_SHARES_SYNC = PATH_TMP_SYNCS / 'shares_sync'
PATH_TST_LCL_FOLDER = PATH_TMP_SYNCS / 'sendfolder'
PATH_VAULT_FILE = TMP / 'sample_vault.bin'
PATH_FILE_LIST = TMP / 'file_list.txt'
PATH_FILE_PAIR_LIST2 = TMP / 'file_pair_list.txt'
PATH_HOT_FOLDER = TMP / 'source_hot'
PATH_SCRIPTS = TST
PKCS_P = 'YourExportPassword'
TEMPORIZE_CREATE = 10
TEMPORIZE_FILE = 30
# ------------------

# give warning and stop on first warning in this gem
RUBY_WRAPPER = ['ruby', '-w', TST / 'warning_exit_wrapper.rb'].freeze
# Copy of the main configuration file to be used in tests
PATH_CONF_FILE = PATH_CLI_HOME / 'config.yaml'
# Temp configuration file that is modified, to avoid changing the main configuration file
PATH_TEST_CONFIG = TMP / 'test_config.yaml'
# Folder where test case states (generated files) are stored
PATH_TMP_STATES = TMP / 'states'
# Test states to not re-execute
SKIP_STATES = %w[passed skipped].freeze
# Rake namespace for all test cases
TEST_CASE_NS = :case

# Init folders and files
TMP.mkpath
PATH_CLI_HOME.mkpath
PATH_TST_ASC_LCL.write('This is a small test file') unless PATH_TST_ASC_LCL.exist?
PATH_TST_UTF_LCL.write('This is a small test file') unless PATH_TST_UTF_LCL.exist?
PATH_FILE_LIST.write(PATH_TST_ASC_LCL.to_s)
PATH_SHARES_SYNC.mkpath
PATH_TMP_STATES.mkpath
(PATH_SHARES_SYNC / 'sample_file.txt').write('Some sample file')
(PATH_TST_LCL_FOLDER / 'sub').mkpath
%w[1 2 3 sub/1 sub/2].each do |f|
  (PATH_TST_LCL_FOLDER / f).write('Some sample file')
end
ALL_TESTS = read_test_definitions

# tests state is saved here
PATH_TESTS_STATES = TMP / 'state.yml'
STATES = PATH_TESTS_STATES.exist? ? YAML.load_file(PATH_TESTS_STATES) : {}

# tags that have special meaning
SPECIAL_TAGS = %w[ignore_fail must_fail hide_fail save_output wait_value tmp_conf noblock].freeze

def path_file_pair_list
  PATH_FILE_PAIR_LIST2.write([
    PATH_TST_ASC_LCL,
    File.join(conf_data('server.inside_folder'), 'other_name')
  ].map(&:to_s).join("\n")) unless PATH_FILE_PAIR_LIST2.exist?
  PATH_FILE_PAIR_LIST2
end

def save_state
  File.write(PATH_TESTS_STATES, STATES.to_yaml)
end

# Retrieve test environment config parameters
# @param path [String] Dot-separated path in config
# @return [Object] Value found at given path
def conf_data(path)
  @param_config_cache = TestEnv.test_configuration if @param_config_cache.nil?
  current = @param_config_cache
  path.split('.').each do |k|
    current = current[k]
    raise "Missing config: #{k} for #{path}" if current.nil?
  end
  current
end

def eval_macro(value, user_binding)
  # value.gsub(/\$\((.*?)\)/) do
  value.gsub(/\$\((?<inner>(?:[^()]+|\((?:[^()]+|\g<inner>)*\))*)\)/) do
    Aspera::Environment.secure_eval(Regexp.last_match(1), __FILE__, __LINE__, user_binding).to_s
  end
  # log.info "Eval: #{value} -> [#{x}]"
end

# @return the Pathname to pid file generated for the given test case
def pid_file(name)
  PATH_TMP_STATES / "#{name}.pid"
end

def pid_of_test(name)
  pid_file(name).read.to_i
end

# @return the Pathname to output file generated for the given test case
def out_file(name)
  PATH_TMP_STATES / "#{name}.out"
end

def err_file(name)
  PATH_TMP_STATES / "#{name}.err"
end

# Read the value generated in output for the given test case
def read_value_from(name)
  state_file = out_file(name)
  value = state_file.read.chomp
  log.info("Read: #{state_file}: #{value}")
  value
end

# Terminates the process of previous test case
def stop_process(name)
  log.info("Stopping process for test case: #{name}")
  pid = pid_of_test(name)
  Process.kill('TERM', pid)
  _, status = Process.waitpid2(pid)
  log.info("Status: #{status}")
rescue Errno::ECHILD
  # ignore if process was started by another instance
  nil
end

def check_process(name)
  pid = pid_of_test(name)
  r = Process.kill(0, pid)
  log.info("Kill 0 : #{r}")
end

# @param pathname [Pathname] Folder
def ls_l(pathname)
  puts pathname.children.map{ |p| format('%10d %s %s', p.lstat.size, p.lstat.mtime.strftime('%b %e %H:%M'), p.basename)}
end

ASPERA_LOG_PATH = '/Library/Logs/Aspera'
ASPERA_DAEMON_USER = 'asperadaemon'

# on macOS activate sshd, restore Log folder owner and restart noded
def reset_macos_hsts
  result = run(*%w[sudo systemsetup -getremotelogin], capture: true)
  run(*%w[sudo systemsetup -setremotelogin on]) if result.include?('Off')
  run(*%w[sudo systemsetup -getremotelogin])
  st = File.stat(ASPERA_LOG_PATH)
  owner = Etc.getpwuid(st.uid).name
  run(*%W[sudo chown -R #{ASPERA_DAEMON_USER}: #{ASPERA_LOG_PATH}]) if owner != ASPERA_DAEMON_USER
  restart_noded
  # while ! $(CLI_COMMAND) node -N -Ptst_node_preview info;do echo waiting..;sleep 2;done
end

MACOS_LAUNCHD_UNLOAD = %w[sudo launchctl unload]
MACOS_LAUNCHD_LOAD = %w[sudo launchctl load]
MACOS_LAUNCHD_FOLDERS = Pathname.new('/Library/LaunchDaemons')

def macos_service(action, aspera_name)
  run(*(%w[sudo launchctl] + [action, MACOS_LAUNCHD_FOLDERS / "com.aspera.#{aspera_name}.plist"]))
end

def macos_stop_service(aspera_name)
  macos_service('unload', aspera_name)
end

def macos_start_service(aspera_name)
  macos_service('load', aspera_name)
end

def restart_noded
  log.info('Restarting noded on macOS')
  macos_stop_service('asperalee') # not needed
  macos_stop_service('asperanoded')
  macos_stop_service('asperaredisd')
  sleep(5)
  # run(*%w[sudo /bin/chmod +a "asperadaemon allow read,write,delete,add_file" /Library/Logs/Aspera])
  # -ps -ef|grep aspera|grep -v grep
  macos_start_service('asperaredisd')
  macos_start_service('asperanoded')
  sleep(5)
  # -ps -ef|grep aspera|grep -v grep
end

def select_test_cases(selection, &block)
  raise 'missing block' unless block_given?
  list = selection&.split(' ')
  if list.nil?
    ALL_TESTS.each(&block)
  elsif list.first.eql?('tag')
    list.shift
    ALL_TESTS.select{ |_, info| info[:tags].intersect?(list)}.each(&block)
  else
    list.each do |name|
      raise "Unknown test: #{name}" unless ALL_TESTS.key?(name)
      yield(name, ALL_TESTS[name])
    end
  end
end

# @return [Integer] Percentage of completed tests
def percent_completed
  total = ALL_TESTS.size
  completed = STATES.count{ |_, v| SKIP_STATES.include?(v)}
  (completed * 100) / total
end

namespace :test do
  desc 'List tests: all, by names, or by tags (space-sep)'
  task :list, [:name_list] do |_, args|
    select_test_cases(args[:name_list]) do |name, info|
      log.info("#{name.ljust(20)} #{info[:tags].join(', ')}")
    end
  end

  desc 'Run tests: all, by names, or by tags (space-sep)'
  task :run, [:name_list] do |_, args|
    select_test_cases(args[:name_list]) do |name, _info|
      Rake::Task["#{TEST_CASE_NS}:#{name}"].invoke
    end
  end

  desc 'Skip tests: all, by names, or by tags (space-sep)'
  task :skip, [:name_list] do |_, args|
    select_test_cases(args[:name_list]) do |name, _info|
      STATES[name] = 'skipped'
      log.info("[SKIP] #{name}")
    end
    save_state
  end

  desc 'Reset tests: all, by names, or by tags (space-sep)'
  task :reset, [:name_list] do |_, args|
    select_test_cases(args[:name_list]) do |name, _info|
      STATES.delete(name)
      log.info("[RESET] #{name}")
    end
    save_state
  end

  desc 'Restart noded on macOS'
  task :noded do
    reset_macos_hsts
  end
end

namespace TEST_CASE_NS do
  # Create a Rake task for each test
  ALL_TESTS.each do |name, info|
    # desc info[:description] || '-'
    deps = info[:depends_on] || []
    Aspera.assert_array_all(deps, String)
    task name => deps.map{ |d| "#{TEST_CASE_NS}:#{d}"} do
      if SKIP_STATES.include?(STATES[name]) && !ENV['FORCE']
        # log.info "[SKIP] #{name}"
        next
      end
      log.info("--#{percent_completed}%-------------------------------------------------")
      log.info("[RUN]  #{name} [#{info[:tags].join(' ')}]")
      log.info("[EXEC] #{info[:args]&.join(' ')}")
      exec_binding = binding
      if info[:pre]
        Aspera.assert_type(info[:pre], String)
        log.info("Pre: Executing: #{info[:pre]}")
        Aspera::Environment.secure_eval(info[:pre], __FILE__, __LINE__, exec_binding)
      end
      tags = SPECIAL_TAGS.to_h{ |s| [s.to_sym, info[:tags].include?(s)]}
      tags[:save_output] ||= info[:expect] unless tags[:must_fail]
      if info[:command].nil?
        log.info("[OK]   #{name} (no command)")
        STATES[name] = 'passed'
        save_state
        next
      end
      command_line = [(BIN / info[:command]).to_s]
      if info[:command].eql?(Aspera::Cli::Info::CMD_NAME)
        command_line.push("--home=#{PATH_CLI_HOME}")
        command_line.push('-Pjns') if defined?(JRUBY_VERSION)
      end
      # ensure that config file is there (a copy)
      if info[:args][0..1].eql?(%w[config wizard]) || tags[:tmp_conf]
        PATH_TEST_CONFIG.write(TestEnv.test_configuration.to_yaml) unless PATH_TEST_CONFIG.exist?
        command_line += ["--config-file=#{PATH_TEST_CONFIG}"]
      else
        PATH_CONF_FILE.write(TestEnv.test_configuration.to_yaml) unless PATH_CONF_FILE.exist?
      end
      command_line += info[:args].map{ |i| eval_macro(i.to_s, exec_binding)}
      command_line += ["--output=#{out_file(name)}"] if tags[:save_output]
      command_line += ['--format=csv'] if tags[:save_output] && !command_line.find{ |i| i.start_with?('--format=')}
      run_options = {}
      if tags[:noblock]
        run_options[:mode] = :background
        command_line.push("--pid-file=#{pid_file(name)}")
      end
      if info[:stdin]
        stdinfile = TMP / "#{name}.stdin"
        input = eval_macro(info[:stdin], exec_binding)
        stdinfile.write(input)
        run_options[:in] = stdinfile.to_s
        log.info("in: #{input}")
      end
      if tags[:must_fail] || tags[:ignore_fail]
        run_options[:err] = err_file(name).to_s
        log.info("err: #{run_options[:err]}")
      end
      # This test case can potentially be executed repeatedly, e.g. if we wait for a value
      # Loop for possible `redo`
      loop do
        run(*(RUBY_WRAPPER + command_line), env: info[:env], **run_options)
        # Give time to start
        if tags[:noblock]
          sleep(1)
          raise 'Process not started' unless pid_file(name).exist?
        end
        if info[:post]
          Aspera.assert_type(info[:post], String)
          log.info("Executing: #{info[:post]}")
          Aspera::Environment.secure_eval(info[:post], __FILE__, __LINE__, exec_binding)
        end
        if tags[:save_output]
          saved_value = read_value_from(name)
          if saved_value.empty?
            message = 'Empty result'
            if tags[:wait_value]
              log.info("#{message}, retry...")
              sleep(5)
              redo
            else
              raise message
            end
          end
          log.info("Saved: #{saved_value}")
          if info[:expect]
            raise "not match[#{info[:expect]}][#{out_file(name).read}]" unless info[:expect].eql?(out_file(name).read.chomp)
          end
        end
        STATES[name] = 'passed'
        raise 'Must fail, but did not' if tags[:must_fail]
        log.info("[OK]   #{name}")
        break
      rescue RuntimeError => e
        STATES[name] = 'failed'
        expected_fails = tags.filter_map do |k, v|
          s = k.to_s
          s.delete_suffix!('_fail') && v == true ? s.upcase : nil
        end
        if expected_fails.empty?
          log.error("[FAIL] #{name} : #{e.message}")
          raise
        end
        if tags[:must_fail]
          stderr = err_file(name).read
          raise "Missing :expect: #{stderr}" unless info[:expect]
          raise "Expected message not found in stderr: #{info[:expect]}" unless stderr.include?(info[:expect])
        end
        log.info("[#{expected_fails.join(' ')} FAIL] #{name}")
        STATES[name] = 'passed'
        save_state
        break
      end
      save_state
    end
  end
end

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
