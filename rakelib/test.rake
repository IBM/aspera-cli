# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/environment'
require_relative '../lib/aspera/rest'
require_relative '../lib/aspera/log'
require_relative '../lib/aspera/hash_ext'
require_relative '../build/lib/build_tools'
require_relative '../build/lib/paths'
require_relative '../build/lib/test_env'
require_relative '../tests/test_helpers'
require_relative '../lib/aspera/rainbow'
require_relative '../lib/aspera/units/duration'
require 'rake'
require 'uri'
require 'zlib'
require 'etc'
require 'set'
require 'fileutils'
require 'securerandom'
require 'yaml'
using Rainbow
# spec tests (only if rspec is available)
begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new
rescue LoadError
  # rspec not available (e.g., in production/deploy environment)
end

include Paths
include BuildTools

# -----------------
# Used in tests.yml
# override $HOME/.aspera/ascli
PATH_CLI_HOME = TMP / "#{Aspera::Cli::Info::CMD_NAME}_home"
PATH_VERSION_CHECK_PERSIST = PATH_CLI_HOME / 'persist_store/version_last_check.txt'
# Package title for faspex and aoc
TIMESTAMP_TEST_RUN = Time.now.to_s
FILENAME_ASCII = 'data_file.bin'
# A medium sized file for testing with unicode characters in file name
FILENAME_UNICODE = "\u{1242B}spécial{#\u{1F600}تツ"
# Testing file generated locally
PATH_TST_ASC_LCL = TMP / FILENAME_ASCII
# Default download folder for Connect Client (used to cleanup and avoid confirmation from connect when overwrite)
PATH_WEB_DOWNLOAD = Pathname.new(Dir.home) / 'Downloads'
PATH_DOWN_TST_ASC = PATH_WEB_DOWNLOAD / FILENAME_ASCII
# This file name contains special characters, it must be quoted when used in shell
PATH_TST_UTF_LCL = TMP / FILENAME_UNICODE
# local path, using `faux:`
PATH_TST_LCL_FILE = "faux:///#{URI.encode_www_form_component(FILENAME_UNICODE)}?100m".freeze
# sync dir must be an absolute path, but tmp dir may not exist yet, while its enclosing folder shall exist
PATH_TMP_SYNCS = TMP / 'syncs'
PATH_SHARES_SYNC = PATH_TMP_SYNCS / 'shares_sync'
PATH_TST_LCL_FOLDER = PATH_TMP_SYNCS / 'sendfolder'
PATH_VAULT_FILE = TMP / 'sample_vault.bin'
PATH_FILE_LIST = TMP / 'file_list.txt'
PATH_FILE_PAIR_LIST2 = TMP / 'file_pair_list.txt'
PATH_HOT_FOLDER = TMP / 'source_hot'
PATH_SCRIPTS = TST
TEMPORIZE_CREATE = 10
TEMPORIZE_FILE = 30
# ------------------

# Auto-browser configuration for tests: default is auto (set TEST_INTERACTIVE=manual for user interaction)
ENV['TEST_INTERACTIVE'] ||= 'auto'
# Browser command (option `ui.command`, see `browser_ui_option`), nil in manual mode
BROWSER_COMMAND = ENV['TEST_INTERACTIVE'].eql?('manual') ? nil : ['ruby', (TST / 'auto_browser.rb').to_s].freeze
# Maximum duration in seconds of a test tagged `interactive`, in auto mode only: a test that waits for a human fails instead of blocking.
# In manual mode (`TEST_INTERACTIVE=manual`) a human acts, so there is no limit. `TEST_TIMEOUT=0` removes the limit in auto mode.
# Longer than the wait of `auto_browser.rb` for a login page (`TEST_LOGIN_TIMEOUT`, 120 s), so that its message is the one reported.
TEST_TIMEOUT_DEFAULT = 300

# Give warning and stop on first warning in this gem
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
# Local ports on which a test may leave a process listening: redirect of web authentication, and mock IdP
TEST_PORTS = [12_345, 13_783].freeze

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
ALL_TESTS = TestEnv.descriptions

