# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/rest'
require 'aspera/log'
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
# spec tests
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new

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

# CLI with default config file
# give warning and stop on first warning in this gem
CLI_TEST = ['ruby', '-w', TST / 'warning_exit_wrapper.rb', CLI_CMD, "--home=#{PATH_CLI_HOME}"]
# JRuby does not support some encryptions
CLI_TEST.push('-Pjns') if defined?(JRUBY_VERSION)
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
ALL_TESTS = yaml_safe_load(TEST_DEFS.read)
# add tags for plugin
ALL_TESTS.each_value do |value|
  plugin = value['command']&.find{ |s| !s.start_with?('-')}
  value['tags'] ||= []
  value['tags'].unshift(plugin) unless value['tags'].include?(plugin)
end

# Allowed keys in test defs: See tests/README.md
ALLOWED_KEYS = %w{command tags depends_on description pre post env $comment stdin expect}
unsupported_keys = ALL_TESTS.values.map(&:keys).flatten.uniq - ALLOWED_KEYS
raise "Unsupported keys: #{unsupported_keys}" unless unsupported_keys.empty?
# tests state is saved here
PATH_TESTS_STATES = TMP / 'state.yml'
STATES = PATH_TESTS_STATES.exist? ? YAML.load_file(PATH_TESTS_STATES) : {}

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

def conf_data(path)
  @param_config_cache = TestEnv.test_configuration if @param_config_cache.nil?
  current = @param_config_cache
  path.split('.').each do |k|
    current = current[k]
    raise "Missing config: #{k} for #{path}" if current.nil?
  end
  current
end

def eval_macro(value)
  # value.gsub(/\$\((.*?)\)/) do
  value.gsub(/\$\((?<inner>(?:[^()]+|\((?:[^()]+|\g<inner>)*\))*)\)/) do
    Aspera::Environment.secure_eval(Regexp.last_match(1), __FILE__, __LINE__).to_s
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
  # while ! $(CLI_TEST) node -N -Ptst_node_preview info;do echo waiting..;sleep 2;done
end

def restart_noded
  run(*%w[sudo launchctl unload /Library/LaunchDaemons/com.aspera.asperalee.plist])
  run(*%w[sudo launchctl unload /Library/LaunchDaemons/com.aspera.asperanoded.plist])
  run(*%w[sudo launchctl unload /Library/LaunchDaemons/com.aspera.asperaredisd.plist])
  sleep(5)
  # run(*%w[sudo /bin/chmod +a "asperadaemon allow read,write,delete,add_file" /Library/Logs/Aspera])
  # -ps -ef|grep aspera|grep -v grep
  run(*%w[sudo launchctl load /Library/LaunchDaemons/com.aspera.asperaredisd.plist])
  run(*%w[sudo launchctl load /Library/LaunchDaemons/com.aspera.asperanoded.plist])
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
    ALL_TESTS.select{ |_, info| info['tags']&.intersect?(list)}.each(&block)
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
      log.info("#{name.ljust(20)} #{info['tags']&.join(', ')}")
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
    # desc info['description'] || '-'
    deps = info['depends_on'] || []
    Aspera.assert_array_all(deps, String)
    task name => deps.map{ |d| "#{TEST_CASE_NS}:#{d}"} do
      if SKIP_STATES.include?(STATES[name]) && !ENV['FORCE']
        # log.info "[SKIP] #{name}"
        next
      end
      log.info("--#{percent_completed}%-------------------------------------------------")
      log.info("[RUN]  #{name} [#{info['tags']&.join(' ')}]")
      log.info("[EXEC] #{info['command']&.join(' ')}")
      if info['pre']
        Aspera.assert_type(info['pre'], String)
        log.info("Pre: Executing: #{info['pre']}")
        Aspera::Environment.secure_eval(info['pre'], __FILE__, __LINE__)
      end
      must_fail = info['tags']&.include?('must_fail')
      hide_fail = info['tags']&.include?('hide_fail')
      ignore_fail = info['tags']&.include?('ignore_fail')
      save_output = info['tags']&.include?('save_output') || info['expect']
      wait_value = info['tags']&.include?('wait_value')
      tmp_conf = info['tags']&.include?('tmp_conf')
      if info['command']
        if info['command'].include?('wizard')
          info['env'] ||= {}
          info['env']['ASCLI_WIZ_TEST'] = 'yes'
        end
        # This test case can potentially be executed repeatedly, e.g. if we wait for a value
        full_args = CLI_TEST.map(&:to_s)
        if info['command'][0..1].eql?(%w[config wizard]) || tmp_conf
          PATH_TEST_CONFIG.write(TestEnv.test_configuration.to_yaml) unless PATH_TEST_CONFIG.exist?
          full_args += ["--config-file=#{PATH_TEST_CONFIG}"]
        else
          PATH_CONF_FILE.write(TestEnv.test_configuration.to_yaml) unless PATH_CONF_FILE.exist?
        end
        full_args += info['command'].map{ |i| eval_macro(i.to_s)}
        full_args += ["--output=#{out_file(name)}"] if save_output
        full_args += ['--format=csv'] if save_output && !full_args.find{ |i| i.start_with?('--format=')}
        run_options = {}
        if info['tags']&.include?('noblock')
          run_options[:mode] = :background
          full_args.push("--pid-file=#{pid_file(name)}")
        end
        if info['stdin']
          stdinfile = TMP / "#{name}.stdin"
          input = eval_macro(info['stdin'])
          stdinfile.write(input)
          run_options[:in] = stdinfile.to_s
          log.info("Input: #{input}")
        end
        loop do
          run(*full_args, env: info['env'], **run_options)
          # give time to start
          sleep(1) if info['tags']&.include?('noblock')
          if info['post']
            Aspera.assert_type(info['post'], String)
            log.info("Executing: #{info['post']}")
            Aspera::Environment.secure_eval(info['post'], __FILE__, __LINE__)
          end
          if save_output
            saved_value = read_value_from(name)
            if saved_value.empty?
              if wait_value
                log.info('No value saved, retry...')
                sleep(5)
                redo
              else
                raise 'No value saved (empty value)'
              end
            end
            log.info("Saved: #{saved_value}")
            if info['expect']
              raise "not match[#{info['expect']}][#{out_file(name).read}]" unless info['expect'].eql?(out_file(name).read.chomp)
            end
          end
          STATES[name] = 'passed'
          raise 'Must fail' if must_fail
          log.info("[OK]   #{name}")
          break
        rescue RuntimeError
          STATES[name] = 'failed'
          if must_fail || hide_fail || ignore_fail
            log.error("[IGNORE FAIL] #{name}")
            STATES[name] = 'passed'
          else
            log.error("[FAIL] #{name}")
            raise
          end
          save_state
          break
        end
      else
        log.info("[OK]   #{name} (no command)")
        STATES[name] = 'passed'
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
