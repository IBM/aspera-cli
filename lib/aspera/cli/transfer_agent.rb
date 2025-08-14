# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/transfer/spec'
require 'aspera/cli/info'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # The Transfer agent is a common interface to start a transfer using
    # one of the supported transfer agents
    # provides CLI options to select one of the transfer agents (FASP/ascp client)
    class TransferAgent
      # special value for --sources : read file list from arguments
      FILE_LIST_FROM_ARGS = '@args'
      # special value for --sources : read file list from transfer spec (--ts)
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
      # % (formatting bug in eclipse)
      private_constant :FILE_LIST_FROM_ARGS,
        :FILE_LIST_FROM_TRANSFER_SPEC,
        :FILE_LIST_OPTIONS,
        :DEFAULT_TRANSFER_NOTIFY_TEMPLATE
      TRANSFER_AGENTS = Agent::Base.agent_list.freeze

      class << self
        # @return :success if all sessions statuses returned by "start" are success
        # else return the first error exception object
        def session_status(statuses)
          error_statuses = statuses.reject{ |i| i.eql?(:success)}
          return :success if error_statuses.empty?
          return error_statuses.first
        end
      end

      # @param env external objects: option manager, config file manager
      def initialize(opt_mgr, config_plugin)
        @opt_mgr = opt_mgr
        @config = config_plugin
        # command line can override transfer spec
        @transfer_spec_command_line = {
          'create_dir'    => true,
          'resume_policy' => 'sparse_csum'
        }
        # options for transfer agent
        @transfer_info = {}
        # the currently selected transfer agent
        @agent = nil
        # source/destination pair, like "paths" of transfer spec
        @transfer_paths = nil
        # HTTPGW URL provided by webapp
        @httpgw_url_lambda = nil
        @opt_mgr.declare(:ts, 'Override transfer spec values', types: Hash, handler: {o: self, m: :option_transfer_spec})
        @opt_mgr.declare(:to_folder, 'Destination folder for transferred files')
        @opt_mgr.declare(:sources, "How list of transferred files is provided (#{FILE_LIST_OPTIONS.join(',')})")
        @opt_mgr.declare(:src_type, 'Type of file list', values: %i[list pair], default: :list)
        @opt_mgr.declare(:transfer, 'Type of transfer agent', values: TRANSFER_AGENTS, default: :direct)
        @opt_mgr.declare(:transfer_info, 'Parameters for transfer agent', types: Hash, handler: {o: self, m: :transfer_info})
        @opt_mgr.parse_options!
        @notification_cb = nil
        if !@opt_mgr.get_option(:notify_to).nil?
          @notification_cb = ->(transfer_spec, global_status) do
            @config.send_email_template(email_template_default: DEFAULT_TRANSFER_NOTIFY_TEMPLATE, values: {
              subject: "#{Info::CMD_NAME} transfer: #{global_status}",
              status:  global_status,
              ts:      transfer_spec
            })
          end
        end
      end

      def option_transfer_spec; @transfer_spec_command_line; end

      # multiple option are merged
      def option_transfer_spec=(value)
        Aspera.assert_type(value, Hash){'ts'}
        @transfer_spec_command_line.deep_merge!(value)
      end

      # add other transfer spec parameters
      def option_transfer_spec_deep_merge(ts); @transfer_spec_command_line.deep_merge!(ts); end

      attr_reader :transfer_info

      # multiple option are merged
      def transfer_info=(value)
        @transfer_info.deep_merge!(value)
      end

      def agent_instance=(instance)
        @agent = instance
      end

      # analyze options and create new agent if not already created or set
      # TODO: make a Factory pattern
      def agent_instance
        return @agent unless @agent.nil?
        agent_type = @opt_mgr.get_option(:transfer, mandatory: true)
        # set keys as symbols
        agent_options = @opt_mgr.get_option(:transfer_info).symbolize_keys
        # special cases
        case agent_type
        when :node
          if agent_options.empty?
            param_set_name = @config.get_plugin_default_config_name(:node)
            raise Cli::BadArgument, "No default node configured. Please specify #{Manager.option_name_to_line(:transfer_info)}" if param_set_name.nil?
            agent_options = @config.preset_by_name(param_set_name).symbolize_keys
          end
        when :direct
          # by default do not display ascp native progress bar
          agent_options[:quiet] = true unless agent_options.key?(:quiet)
          agent_options[:check_ignore_cb] = ->(host, port){@config.ignore_cert?(host, port)}
          # JRuby
          agent_options[:trusted_certs] = @config.trusted_cert_locations unless agent_options.key?(:trusted_certs)
        when :httpgw
          unless agent_options.key?(:url) || @httpgw_url_lambda.nil?
            Log.log.debug('retrieving HTTPGW URL from webapp')
            agent_options[:url] = @httpgw_url_lambda.call
          end
        end
        agent_options[:progress] = @config.progress_bar
        # get agent instance
        self.agent_instance = Agent::Base.factory_create(agent_type, agent_options)
        Log.log.debug{"transfer agent is a #{@agent.class}"}
        return @agent
      end

      # return destination folder for transfers
      # sets default if needed
      # param: 'send' or 'receive'
      def destination_folder(direction)
        dest_folder = @opt_mgr.get_option(:to_folder)
        # do not expand path, if user wants to expand path: user @path:
        return dest_folder unless dest_folder.nil?
        dest_folder = @transfer_spec_command_line['destination_root']
        return dest_folder unless dest_folder.nil?
        # default: / on remote, . on local
        case direction.to_s
        when Transfer::Spec::DIRECTION_SEND then dest_folder = '/'
        when Transfer::Spec::DIRECTION_RECEIVE then dest_folder = '.'
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

      def httpgw_url_cb=(httpgw_url_proc)
        Aspera.assert_type(httpgw_url_proc, Proc){'httpgw_url_cb'}
        @httpgw_url_lambda = httpgw_url_proc
      end

      # This is how the list of files to be transferred is specified
      # get paths suitable for transfer spec from command line
      # @param default [String] if set, used as default file for --sources=@args
      # @return [Hash] {source: (mandatory), destination: (optional)}
      # computation is done only once, cache is kept in @transfer_paths
      def ts_source_paths(default: nil)
        # return cache if set
        return @transfer_paths unless @transfer_paths.nil?
        # start with lower priority : get paths from transfer spec on command line
        @transfer_paths = @transfer_spec_command_line['paths'] if @transfer_spec_command_line.key?('paths')
        # is there a source list option ?
        file_list = @opt_mgr.get_option(:sources)
        case file_list
        when nil, FILE_LIST_FROM_ARGS
          Log.log.debug('getting file list as parameters')
          Aspera.assert_type(default, Array) unless default.nil?
          # get remaining arguments
          file_list = @opt_mgr.get_next_argument('source file list', multiple: true, default: default)
          raise Cli::BadArgument, 'specify at least one file on command line or use ' \
            "--sources=#{FILE_LIST_FROM_TRANSFER_SPEC} to use transfer spec" if !file_list.is_a?(Array) || file_list.empty?
        when FILE_LIST_FROM_TRANSFER_SPEC
          Log.log.debug('assume list provided in transfer spec')
          special_case_direct_with_list =
            @opt_mgr.get_option(:transfer, mandatory: true).eql?(:direct) &&
            Transfer::Parameters.ascp_args_file_list?(@opt_mgr.get_option(:transfer_info)['ascp_args'])
          raise Cli::BadArgument, 'transfer spec on command line must have sources' if @transfer_paths.nil? && !special_case_direct_with_list
          # here we assume check of sources is made in transfer agent
          return @transfer_paths
        when Array
          Log.log.debug('getting file list as extended value')
          raise Cli::BadArgument, 'sources must be a Array of String' if !file_list.reject{ |f| f.is_a?(String)}.empty?
        else
          raise Cli::BadArgument, "sources must be a Array, not #{file_list.class}"
        end
        # here, file_list is an Array or String
        if !@transfer_paths.nil?
          Log.log.warn('--sources overrides paths from --ts')
        end
        source_type = @opt_mgr.get_option(:src_type, mandatory: true)
        case source_type
        when :list
          # when providing a list, just specify source
          @transfer_paths = file_list.map{ |i| {'source' => i}}
        when :pair
          Aspera.assert(file_list.length.even?, exception_class: Cli::BadArgument){"When using pair, provide an even number of paths: #{file_list.length}"}
          @transfer_paths = file_list.each_slice(2).to_a.map{ |s, d| {'source' => s, 'destination' => d}}
        else Aspera.error_unexpected_value(source_type)
        end
        Log.log.debug{"paths=#{@transfer_paths}"}
        return @transfer_paths
      end

      # start a transfer and wait for completion, plugins shall use this method
      # @param transfer_spec [Hash]
      # @param rest_token [Rest] if oauth token regeneration supported
      def start(transfer_spec, rest_token: nil)
        # check parameters
        Aspera.assert_type(transfer_spec, Hash){'transfer_spec'}
        if transfer_spec['remote_host'].eql?(CP4I_REMOTE_HOST_LB)
          raise "Wrong remote host: #{CP4I_REMOTE_HOST_LB}"
        end
        # process :src option
        case transfer_spec['direction']
        when Transfer::Spec::DIRECTION_RECEIVE
          # init default if required in any case
          @transfer_spec_command_line['destination_root'] ||= destination_folder(transfer_spec['direction'])
        when Transfer::Spec::DIRECTION_SEND
          if transfer_spec.dig('tags', Transfer::Spec::TAG_RESERVED, 'node', 'access_key')
            # gen4
            @transfer_spec_command_line.delete('destination_root') if @transfer_spec_command_line.key?('destination_root_id')
          elsif transfer_spec.key?('token')
            # gen3
            # in that case, destination is set in return by application (API/upload_setup)
            # but to_folder was used in initial API call
            @transfer_spec_command_line.delete('destination_root')
          else
            # init default if required
            @transfer_spec_command_line['destination_root'] ||= destination_folder(transfer_spec['direction'])
          end
        end
        # update command line paths, unless destination already has one
        @transfer_spec_command_line['paths'] = transfer_spec['paths'] || ts_source_paths
        # updated transfer spec with command line
        transfer_spec.deep_merge!(@transfer_spec_command_line)
        # recursively remove values that are nil (user wants to delete)
        transfer_spec.deep_do{ |hash, key, value, _unused| hash.delete(key) if value.nil?}
        # if TS from app has content_protection (e.g. F5), that means content is protected: ask password if not provided
        if transfer_spec['content_protection'].eql?('decrypt') && !transfer_spec.key?('content_protection_password')
          transfer_spec['content_protection_password'] = @opt_mgr.prompt_user_input('content protection password', sensitive: true)
        end
        # create transfer agent
        agent_instance.start_transfer(transfer_spec, token_regenerator: rest_token)
        # list of: :success or "error message string"
        result = agent_instance.wait_for_completion
        @notification_cb&.call(transfer_spec, self.class.session_status(result))
        return result
      end

      # shut down if agent requires it
      def shutdown
        @agent.shutdown if @agent.respond_to?(:shutdown)
      end
    end
  end
end