# tests state is saved here
PATH_TESTS_STATES = TMP / 'state.yml'
STATES = PATH_TESTS_STATES.exist? ? YAML.load_file(PATH_TESTS_STATES) : {}

def path_file_pair_list
  PATH_FILE_PAIR_LIST2.write([
    PATH_TST_ASC_LCL,
    File.join(conf_data('server1_info.inside_folder'), 'other_name')
  ].join("\n")) unless PATH_FILE_PAIR_LIST2.exist?
  PATH_FILE_PAIR_LIST2
end

def save_state
  File.write(PATH_TESTS_STATES, STATES.to_yaml)
end

# Duration in seconds of the last execution of each test (passed or failed), saved here
PATH_TESTS_DURATIONS = TMP / 'durations.yml'
DURATIONS = PATH_TESTS_DURATIONS.exist? ? YAML.load_file(PATH_TESTS_DURATIONS) : {}
# Durations of the tests executed by this Rake process (filled during the run)
RUN_DURATIONS = {} # rubocop:disable Style/MutableConstant

# @return [Float] Monotonic clock, in seconds
def clock_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

# Save the duration of a test
# @param name    [String] Test name
# @param started [Float]  Value of `clock_now` when the test started
def record_duration(name, started)
  DURATIONS[name] = RUN_DURATIONS[name] = (clock_now - started).round(1)
  File.write(PATH_TESTS_DURATIONS, DURATIONS.to_yaml)
end

# @param seconds [Numeric] Duration
# @return [String] Duration as `1h02m03s`, `2m03s` or `3s`
def format_duration(seconds)
  Aspera::Units::Duration.new(seconds).to_s
end

# Log the slowest tests
# @param durations [Hash{String => Float}] Test name to duration in seconds
# @param count     [Integer]               Number of tests to show
def log_slowest(durations, count)
  durations.max_by(count, &:last).each do |name, seconds|
    log.info("#{format_duration(seconds).rjust(9)} #{name}")
  end
end

# Retrieve test environment config parameters
# @param path [String] Dot-separated path in config
# @return [Object] Value found at given path
def conf_data(path)
  TestEnv.conf_data(path)
end

def eval_macro(value, user_binding)
  # value.gsub(/\$\((.*?)\)/) do
  value.gsub(/\$\((?<inner>(?:[^()]+|\((?:[^()]+|\g<inner>)*\))*)\)/) do
    Aspera::Environment.secure_eval(Regexp.last_match(1), __FILE__, __LINE__, user_binding).to_s
  end
  # log.info "Eval: #{value} -> [#{x}]"
end

# @param pathname [Pathname] Folder
def ls_l(pathname)
  puts pathname.children.map { |p| format('%10d %s %s', p.lstat.size, p.lstat.mtime.strftime('%b %e %H:%M'), p.basename) }
end

ASPERA_LOG_PATH = '/Library/Logs/Aspera'
ASPERA_DAEMON_USER = 'asperadaemon'

