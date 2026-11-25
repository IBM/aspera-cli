# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../agent/factory'
require_relative '../../bundle_registry'
require_relative '../../schema/registry'
require_relative '../../ascp/installation'
require_relative '../../cli/argument'
require_relative '../../cli/error'
require_relative '../../cli/hints'
require_relative '../../cli/option/declarator'
require_relative '../../cli/result'
require_relative '../../cli/version'
require_relative '../../transfer/error'
require_relative '../../transfer/parameters'
require_relative '../../transfer/result'
require_relative '../../transfer/spec'
require_relative '../../cli/info'
require_relative 'async_transfer_store'
require_relative '../../log'
require_relative '../../assert'
require_relative '../../secret/hider'
require_relative '../../cli/security'
require 'securerandom'

module Aspera
  module Plugins
    module Xfer
      # The Transfer agent is a common interface to start a transfer using
      # one of the supported transfer agents.
      # Provide CLI options to select one of the transfer agents (FASP/ascp client)
      # Service `transfer` of the bundle (manifest `services`): created once per context, see `Cli::Context#service`
      class TransferAgent
        # Plugins store transfer result using this key and use `result_transfer_multiple`
        STATUS_FIELD = 'status'
        # Schema of option `transfer`, in the schemas of the bundle (manifest `schemas`): its variants are the agents (extension point `agent`)
        TRANSFER_OPTION_SCHEMA = 'transfer_opts:components.schemas.TransferAgentOptions'
        # `@args` special value for --sources : read file list from arguments
        FILE_LIST_FROM_ARGS = '@args'
        # `@ts` special value for --sources : read file list from transfer spec (--ts)
        FILE_LIST_FROM_TRANSFER_SPEC = '@ts'
        FILE_LIST_OPTIONS = [FILE_LIST_FROM_ARGS, FILE_LIST_FROM_TRANSFER_SPEC, 'Array'].freeze
        DEFAULT_TRANSFER_NOTIFY_TEMPLATE = <<~END_OF_TEMPLATE
          From: <%=from_name%> <<%=from_email%>>
          To: <<%=to%>>
          Subject: <%=subject%>

          Transfer is: <%=status%>

          <%=ts.to_yaml%>
        END_OF_TEMPLATE
        CP4I_REMOTE_HOST_LB = 'N/A'
        # Folder of the configuration folder for file lists used by transfers
        FILE_LIST_FOLDER_NAME = 'filelists'
        # Transfer spec parameters overridden by option `ts`
        TS_DEFAULTS = {
          'create_dir'    => true,
          'resume_policy' => 'sparse_csum'
        }.freeze
        private_constant :FILE_LIST_FROM_TRANSFER_SPEC,
          :FILE_LIST_OPTIONS,
          :DEFAULT_TRANSFER_NOTIFY_TEMPLATE,
          :FILE_LIST_FOLDER_NAME,
          :TS_DEFAULTS

        extend Cli::Option::Declarator

        option :ts,            description: 'Override transfer spec values', schema: Schema::Registry::TRANSFER_SPEC, on_set: :user_transfer_spec=
        option :to_folder,     description: 'Destination folder for transferred files', complete: :destination_folder
        option :sources,       description: "How list of transferred files is provided (#{FILE_LIST_OPTIONS.join(',')})",               default: FILE_LIST_FROM_ARGS
        option :src_type,      description: 'Type of file list',                                                                        allowed: %i[list pair], default: :list
        option :transfer,      description: 'Transfer agent type, or agent parameters with optional agent key',                         allowed: [Hash, String], shorthand: 'agent', schema: TRANSFER_OPTION_SCHEMA
        option :transfer_info, description: 'Parameters for transfer agent',                                                            deprecation: {last: '4.26.2', message: 'use --transfer instead'}, schema: TRANSFER_OPTION_SCHEMA

        class << self
          # Process the typed result of a finished (or submitted) transfer.
          # @param transfer_result [Aspera::Transfer::Result] typed result from `start`
          # @raise [StandardError] if the transfer failed
          # @return [Cli::Result] CLI result object
          def result_transfer(transfer_result)
            case transfer_result
            when Aspera::Transfer::Result::Async
              return Cli::Result::SingleObject.new(transfer_result.to_h)
            when Aspera::Transfer::Result::Error
              raise transfer_result.exception
            when Aspera::Transfer::Result::Success
              return Cli::Result::Nothing.new
            when Aspera::Transfer::Result::DryRun
              # Secrets are hidden by the formatter, as in any result
              return Cli::Result::SingleObject.new(transfer_result.transfer_spec)
            else
              raise "Unexpected transfer result type: #{transfer_result.class}"
            end
          end

          # Result of a command that creates an object and transfers its files, e.g. `packages send`.
          # @param object          [Hash]                     Created object
          # @param transfer_result [Aspera::Transfer::Result] Typed result from `start`
          # @raise [StandardError] if the transfer failed
          # @return [Cli::Result::SingleObject] The object, with field `transfer` (`job_id`) if the transfer is asynchronous
          def result_object_transfer(object, transfer_result)
            status = result_transfer(transfer_result)
            object = object.merge('transfer' => status.data) if status.is_a?(Cli::Result::SingleObject)
            Cli::Result::SingleObject.new(object)
          end

          # Used when one command executes several transfer jobs (each job being possibly multi session)
          # @param status_table [Array] [{STATUS_FIELD=>Aspera::Transfer::Result,...},...]
          # @return [Cli::Result] a status object suitable as command result
          def result_transfer_multiple(status_table)
            failed_result = nil
            status_table.each do |item|
              tr = item[STATUS_FIELD]
              case tr
              when Aspera::Transfer::Result::Error
                failed_result ||= tr
                item[STATUS_FIELD] = tr.exception.message
              when Aspera::Transfer::Result::Success
                item[STATUS_FIELD] = 'success'
              when Aspera::Transfer::Result::Async
                item[STATUS_FIELD] = "async:#{tr.job_id}"
              when Aspera::Transfer::Result::DryRun
                item[STATUS_FIELD] = 'dry_run'
              else
                item[STATUS_FIELD] = tr.to_s
              end
            end
            raise failed_result.exception unless failed_result.nil?
            return Cli::Result::ObjectList.new(status_table)
          end
        end

        # @param context [Cli::Context] Application context
        def initialize(context)
          Aspera.assert_type(context, Cli::Context) { 'context' }
          Aspera.assert_type(context.options, Cli::Parser) { 'context.options' }
          @context = context
          # Runtime of transfers: SDK downloads refer to the version of the gem, file lists are in the configuration folder (if any, else a temporary folder)
          Ascp::Installation.instance.referer_url = "#{Cli::Info::GEM_URL}/versions/#{Cli::VERSION}"
          Aspera::Transfer::Parameters.file_list_folder = File.join(@context.main_folder, FILE_LIST_FOLDER_NAME) unless @context.main_folder.nil?
          # Command line can override transfer spec
          @user_transfer_spec = TS_DEFAULTS.dup
          # the currently selected transfer agent
          @agent = nil
          # source/destination pair, like "paths" of transfer spec
          @transfer_paths = nil
          # HTTPGW URL provided by webapp
          @httpgw_url_lambda = nil
          # Instance variables used by `on_set` callbacks are set above
          self.class.declare_options(@context.options, target: self)
          @context.options.parse_options!
          @notification_cb = nil
          if !@context.options.get_option(:notify_to).nil?
            @notification_cb = ->(transfer_spec, global_status) do
              @context.mailer.send_email_template(email_template_default: DEFAULT_TRANSFER_NOTIFY_TEMPLATE, values: {
                subject: "#{Cli::Info::CMD_NAME} transfer: #{global_status}",
                status:  global_status,
                ts:      transfer_spec
              })
            end
          end
        end

        attr_reader :user_transfer_spec

        # Argument shown in the help of a command with `transfer_paths`: the files are read by `ts_source_paths`
        # @param direction [Symbol] `:send` (files to upload) or `:receive` (remote paths to download)
        # @return [Cli::Argument] Description of the list of files, depending on option `sources`
        def paths_argument(direction)
          description =
            case direction
            when :receive then "Remote path(s) to download (default --sources=#{FILE_LIST_FROM_ARGS}; see also --to-folder)"
            when :send then "Source file(s) to upload (default --sources=#{FILE_LIST_FROM_ARGS}; see also --src-type, --to-folder)"
            else Aspera.error_unexpected_value(direction) { 'transfer_paths' }
            end
          Cli::Argument.new(name: :source_file, description: description, mandatory: false, multiple: true)
        end

        # `on_set` callback of option `ts`: values override defaults
        # @param value [Hash] transfer spec parameters
        def user_transfer_spec=(value)
          @user_transfer_spec = TS_DEFAULTS.merge(value)
        end

        # @return [Hash] agent type (key `agent`) and agent parameters, from options `transfer` and deprecated `transfer_info`
        def transfer_options
          @context.options.get_option(:transfer_info).deep_merge(@context.options.get_option(:transfer))
        end

        # Options to create the `direct` agent that runs the local `async` program for a `sync` command.
        # `sync` always uses the `direct` agent, whatever the `agent` key of option `transfer`, so the parameters of
        # `transfer` (and the deprecated `transfer_info`) are forwarded only when they are those of the `direct` agent
        # (its default); parameters meant for another agent (e.g. the `url` of `node`) are ignored. For `async`, `quiet`
        # and `spawn_timeout_sec` have an effect; the `ascp`-only parameters (e.g. `ascp_args`, `wss`, `resume`) do not.
        # The base options (e.g. `progress`, `config_dir`) are always given, as for any agent.
        # @return [Hash] options for `Aspera::Agent::Factory.create(:direct, ...)`
        def sync_agent_options
          raw_type = transfer_options['agent']
          agent_options = raw_type.nil? || raw_type.to_s.eql?('direct') ? transfer_options.except('agent', 'asynchronous').symbolize_keys : {}
          agent_options[:trusted_certs] = @context.http_config.trusted_cert_locations unless agent_options.key?(:trusted_certs)
          agent_options.merge(base_agent_options)
        end

        def agent_instance=(instance)
          @agent = instance
          # Name of the agent is found from the instance when needed, see `agent_name`
          @agent_type = nil
        end

        # @return [String] Name of the agent in use (resolved name, not an abbreviation of option `transfer`), also if the instance was given
        def agent_name
          @agent_type ||= Aspera::Agent::Factory.instance.agent_name(agent_instance)&.to_s
          Aspera.assert(@agent_type) { "unknown agent class: #{agent_instance.class}" }
          @agent_type
        end

        # analyze options and create new agent if not already created or set
        def agent_instance
          return @agent unless @agent.nil?
          # agent type: from composite option 'agent' key, default :direct
          raw_type = transfer_options['agent'] || :direct
          # An agent of an unavailable bundle is given as is: creating it tells why it is unavailable
          agent_type = Aspera::Agent::Factory.instance.unavailable_reason(raw_type).nil? ? Cli::Parser.get_from_list(raw_type.to_s, 'transfer agent', Aspera::Agent::Factory::ALL.keys) : raw_type.to_s
          # set keys as symbols, strip internal keys not forwarded to the agent constructor
          agent_options = transfer_options.except('agent', 'asynchronous').symbolize_keys
          # get agent instance
          begin
            agent_class = Aspera::Agent::Factory.instance.agent_class(agent_type)
            # A transfer agent that runs on the local host (local `ascp`, a local daemon, a local application) is refused at level `high`:
            # at `high`, transfers use a remote agent (e.g. `node`, or `transferd` attached to a remote daemon) that the user controls.
            # Checked before the base options are built: the decision needs only the agent parameters (e.g. the daemon `url`).
            unless Cli::Security.instance.allowed?(agent_class.required_security_level(agent_options))
              raise Cli::BadArgument,
                "transfer agent #{agent_type}: runs on the local host, disabled by security level #{Cli::Security.instance.level}. " \
                'Use a remote agent (--transfer.agent=node, or --transfer.agent=transferd with a url to a remote daemon), or a lower security level'
            end
            # Same base options for every agent, each agent uses those it needs (see `Aspera::Agent::Base#initialize`)
            # JRuby: given value, else trusted certificates of the HTTP configuration
            agent_options[:trusted_certs] = @context.http_config.trusted_cert_locations unless agent_options.key?(:trusted_certs)
            agent_options.merge!(base_agent_options)
            self.agent_instance = Aspera::Agent::Factory.instance.create(agent_type, agent_options)
            @agent_type = agent_type.to_s
          rescue BundleRegistry::Unavailable => e
            # Agent of a bundle that cannot be loaded (e.g. missing gem): same error as an unavailable plugin
            raise Cli::Error, e.message
          end
          Log.log.debug { "transfer agent is a #{@agent.class}" }
          return @agent
        end

        # Get destination folder
        # @param direction [String] `send`` or `receive``
        # @return [String] Destination folder for transfers (with default based on direction)
        def destination_folder(direction)
          dest_folder = @context.options.get_option(:to_folder)
          # do not expand path, if user wants to expand path: user @path:
          return dest_folder unless dest_folder.nil?
          dest_folder = @user_transfer_spec['destination_root']
          return dest_folder unless dest_folder.nil?
          # default: / on remote, . on local
          case direction.to_s
          when Aspera::Transfer::Spec::DIRECTION_SEND then dest_folder = '/'
          when Aspera::Transfer::Spec::DIRECTION_RECEIVE then dest_folder = '.'
          else Aspera.error_unexpected_value(direction)
          end
          return dest_folder
        end

        # @return [Array] list of source files
        def source_list
          return ts_source_paths.map do |i|
            i['source']
          end
        end

        # @param httpgw_url_proc [Proc]
        def httpgw_url_cb=(httpgw_url_proc)
          Aspera.assert_type(httpgw_url_proc, Proc) { 'httpgw_url_cb' }
          @httpgw_url_lambda = httpgw_url_proc
        end

        # Transform the list of paths to a list of hash with source/dest
        # @param file_list [Array<Hash>]
        def list_to_paths(file_list)
          source_type = @context.options.get_option(:src_type, mandatory: true)
          @transfer_paths =
            case source_type
            when :list
              # when providing a list, just specify source
              file_list.map { |i| {'source' => i} }
            when :pair
              Aspera.assert(file_list.length.even?, type: Cli::BadArgument) { "When using pair, provide an even number of paths: #{file_list.length}" }
              file_list.each_slice(2).map { |s, d| {'source' => s, 'destination' => d} }
            else Aspera.error_unexpected_value(source_type)
            end
        end

        # This is how the list of files to be transferred is specified
        # get paths suitable for transfer spec from command line
        # computation is done only once, cache is kept in @transfer_paths
        # @param default [nil, Array<String>] If set, used as default file for --sources=@args
        # @return [Array, nil] of Hash {source: (mandatory), destination: (optional)}
        def ts_source_paths(default: nil)
          # return cache if set
          return @transfer_paths unless @transfer_paths.nil?
          # start with lower priority : get paths from transfer spec on command line
          @transfer_paths = @user_transfer_spec['paths'] if @user_transfer_spec.key?('paths')
          # is there a source list option ?
          sources = @context.options.get_option(:sources)
          @transfer_paths =
            case sources
            when FILE_LIST_FROM_ARGS
              Log.log.debug('getting file list as parameters')
              Aspera.assert_type(default, Array, NilClass)
              # get remaining arguments
              list = @context.options.get_next_argument('source file list', multiple: true, default: default)
              raise Cli::BadArgument, 'specify at least one file on command line or use ' \
                "--sources=#{FILE_LIST_FROM_TRANSFER_SPEC} to use transfer spec" if !list.is_a?(Array) || list.empty?
              list_to_paths(list)
            when FILE_LIST_FROM_TRANSFER_SPEC
              Log.log.debug('assume list provided in transfer spec')
              special_case_direct_with_list =
                (transfer_options['agent'] || :direct).to_sym.eql?(:direct) &&
                Aspera::Transfer::Parameters.ascp_args_file_list?(transfer_options['ascp_args'])
              Aspera.assert(!@transfer_paths.nil? || special_case_direct_with_list, type: Cli::BadArgument) { 'transfer spec on command line must have sources' }
              # can be nil
              @transfer_paths
            when Array
              Log.log.debug('getting file list as extended value')
              Aspera.assert_array_all(sources, String, type: Cli::BadArgument) { 'sources must be a Array of String' }
              list_to_paths(sources)
            else Aspera.error_unexpected_value(sources) { 'sources' }
            end
          Log.dump(:paths, @transfer_paths)
          return @transfer_paths
        end

        # Start a transfer and wait for completion, plugins shall use this method
        # @param transfer_spec [Hash] transfer specification
        # @param oauth_api     [Rest::Client, nil] API whose OAuth token renews the bearer token of the transfer, if rejected
        def start(transfer_spec, oauth_api: nil)
          # check parameters
          Aspera.assert_type(transfer_spec, Hash) { 'transfer_spec' }
          raise "Wrong remote host: #{CP4I_REMOTE_HOST_LB}" if transfer_spec['remote_host'].eql?(CP4I_REMOTE_HOST_LB)
          # process :src option
          case transfer_spec['direction']
          when Aspera::Transfer::Spec::DIRECTION_RECEIVE
            # init default if required in any case
            @user_transfer_spec['destination_root'] ||= destination_folder(transfer_spec['direction'])
          when Aspera::Transfer::Spec::DIRECTION_SEND
            if transfer_spec.dig('tags', Aspera::Transfer::Spec::TAG_RESERVED, 'node', 'access_key')
              # gen4
              @user_transfer_spec.delete('destination_root') if @user_transfer_spec.key?('destination_root_id')
            elsif transfer_spec.key?('token')
              # gen3
              # in that case, destination is set in return by application (API/upload_setup)
              # but to_folder was used in initial API call
              @user_transfer_spec.delete('destination_root')
            else
              # init default if required
              @user_transfer_spec['destination_root'] ||= destination_folder(transfer_spec['direction'])
            end
          end
          # update command line paths, unless destination already has one
          @user_transfer_spec['paths'] = transfer_spec['paths'] || ts_source_paths
          # updated transfer spec with command line
          transfer_spec.deep_merge!(@user_transfer_spec)
          # Files are written where the client chooses, see Security: only for an agent that writes on the local system
          receives_locally = transfer_spec['direction'].eql?(Aspera::Transfer::Spec::DIRECTION_RECEIVE) && agent_instance.local_destination?
          transfer_spec['destination_root'] = Cli::Security.instance.writable_path(transfer_spec['destination_root']) if receives_locally && transfer_spec['destination_root']
          # resolve pseudo-parameter: target_rate -> target_rate_kbps (overrides target_rate_kbps if both are present)
          Aspera::Transfer::Spec.resolve_target_rate(transfer_spec)
          # recursively remove values that are nil (user wants to delete)
          transfer_spec.deep_do { |hash, key, value, _unused| hash.delete(key) if value.nil? }
          # if TS from app has content_protection (e.g. F5), that means content is protected: ask password if not provided
          transfer_spec['content_protection_password'] = @context.options.prompt_user_input('content protection password', sensitive: true) if transfer_spec['content_protection'].eql?('decrypt') && !transfer_spec.key?('content_protection_password')
          # Secrets of transfer spec (e.g. `token` from the application) are hidden wherever they appear (logs, results)
          Secret::Hider.instance.add_secrets_in(transfer_spec)
          # Option `dry_run`: no transfer, the final transfer spec is the result
          return Aspera::Transfer::Result.dry_run(transfer_spec) if dry_run?
          # Renews the bearer token of the transfer: only possible with OAuth
          token_regenerator = -> { oauth_api.oauth.renewed_authorization } if oauth_api&.auth_params&.fetch(:type, nil).eql?(:oauth2)
          # create transfer agent
          agent_instance.start_transfer(transfer_spec, token_regenerator: token_regenerator)
          # --- async mode ---
          if transfer_options['asynchronous']
            # In-process agents (direct, httpgw) expose last_job_id directly.
            # Remote-daemon agents do not override last_job_id (returns nil): generate a UUID.
            agent_type = agent_name
            job_id = agent_instance.last_job_id || SecureRandom.uuid
            # Base agent_params from transfer options (strip internal keys), and connection details resolved by the agent (daemon agents)
            agent_params = transfer_options.except('agent', 'asynchronous').merge(agent_instance.async_params)
            # Register an in-process agent reference for direct/httpgw agents so that
            # config transfer status can re-query them while the same process is alive
            # (e.g. MCP server mode). The ref is stored in AsyncTransferStore's memory map,
            # never on disk.
            async_store.register_agent_ref(job_id, agent_instance) if agent_instance.in_process?
            async_store.write(job_id, {
              'job_id'            => job_id,
              'agent_type'        => agent_type,
              'transfer_id'       => agent_instance.transfer_id.to_s,
              'agent_params'      => agent_params,
              'status'            => 'running',
              'bytes_transferred' => 0,
              'started_at'        => Time.now.utc.iso8601,
              'ended_at'          => nil,
              'error'             => nil
            })
            Log.log.info { "Async transfer started: job_id=#{job_id}, agent=#{agent_type}" }
            return Aspera::Transfer::Result.async(job_id: job_id)
          end
          # --- synchronous mode (default) ---
          result = agent_instance.wait_for_completion
          @notification_cb&.call(transfer_spec, result)
          return result
        end

        # @return [Boolean] `true` if option `dry_run` is set: transfers are not started (see `start`)
        def dry_run?
          @context.options.get_option(:dry_run)
        end

        # For a command that changes something before its transfer (e.g. creates a package), or that does not transfer with `start`:
        # fail before any change with option `dry_run`
        # @raise [Cli::BadArgument] if option `dry_run` is set
        def assert_no_dry_run
          Aspera.assert(!dry_run?, type: Cli::BadArgument) { 'Option dry_run is not supported by this command' }
        end

        # shut down if agent requires it
        def shutdown
          @agent.shutdown if @agent.respond_to?(:shutdown)
        end

        # Lazy accessor for the async transfer store (shared with TransferActions via context.transfer).
        def async_store
          @async_store ||= AsyncTransferStore.new(@context.persistency)
        end

        private

        # Base options given to every agent: plain values and callable objects (Proc), see `Aspera::Agent::Base#initialize`
        # @return [Hash] base options
        def base_agent_options
          {
            progress:         @context.progress_bar,
            # Option `progress_bar` not set: an agent that displays its own progress (direct, not `quiet`) does not use it
            progress_default: @context.options.option_def(:progress_bar).source.eql?(:default),
            config_dir:       @context.main_folder,
            check_ignore_cb:  ->(host, port) { @context.http_config.ignore_cert?(host, port) },
            # Values of the default preset of a plugin (e.g. node agent without `url`)
            preset_lookup:    ->(plugin) do
              param_set_name = @context.presets.plugin_default_name(plugin)
              Aspera.assert(!param_set_name.nil?, type: Cli::BadArgument) { "No default #{plugin} configured. Please specify #{Cli::Parser.option_name_to_line(:transfer)}.url or #{Cli::Parser.option_name_to_line(:transfer)}" }
              @context.presets.by_name(param_set_name)
            end,
            # URL given by the web application (httpgw agent without `url`)
            url_provider:     @httpgw_url_lambda
          }
        end
      end
      # A failed transfer exits with its own code
      Cli::ExitCode.add_error(Aspera::Transfer::Error, label: 'Transfer', code: Cli::ExitCode::TRANSFER)
      Cli::Hints.add(
        exception:   Aspera::Transfer::Error,
        match:       'Remote host is not who we expected',
        remediation: [
          'For this specific error, refer to:',
          "#{Cli::Info::SRC_URL}#error-remote-host-is-not-who-we-expected",
          'Add this to arguments:',
          %q{--ts=@json:'{"sshfp":null}'"}
        ]
      )
      Cli::Hints.add(
        exception:   RuntimeError,
        match:       /unexpected last event type: INIT/,
        remediation: [
          'ascp exited unexpectedly',
          'it might be due to SSH handshake failure',
          'one can check SSH connection using ssh command'
        ]
      )
      # Raised by `TransferAgent#start`
      Cli::Hints.add(
        exception:   RuntimeError,
        match:       /Wrong remote host:/,
        remediation: [
          'If remote node is Cloud Pak For Integration',
          'Make sure that a LoadBalancer is active on cluster',
          'Check the external address of Aspera tcp-proxy Pod'
        ]
      )
    end
  end
end
