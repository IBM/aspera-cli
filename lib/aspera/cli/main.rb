# frozen_string_literal: true

require 'aspera/cli/manager'
require 'aspera/cli/formatter'
require 'aspera/cli/plugins/config'
require 'aspera/cli/extended_value'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/version'
require 'aspera/cli/info'
require 'aspera/fasp/error'
require 'aspera/open_application'
require 'aspera/temp_file_manager'
require 'aspera/persistency_folder'
require 'aspera/log'
require 'aspera/rest'
require 'aspera/nagios'
require 'aspera/colors'
require 'aspera/secret_hider'
require 'net/ssh'

module Aspera
  module Cli
    # The main CLI class
    class Main
      # prefix to display error messages in user messages (terminal)
      ERROR_FLASH = 'ERROR:'.bg_red.gray.blink.freeze
      WARNING_FLASH = 'WARNING:'.bg_red.gray.blink.freeze
      private_constant :ERROR_FLASH, :WARNING_FLASH

      # store transfer result using this key and use result_transfer_multiple
      STATUS_FIELD = 'status'

      # for testing only
      SELF_SIGNED_CERT = OpenSSL::SSL.const_get(:enon_yfirev.to_s.upcase.reverse)

      class << self
        # expect some list, but nothing to display
        def result_empty; return {type: :empty, data: :nil}; end

        # nothing expected
        def result_nothing; return {type: :nothing, data: :nil}; end

        def result_status(status); return {type: :status, data: status}; end

        def result_success; return result_status('complete'); end

        # Process statuses of finished transfer sessions
        # raise exception if there is one error
        # else returns an empty status
        def result_transfer(statuses)
          worst = TransferAgent.session_status(statuses)
          raise worst unless worst.eql?(:success)
          return Main.result_nothing
        end

        # used when one command executes several transfer jobs (each job being possibly multi session)
        # @param status_table [Array] [{STATUS_FIELD=>[status array],...},...]
        # @return a status object suitable as command result
        # each element has a key STATUS_FIELD which contains the result of possibly multiple sessions
        def result_transfer_multiple(status_table)
          global_status = :success
          # transform status array into string and find if there was problem
          status_table.each do |item|
            worst = TransferAgent.session_status(item[STATUS_FIELD])
            global_status = worst unless worst.eql?(:success)
            item[STATUS_FIELD] = item[STATUS_FIELD].map(&:to_s).join(',')
          end
          raise global_status unless global_status.eql?(:success)
          return {type: :object_list, data: status_table}
        end
      end

      private

      # =============================================================
      # Parameter handlers
      #
      attr_accessor :option_insecure, :option_http_options, :option_cache_tokens

      def option_ui; OpenApplication.instance.url_method; end

      def option_ui=(value); OpenApplication.instance.url_method = value; end

      # called every time a new REST HTTP session is opened
      # @param http [Net::HTTP] the newly created http session object
      def http_parameters=(http)
        if @option_insecure
          url = http.inspect.gsub(/^[^ ]* /, 'https://').gsub(/ [^ ]*$/, '')
          if !@ssl_warned_urls.include?(url)
            @formatter.display_message(:error, "#{WARNING_FLASH} ignoring certificate for: #{url}. Do not use unsafe certificates in production.")
            @ssl_warned_urls.push(url)
          end
          http.verify_mode = SELF_SIGNED_CERT
        end
        http.set_debug_output($stdout) if @option_rest_debug
        raise 'http_options expects Hash' unless @option_http_options.is_a?(Hash)

        @option_http_options.each do |k, v|
          method = "#{k}=".to_sym
          # check if accessor is a method of Net::HTTP
          # continue_timeout= read_timeout= write_timeout=
          if http.respond_to?(method)
            http.send(method, v)
          else
            Log.log.error{"no such attribute: #{k}"}
          end
        end
      end

      # minimum initialization
      def initialize(argv)
        # first thing : manage debug level (allows debugging of option parser)
        early_debug_setup(argv)
        # compare $0 with expected name
        current_prog_name = File.basename($PROGRAM_NAME)
        @formatter.display_message(:error, "#{'WARNING'.bg_red.blink.gray} Please use '#{PROGRAM_NAME}' instead of '#{current_prog_name}'") \
          unless current_prog_name.eql?(PROGRAM_NAME)
        @option_help = false
        @bash_completion = false
        @option_show_config = false
        @option_insecure = false
        @option_rest_debug = false
        @option_cache_tokens = true
        @option_http_options = {}
        @ssl_warned_urls = []
        # environment provided to plugin for various capabilities
        @plugin_env = {}
        # give command line arguments to option manager
        @plugin_env[:options] = @opt_mgr = Manager.new(PROGRAM_NAME, argv: argv)
        # formatter adds options
        @formatter = @plugin_env[:formatter] = Formatter.new(@plugin_env[:options])
        Rest.user_agent = PROGRAM_NAME
        Rest.session_cb = lambda{|http|self.http_parameters = http}
        # declare and parse global options
        init_global_options
        # the Config plugin adds the @preset parser, so declare before TransferAgent which may use it
        @plugin_env[:config] = Plugins::Config.new(@plugin_env, gem: GEM_NAME, name: PROGRAM_NAME, help: DOC_URL, version: Aspera::Cli::VERSION)
        # the TransferAgent plugin may use the @preset parser
        @plugin_env[:transfer] = TransferAgent.new(@plugin_env[:options], @plugin_env[:config])
        # data persistency
        @plugin_env[:persistency] = PersistencyFolder.new(File.join(@plugin_env[:config].main_folder, 'persist_store'))
        Log.log.debug('plugin env created'.red)
        Oauth.persist_mgr = @plugin_env[:persistency] if @option_cache_tokens
        Fasp::Parameters.file_list_folder = File.join(@plugin_env[:config].main_folder, 'filelists')
        Aspera::RestErrorAnalyzer.instance.log_file = File.join(@plugin_env[:config].main_folder, 'rest_exceptions.log')
        # register aspera REST call error handlers
        Aspera::RestErrorsAspera.register_handlers
        # set banner when all environment is created so that additional extended value modifiers are known, e.g. @preset
        @opt_mgr.parser.banner = app_banner
      end

      def app_banner
        t = ' ' * 8
        return <<~END_OF_BANNER
          NAME
          #{t}#{PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{Aspera::Cli::VERSION})

          SYNOPSIS
          #{t}#{PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]

          DESCRIPTION
          #{t}Use Aspera application to perform operations on command line.
          #{t}Documentation and examples: #{GEM_URL}
          #{t}execute: #{PROGRAM_NAME} conf doc
          #{t}or visit: #{DOC_URL}
          #{t}source repo: #{SRC_URL}

          ENVIRONMENT VARIABLES
          #{t}#{@plugin_env[:config].conf_dir_env_var} config folder, default: $HOME/#{Plugins::Config::ASPERA_HOME_FOLDER_NAME}/#{PROGRAM_NAME}
          #{t}Any option can be set as an environment variable, refer to the manual

          COMMANDS
          #{t}To list first level commands, execute: #{PROGRAM_NAME}
          #{t}Note that commands can be written shortened (provided it is unique).

          OPTIONS
          #{t}Options begin with a '-' (minus), and value is provided on command line.
          #{t}Special values are supported beginning with special prefix @pfx:, where pfx is one of:
          #{t}#{ExtendedValue.instance.modifiers.map(&:to_s).join(', ')}
          #{t}Dates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'

          ARGS
          #{t}Some commands require mandatory arguments, e.g. a path.
        END_OF_BANNER
      end

      # define header for manual
      def init_global_options
        Log.log.debug('init_global_options')
        @opt_mgr.add_opt_switch(:help, '-h', 'Show this message.') { @option_help = true }
        @opt_mgr.add_opt_switch(:bash_comp, 'generate bash completion for command') { @bash_completion = true }
        @opt_mgr.add_opt_switch(:show_config, 'Display parameters used for the provided action.') { @option_show_config = true }
        @opt_mgr.add_opt_switch(:rest_debug, '-r', 'more debug for HTTP calls') { @option_rest_debug = true }
        @opt_mgr.add_opt_switch(:version, '-v', 'display version') { @formatter.display_message(:data, Aspera::Cli::VERSION); Process.exit(0) } # rubocop:disable Style/Semicolon, Layout/LineLength
        @opt_mgr.add_opt_switch(:warnings, '-w', 'check for language warnings') { $VERBOSE = true }
        # handler must be set before declaration
        @opt_mgr.set_obj_attr(:log_level, Log.instance, :level)
        @opt_mgr.set_obj_attr(:logger, Log.instance, :logger_type)
        @opt_mgr.set_obj_attr(:insecure, self, :option_insecure, :no)
        @opt_mgr.set_obj_attr(:ui, self, :option_ui)
        @opt_mgr.set_obj_attr(:http_options, self, :option_http_options)
        @opt_mgr.set_obj_attr(:log_secrets, SecretHider, :log_secrets)
        @opt_mgr.set_obj_attr(:cache_tokens, self, :option_cache_tokens)
        @opt_mgr.add_opt_list(:ui, OpenApplication.user_interfaces, 'method to start browser')
        @opt_mgr.add_opt_list(:log_level, Log.levels, 'Log level')
        @opt_mgr.add_opt_list(:logger, Log::LOG_TYPES, 'logging method')
        @opt_mgr.add_opt_simple(:lock_port, 'prevent dual execution of a command, e.g. in cron')
        @opt_mgr.add_opt_simple(:http_options, 'options for http socket (extended value)')
        @opt_mgr.add_opt_boolean(:insecure, 'do not validate HTTPS certificate')
        @opt_mgr.add_opt_boolean(:once_only, 'process only new items (some commands)')
        @opt_mgr.add_opt_boolean(:log_secrets, 'show passwords in logs')
        @opt_mgr.add_opt_boolean(:cache_tokens, 'save and reuse Oauth tokens')
        @opt_mgr.set_option(:ui, OpenApplication.default_gui_mode)
        @opt_mgr.set_option(:once_only, false)
        # parse declared options
        @opt_mgr.parse_options!
      end

      # @return the plugin instance, based on name
      # also loads the plugin options, and default values from conf file
      # @param plugin_name_sym : symbol for plugin name
      def get_plugin_instance_with_options(plugin_name_sym, env=nil)
        env ||= @plugin_env
        Log.log.debug{"get_plugin_instance_with_options(#{plugin_name_sym})"}
        require @plugin_env[:config].plugins[plugin_name_sym][:require_stanza]
        # load default params only if no param already loaded before plugin instantiation
        env[:config].add_plugin_default_preset(plugin_name_sym)
        command_plugin = Plugins::Config.plugin_class(plugin_name_sym).new(env)
        Log.log.debug{"got #{command_plugin.class}"}
        # TODO: check that ancestor is Plugin?
        return command_plugin
      end

      def generate_bash_completion
        if @opt_mgr.get_next_argument('', expected: :multiple, mandatory: false).nil?
          @plugin_env[:config].plugins.each_key{|p|puts p.to_s}
        else
          Log.log.warn('only first level completion so far')
        end
        Process.exit(0)
      end

      def exit_with_usage(all_plugins)
        Log.log.debug('exit_with_usage'.bg_red)
        # display main plugin options
        @formatter.display_message(:error, @opt_mgr.parser)
        if all_plugins
          # list plugins that have a "require" field, i.e. all but main plugin
          @plugin_env[:config].plugins.each_key do |plugin_name_sym|
            next if plugin_name_sym.eql?(Plugins::Config::CONF_PLUGIN_SYM)
            # override main option parser with a brand new, to avoid having global options
            plugin_env = @plugin_env.clone
            plugin_env[:man_only] = true
            plugin_env[:options] = Manager.new(PROGRAM_NAME)
            plugin_env[:options].parser.banner = '' # remove default banner
            get_plugin_instance_with_options(plugin_name_sym, plugin_env)
            # display generated help for plugin options
            @formatter.display_message(:error, plugin_env[:options].parser.help)
          end
        end
        Process.exit(0)
      end

      protected

      # early debug for parser
      # Note: does not accept shortcuts
      def early_debug_setup(argv)
        Aspera::Log.instance.program_name = PROGRAM_NAME
        argv.each do |arg|
          case arg
          when '--' then break
          when /^--log-level=(.*)/ then Aspera::Log.instance.level = Regexp.last_match(1).to_sym
          when /^--logger=(.*)/ then Aspera::Log.instance.logger_type = Regexp.last_match(1).to_sym
          end
        end
      end

      public

      # this is the main function called by initial script just after constructor
      def process_command_line
        Log.log.debug('process_command_line')
        # catch exception information , if any
        exception_info = nil
        # false if command shall not be executed ("once_only")
        execute_command = true
        begin
          # find plugins, shall be after parse! ?
          @plugin_env[:config].add_plugins_from_lookup_folders
          # help requested without command ? (plugins must be known here)
          exit_with_usage(true) if @option_help && @opt_mgr.command_or_arg_empty?
          generate_bash_completion if @bash_completion
          @plugin_env[:config].periodic_check_newer_gem_version
          command_sym =
            if @option_show_config && @opt_mgr.command_or_arg_empty?
              Plugins::Config::CONF_PLUGIN_SYM
            else
              @opt_mgr.get_next_command(@plugin_env[:config].plugins.keys.dup.unshift(:help))
            end
          # command will not be executed, but we need manual
          @opt_mgr.fail_on_missing_mandatory = false if @option_help || @option_show_config
          # main plugin is not dynamically instantiated
          case command_sym
          when :help
            exit_with_usage(true)
          when Plugins::Config::CONF_PLUGIN_SYM
            command_plugin = @plugin_env[:config]
          else
            # get plugin, set options, etc
            command_plugin = get_plugin_instance_with_options(command_sym)
            # parse plugin specific options
            @opt_mgr.parse_options!
          end
          # help requested for current plugin
          exit_with_usage(false) if @option_help
          if @option_show_config
            @formatter.display_results({type: :single_object, data: @opt_mgr.declared_options(only_defined: true)})
            execute_command = false
          end
          # locking for single execution (only after "per plugin" option, in case lock port is there)
          lock_port = @opt_mgr.get_option(:lock_port)
          if !lock_port.nil?
            begin
              # no need to close later, will be freed on process exit. must save in member else it is garbage collected
              Log.log.debug{"Opening lock port #{lock_port.to_i}"}
              @tcp_server = TCPServer.new('127.0.0.1', lock_port.to_i)
            rescue StandardError => e
              execute_command = false
              Log.log.warn{"Another instance is already running (#{e.message})."}
            end
          end
          # execute and display (if not exclusive execution)
          @formatter.display_results(command_plugin.execute_action) if execute_command
          # finish
          @plugin_env[:transfer].shutdown
        rescue Net::SSH::AuthenticationFailed => e; exception_info = {e: e, t: 'SSH', security: true}
        rescue OpenSSL::SSL::SSLError => e;         exception_info = {e: e, t: 'SSL'}
        rescue CliBadArgument => e;                 exception_info = {e: e, t: 'Argument', usage: true}
        rescue CliNoSuchId => e;                    exception_info = {e: e, t: 'Identifier'}
        rescue CliError => e;                       exception_info = {e: e, t: 'Tool', usage: true}
        rescue Fasp::Error => e;                    exception_info = {e: e, t: 'FASP(ascp)'}
        rescue Aspera::RestCallError => e;          exception_info = {e: e, t: 'Rest'}
        rescue SocketError => e;                    exception_info = {e: e, t: 'Network'}
        rescue StandardError => e;                  exception_info = {e: e, t: 'Other', debug: true}
        rescue Interrupt => e;                      exception_info = {e: e, t: 'Interruption', debug: true}
        end
        # cleanup file list files
        TempFileManager.instance.cleanup
        # 1- processing of error condition
        unless exception_info.nil?
          Log.log.warn(exception_info[:e].message) if Aspera::Log.instance.logger_type.eql?(:syslog) && exception_info[:security]
          @formatter.display_message(:error, "#{ERROR_FLASH} #{exception_info[:t]}: #{exception_info[:e].message}")
          @formatter.display_message(:error, 'Use option -h to get help.') if exception_info[:usage]
          # Provide hint on FASP errors
          if exception_info[:e].is_a?(Fasp::Error) && exception_info[:e].message.eql?('Remote host is not who we expected')
            @formatter.display_message(:error, "For this specific error, refer to:\n"\
              "#{SRC_URL}#error-remote-host-is-not-who-we-expected\nAdd this to arguments:\n--ts=@json:'{\"sshfp\":null}'")
          end
          # Provide hint on SSL errors
          if exception_info[:e].is_a?(OpenSSL::SSL::SSLError) && ['does not match the server certificate'].any?{|m|exception_info[:e].message.include?(m)}
            @formatter.display_message(:error, "You can ignore SSL errors with option:\n--insecure=yes")
          end
        end
        # 2- processing of command not processed (due to exception or bad command line)
        if execute_command || @option_show_config
          @opt_mgr.final_errors.each do |msg|
            @formatter.display_message(:error, "#{ERROR_FLASH} Argument: #{msg}")
            # add code as exception if there is not already an error
            exception_info = {e: Exception.new(msg), t: 'UnusedArg'} if exception_info.nil?
          end
        end
        # 3- in case of error, fail the process status
        unless exception_info.nil?
          # show stack trace in debug mode
          raise exception_info[:e] if Log.instance.level.eql?(:debug)
          # else give hint and exit
          @formatter.display_message(:error, 'Use --log-level=debug to get more details.') if exception_info[:debug]
          Process.exit(1)
        end
        return nil
      end # process_command_line
    end # Main
  end # Cli
end # Aspera