# on macOS activate sshd, restore Log folder owner and restart noded
def reset_macos_hsts
  result = run(*%w[sudo systemsetup -getremotelogin], mode: :capture).first
  run(*%w[sudo systemsetup -setremotelogin on]) if result.include?('Off')
  run(*%w[sudo systemsetup -getremotelogin])
  st = File.stat(ASPERA_LOG_PATH)
  owner = Etc.getpwuid(st.uid).name
  run(*%W[sudo chown -R #{ASPERA_DAEMON_USER}: #{ASPERA_LOG_PATH}]) if owner != ASPERA_DAEMON_USER
  restart_noded
  # while ! $(CLI_COMMAND) node -N -Ptst_node_preview info;do echo waiting..;sleep 2;done
end

MACOS_LAUNCHD_UNLOAD = %w[sudo launchctl unload].freeze
MACOS_LAUNCHD_LOAD = %w[sudo launchctl load].freeze
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

# @param tags [Array<Symbol>] Tags of the test
# @return [Integer, nil] Maximum duration in seconds of the test, nil if no limit (see `TEST_TIMEOUT_DEFAULT`)
def test_timeout(tags)
  return if BROWSER_COMMAND.nil? || !tags.include?(:interactive)
  seconds = Integer(ENV.fetch('TEST_TIMEOUT', TEST_TIMEOUT_DEFAULT))
  seconds.positive? ? seconds : nil
end

# Stop a process and its children (browser...), started with `pgroup: true`
# @param pid [Integer] Process id of the leader of the group
def kill_process_group(pid)
  Process.kill('TERM', -pid)
  # Wait for the end of the leader (this also collects it: a zombie group cannot be signaled on macOS), then force if still there
  20.times do
    return if Process.waitpid(pid, Process::WNOHANG)
    sleep(0.1)
  end
  Process.kill('KILL', -pid)
  Process.wait(pid)
rescue Errno::ESRCH, Errno::ECHILD
  nil
end

# Execute the command of a test, with a limit of duration if `timeout` is set.
# Same result as `run`: raises `RuntimeError` if the command fails.
# @param command_line [Array<String>] Command and arguments
# @param timeout      [Integer, nil]  Maximum duration in seconds, nil for no limit
# @param options      [Hash]          Options of `run`
def run_test_command(command_line, timeout, **options)
  return run(*command_line, **options) if timeout.nil?
  pid = run(*command_line, mode: :background, pgroup: true, **options)
  finished = false
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  loop do
    status = Process.waitpid2(pid, Process::WNOHANG)&.last
    unless status.nil?
      finished = true
      raise "Command failed: #{status}" unless status.success?
      return true
    end
    raise "Timeout after #{timeout}s: the test probably waits for a human action (use TEST_INTERACTIVE=manual, or TEST_TIMEOUT=<seconds>)" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep(0.2)
  end
ensure
  # Timeout, Ctrl-C or any error: the command is in its own process group, so it would stay alive and keep its port (e.g. redirect of web auth)
  kill_process_group(pid) if pid && !finished
end

# Execute the command of a test in a pseudo-terminal: `$stdin.tty?` is true for the command, so that it prompts like with a human.
# Each line of `lines` is sent when the command displays a prompt, i.e. its output ends with `> `.
# Same result as `run`: raises `RuntimeError` if the command fails, or after `timeout`.
# @param command_line [Array<#to_s>]  Command and arguments
# @param lines        [Array<String>]  Lines to send, one per prompt
# @param timeout      [Integer, nil]   Maximum duration in seconds, nil for no limit
# @param transcript   [Pathname]       File where the text displayed on the terminal is saved
# @param env          [Hash, nil]      Environment variables, a `nil` value removes the variable
# @param evaluate     [#call, nil]     Called with a line and the text displayed so far, returns the text to type
def run_test_pty(command_line, lines, timeout, transcript, env: nil, evaluate: nil)
  require 'pty'
  deadline = timeout && Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  screen = +''
  # Position in `screen` after which the next prompt is expected
  answered_at = 0
  output, input, pid = PTY.spawn(env || {}, *command_line.map(&:to_s))
  begin
    loop do
      if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        # The command leads its session: closing the terminal also sends SIGHUP to its processes.
        # On macOS, a command that is stopped does not end until the terminal is closed.
        output.close
        input.close
        Process.kill('TERM', pid)
        Process.wait(pid)
        raise "Timeout after #{timeout}s: the test probably waits for a human action (use TEST_INTERACTIVE=manual, or TEST_TIMEOUT=<seconds>)"
      end
      if IO.select([output], nil, nil, 0.1)
        begin
          screen << output.read_nonblock(4096)
        rescue IO::WaitReadable
          nil
        rescue EOFError, Errno::EIO
          # The command closed the terminal: it ends
          break
        end
      end
      next if lines.empty? || !screen[answered_at..].end_with?('> ')
      # Echo is disabled after the prompt is displayed: do not type before, else the answer would be displayed
      sleep(0.2)
      line = lines.shift
      input.write(evaluate ? evaluate.call(line, screen) : line)
      answered_at = screen.size
    end
    status = Process.waitpid2(pid).last
  ensure
    output.close
    input.close
    transcript.write(screen)
  end
  raise "Command failed: #{status}" unless status.success?
  true
end

# @return [Array<String>] List of matching test case names
def select_test_cases(selection)
  list = selection&.split(' ')
  if list.nil?
    ALL_TESTS.keys
  elsif list.first.eql?('next')
    count = list[1]&.match?(/\A\d+\z/) ? list[1].to_i : 1
    ALL_TESTS.keys.reject { |name| SKIP_STATES.include?(STATES[name]) }.first(count)
  elsif list.first.eql?('tag')
    list.shift
    list.map!(&:to_sym)
    unknown = list - ALL_TESTS.each_with_object(Set.new) { |(_, i), m| m.merge(i[:tags]) }.to_a
    Aspera.assert(unknown.empty?) { "Unknown tag: #{unknown.join(', ')}".red }
    ALL_TESTS.filter_map { |name, info| name if info[:tags].intersect?(list) }
  else
    unknown = list - ALL_TESTS.keys
    Aspera.assert(unknown.empty?) { "Unknown test: #{unknown.join(', ')}".red }
    list
  end
end

# @return [Integer] Percentage of completed tests
def percent_completed
  completed = STATES.count { |_, v| SKIP_STATES.include?(v) }
  ((completed * 100.0) / ALL_TESTS.size).round(1)
end

# Set description of target when selectors are available
def selector_desc(description)
  desc("#{description}: all, by names, or by tags (space-sep)")
end

namespace :test do
  selector_desc 'List tests'
  task :list, [:name_list] do |_, args|
    select_test_cases(args[:name_list]).each do |name|
      log.info("#{name.ljust(20)} #{ALL_TESTS[name][:tags].join(', ')}")
    end
  end

  selector_desc 'Run tests'
  task :run, [:name_list] do |_, args|
    started = clock_now
    begin
      select_test_cases(args[:name_list]).each do |name|
        Rake::Task["#{TEST_CASE_NS}:#{name}"].invoke
      end
    ensure
      unless RUN_DURATIONS.empty?
        log.info("Duration of this run: #{format_duration(clock_now - started)}, #{RUN_DURATIONS.size} tests executed, slowest:")
        log_slowest(RUN_DURATIONS, 10)
      end
    end
  ensure
    # Also on failure: report the coverage of tests run so far
    Rake::Task['test:coverage'].invoke if ENV.key?('ENABLE_COVERAGE')
  end

  desc 'Generate coverage report (tmp/coverage) from results of tests run with ENABLE_COVERAGE, and badge when all tests completed'
  task :coverage do
    # Do not start coverage of Rake itself, but keep the variable for tests started afterwards
    saved = ENV.delete('ENABLE_COVERAGE')
    begin
      require_relative '../lib/aspera/coverage'
    ensure
      ENV['ENABLE_COVERAGE'] = saved if saved
    end
    percent = Aspera::Coverage.report
    next log.warn('No coverage result') if percent.nil?
    # A partial run would publish a lower coverage
    next log.info("Coverage #{percent.round(1)}%: badge not updated, tests completed: #{percent_completed}%") unless percent_completed.eql?(100.0)
    Aspera::Coverage.write_badge(percent)
    log.info("Coverage #{percent.round(1)}%: badge updated: #{Aspera::Coverage::BADGE}")
  end

  selector_desc 'Skip tests'
  task :skip, [:name_list] do |_, args|
    select_test_cases(args[:name_list]).each do |name|
      STATES[name] = 'skipped'
      log.info("[SKIP] #{name}")
    end
    save_state
  end

  selector_desc 'Reset tests'
  task :reset, [:name_list] do |_, args|
    to_reset = select_test_cases(args[:name_list])
    # find all reverse dependencies
    loop do
      # find tests that depend on current selection
      revdep = ALL_TESTS.filter_map do |name, info|
        name if info[:depends_on]&.intersect?(to_reset)
      end
      # end if no new dependency
      break if (revdep - to_reset).empty?
      to_reset |= revdep
    end
    to_reset.each do |name|
      log.info("[RESET] #{name}") if STATES.delete(name)
    end
    save_state
  end

  desc 'Show test durations (last execution of each test, possibly in several runs): total and slowest tests'
  task :durations, [:count] do |_, args|
    durations = DURATIONS.slice(*ALL_TESTS.keys)
    next log.warn("No test duration in #{PATH_TESTS_DURATIONS}") if durations.empty?
    log.info("Total: #{format_duration(durations.values.sum)} for #{durations.size} of #{ALL_TESTS.size} tests, slowest:")
    log_slowest(durations, Integer(args[:count] || 20))
  end

  desc 'Restart noded on macOS'
  task :noded do
    reset_macos_hsts
  end

  desc 'Show test status: passed, failed, not run'
  task :status do
    passed  = STATES.count { |_, v| v == 'passed' }
    failed  = STATES.count { |_, v| v == 'failed' }
    skipped = STATES.count { |_, v| v == 'skipped' }
    not_run = ALL_TESTS.size - STATES.size
    log.info("Total  : #{ALL_TESTS.size}")
    log.info("Passed : #{passed}")
    log.info("Failed : #{failed}")
    log.info("Skipped: #{skipped}")
    log.info("Not run: #{not_run}")
  end

  desc 'Stop processes left by tests: background ones (tmp/states/*.pid) and listeners on the ports used by tests'
  task :kill_background do
    processes = PATH_TMP_STATES.glob('*.pid').to_h { |f| [f.read.to_i, f.basename('.pid').to_s] }
    # Processes that were not started with a pid file (e.g. interrupted test), but still keep a port
    TEST_PORTS.each do |port|
      `lsof -ti tcp:#{port} -sTCP:LISTEN 2>/dev/null`.split.each { |p| processes[p.to_i] ||= "port #{port}" }
    end
    processes.each do |pid, origin|
      next unless pid.positive?
      # The pid may have been reused by an unrelated process if the file is stale
      command = `ps -p #{pid} -o command= 2>/dev/null`.strip
      next unless command.match?(/ascli|mock_idp/)
      log.info("Stopping #{origin}: #{pid} (#{command})")
      begin
        Process.kill('TERM', pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end
  end
end

# Do not lose the pid files (in tmp) of background processes: stop them before deleting
task clean: 'test:kill_background'

namespace TEST_CASE_NS do
  # Create a Rake task for each test
  ALL_TESTS.each do |name, info|
    # desc info[:description] || '-'
    deps = info[:depends_on] || []
    Aspera.assert_array_all(deps, String)
    task name => deps.map { |d| "#{TEST_CASE_NS}:#{d}" } do
      started = nil
      if SKIP_STATES.include?(STATES[name]) && !ENV['FORCE']
        # log.info "[SKIP] #{name}"
        next
      end
      started = clock_now
      log.info("--#{percent_completed}%-------------------------------------------------")
      log.info("[RUN]  #{name} [#{info[:tags].join(' ')}]")
      log.info("[EXEC] #{info[:args]&.join(' ')}")
      # The options of the auto browser are selected by each test, see `select_browser`
      ENV['ASCLI_UI'] = browser_ui_option
      exec_binding = binding
      t = TestEnv::Context.new(name, info[:instance_prefix], info.fetch(:siblings, []))
      (info[:vars] || {}).each { |k, v| exec_binding.local_variable_set(k.to_sym, v) }
      if info[:pre]
        Aspera.assert_type(info[:pre], String)
        log.info("Pre: Executing: #{info[:pre]}")
        Aspera::Environment.secure_eval(info[:pre], __FILE__, __LINE__, exec_binding)
      end
      # [Hash{Symbol => Boolean}] key=special tag, value=true if present
      tags = TestEnv::SPECIAL_TAGS.to_h { |s| [s, info[:tags].include?(s)] }
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
        PATH_TEST_CONFIG.write(TestEnv.configuration.to_yaml) unless PATH_TEST_CONFIG.exist?
        command_line += ["--config-file=#{PATH_TEST_CONFIG}"]
      else
        PATH_CONF_FILE.write(TestEnv.configuration.to_yaml) unless PATH_CONF_FILE.exist?
      end
      command_line += info[:args].map { |i| eval_macro(i.to_s, exec_binding) }
      command_line += ["--out.file=#{t.out_file}"] if tags[:save_output]
      command_line += ['--format=csv', '--out.level=data'] if tags[:save_output] && !command_line.find { |i| i.start_with?('--format=', '--out.format=') }
      run_options = {}
      if tags[:background]
        run_options[:mode] = :background
        command_line.push("--pid-file=#{t.pid_file}")
      end
      tty_lines = []
      tty_evaluate = nil
      if info[:stdin]
        if tags[:tty]
          # Sent to the terminal, one line per prompt (see `run_test_pty`).
          # Macros are evaluated when the line is typed: `screen` is the text displayed so far, e.g. to read the login URL that the command shows.
          tty_lines = info[:stdin].lines
          log.info("in: #{info[:stdin]}")
          tty_evaluate = lambda do |line, screen|
            exec_binding.local_variable_set(:screen, screen)
            eval_macro(line, exec_binding)
          end
        else
          input = eval_macro(info[:stdin], exec_binding)
          log.info("in: #{input}")
          stdinfile = TMP / "#{name}.stdin"
          stdinfile.write(input)
          run_options[:in] = stdinfile.to_s
          run_options[:out] = t.out_file.to_s unless tags[:background]
        end
      end
      if tags[:must_fail] || tags[:cleanup]
        run_options[:err] = t.err_file.to_s
        log.info("err: #{run_options[:err]}")
      end
      # This test case can potentially be executed repeatedly, e.g. if we wait for a value
      # Loop for possible `redo`
      wait_attempts = 0
      loop do
        if tags[:background]
          run(*(RUBY_WRAPPER + command_line), env: info[:env], **run_options)
        elsif tags[:tty]
          # The text displayed on the terminal is saved in a `.tty` file, e.g. to check that a secret was not displayed
          run_test_pty(RUBY_WRAPPER + command_line, tty_lines.dup, test_timeout(info[:tags]), t.out_file.sub_ext('.tty'), env: info[:env], evaluate: tty_evaluate)
        else
          run_test_command(RUBY_WRAPPER + command_line, test_timeout(info[:tags]), env: info[:env], **run_options)
        end
        # Give time to start
        if tags[:background]
          sleep(1)
          raise 'Process not started' unless t.pid_file.exist?
        end
        if info[:post]
          Aspera.assert_type(info[:post], String)
          log.info("Executing: #{info[:post]}")
          begin
            Aspera::Environment.secure_eval(info[:post], __FILE__, __LINE__, exec_binding)
          rescue StandardError
            # Do not leave the background process running: it keeps its port and the output of rake
            begin
              t.stop_process if tags[:background]
            rescue Errno::ESRCH
              nil
            end
            raise
          end
        end
        if tags[:save_output]
          saved_value = t.saved_output
          if saved_value.empty?
            message = 'Empty result'
            if tags[:wait_value]
              wait_attempts += 1
              raise "#{message} after #{wait_attempts} attempts" if wait_attempts >= 60
              log.info("#{message}, retry #{wait_attempts}...")
              sleep(5)
              redo
            else
              raise message
            end
          end
          log.info("Saved: #{saved_value}")
          if info[:expect]
            expected = eval_macro(info[:expect], exec_binding)
            raise "not match[#{expected}][#{t.out_file.read}]" unless expected.eql?(t.out_file.read.chomp)
          end
        end
        STATES[name] = 'passed'
        raise 'Must fail, but did not' if tags[:must_fail]
        log.info("[OK]   #{name}")
        break
      rescue RuntimeError => e
        if tags[:wait_value] && wait_attempts < 60
          wait_attempts += 1
          log.info("Retry #{wait_attempts} after error: #{e.message}")
          sleep(5)
          redo
        end
        STATES[name] = 'failed'
        expected_fails = TestEnv::EXPECTED_FAIL.select { |tag| tags[tag] }
        if expected_fails.empty?
          log.error("[FAIL] #{name} : #{e.message}")
          raise
        end
        if tags[:must_fail]
          stderr = t.err_file.read
          raise "Missing :expect: #{stderr}" unless info[:expect]
          raise "Expected message not found in stderr: #{info[:expect]}\nHave: #{stderr}" unless stderr.include?(info[:expect])
        end
        log.info("[FAIL] #{name} #{expected_fails.join(' ')}")
        STATES[name] = 'passed'
        save_state
        break
      end
      save_state
    ensure
      # Also when the test fails
      record_duration(name, started) unless started.nil?
    end
  end
end
