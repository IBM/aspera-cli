# frozen_string_literal: true

require 'aspera/fasp/transfer_spec'
require 'aspera/cli/listener/logger'
require 'aspera/cli/listener/progress_multi'
require 'aspera/cli/info'

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
      DEFAULT_TRANSFER_NOTIF_TMPL = <<~END_OF_TEMPLATE
        From: <%=from_name%> <<%=from_email%>>
        To: <<%=to%>>
        Subject: <%=subject%>

        Transfer is: <%=global_transfer_status%>

        <%=ts.to_yaml%>
      END_OF_TEMPLATE
      # % (formatting bug in eclipse)
      private_constant :FILE_LIST_FROM_ARGS,
        :FILE_LIST_FROM_TRANSFER_SPEC,
        :FILE_LIST_OPTIONS,
        :DEFAULT_TRANSFER_NOTIF_TMPL
      TRANSFER_AGENTS = %i[direct node connect httpgw trsdk].freeze

      class << self
        # @return :success if all sessions statuses returned by "start" are success
        # else return the first error exception object
        def session_status(statuses)
          error_statuses = statuses.reject{|i|i.eql?(:success)}
          return :success if error_statuses.empty?
          return error_statuses.first
        end
      end

      # @param env external objects: option manager, config file manager
      def initialize(opt_mgr, config)
        @opt_mgr = opt_mgr
        @config = config
        # command line can override transfer spec
        @transfer_spec_cmdline = {'create_dir' => true}
        # the currently selected transfer agent
        @agent = nil
        @progress_listener = Listener::ProgressMulti.new
        # source/destination pair, like "paths" of transfer spec
        @transfer_paths = nil
        @opt_mgr.set_obj_attr(:ts, self, :option_transfer_spec)
        @opt_mgr.add_opt_simple(:ts, "Override transfer spec values (Hash, e.g. use @json: prefix), current=#{@opt_mgr.get_option(:ts)}")
        @opt_mgr.add_opt_simple(:to_folder, 'Destination folder for transferred files')
        @opt_mgr.add_opt_simple(:sources, "How list of transferred files is provided (#{FILE_LIST_OPTIONS.join(',')})")
        @opt_mgr.add_opt_list(:src_type, %i[list pair], 'Type of file list')
        @opt_mgr.add_opt_list(:transfer, TRANSFER_AGENTS, 'Type of transfer agent')
        @opt_mgr.add_opt_simple(:transfer_info, 'Parameters for transfer agent')
        @opt_mgr.add_opt_list(:progress, %i[none native multi], 'Type of progress bar')
        @opt_mgr.set_option(:transfer, :direct)
        @opt_mgr.set_option(:src_type, :list)
        @opt_mgr.set_option(:progress, :native) # use native ascp progress bar as it is more reliable
        @opt_mgr.parse_options!
      end

      def option_transfer_spec; @transfer_spec_cmdline; end

      # multiple option are merged
      def option_transfer_spec=(value); @transfer_spec_cmdline.merge!(value); end

      def option_transfer_spec_deep_merge(ts); @transfer_spec_cmdline.deep_merge!(ts); end

      def agent_instance=(instance)
        @agent = instance
        @agent.add_listener(Listener::Logger.new)
        # use local progress bar if asked so, or if native and non local ascp (because only local ascp has native progress bar)
        if @opt_mgr.get_option(:progress, is_type: :mandatory).eql?(:multi) ||
            (@opt_mgr.get_option(:progress, is_type: :mandatory).eql?(:native) && !instance.class.to_s.eql?('Aspera::Fasp::AgentDirect'))
          @agent.add_listener(@progress_listener)
        end
      end

      # analyze options and create new agent if not already created or set
      def set_agent_by_options
        return nil unless @agent.nil?
        agent_type = @opt_mgr.get_option(:transfer, is_type: :mandatory)
        # agent plugin is loaded on demand to avoid loading unnecessary dependencies
        require "aspera/fasp/agent_#{agent_type}"
        agent_options = @opt_mgr.get_option(:transfer_info)
        raise CliBadArgument, "the transfer agent configuration shall be Hash, not #{agent_options.class} (#{agent_options}), "\
          'use either @json:<json> or @preset:<parameter set name>' unless [Hash, NilClass].include?(agent_options.class)
        # special case
        if agent_type.eql?(:node) && agent_options.nil?
          param_set_name = @config.get_plugin_default_config_name(:node)
          raise CliBadArgument, "No default node configured, Please specify --#{:transfer_info.to_s.tr('_', '-')}" if param_set_name.nil?
          agent_options = @config.preset_by_name(param_set_name)
        end
        # special case
        if agent_type.eql?(:direct) && @opt_mgr.get_option(:progress, is_type: :mandatory).eql?(:native)
          agent_options = {} if agent_options.nil?
          agent_options[:quiet] = false
        end
        agent_options = agent_options.symbolize_keys if agent_options.is_a?(Hash)
        # get agent instance
        new_agent = Kernel.const_get("Aspera::Fasp::Agent#{agent_type.capitalize}").new(agent_options)
        self.agent_instance = new_agent
        return nil
      end

      # return destination folder for transfers
      # sets default if needed
      # param: 'send' or 'receive'
      def destination_folder(direction)
        dest_folder = @opt_mgr.get_option(:to_folder)
        # do not expand path, if user wants to expand path: user @path:
        return dest_folder unless dest_folder.nil?
        dest_folder = @transfer_spec_cmdline['destination_root']
        return dest_folder unless dest_folder.nil?
        # default: / on remote, . on local
        case direction.to_s
        when Fasp::TransferSpec::DIRECTION_SEND then dest_folder = '/'
        when Fasp::TransferSpec::DIRECTION_RECEIVE then dest_folder = '.'
        else raise "wrong direction: #{direction}"
        end
        return dest_folder
      end

      # This is how the list of files to be transferred is specified
      # get paths suitable for transfer spec from command line
      # @return [Hash] {source: (mandatory), destination: (optional)}
      # computation is done only once, cache is kept in @transfer_paths
      def ts_source_paths
        # return cache if set
        return @transfer_paths unless @transfer_paths.nil?
        # start with lower priority : get paths from transfer spec on command line
        @transfer_paths = @transfer_spec_cmdline['paths'] if @transfer_spec_cmdline.key?('paths')
        # is there a source list option ?
        file_list = @opt_mgr.get_option(:sources)
        case file_list
        when nil, FILE_LIST_FROM_ARGS
          Log.log.debug('getting file list as parameters')
          # get remaining arguments
          file_list = @opt_mgr.get_next_argument('source file list', expected: :multiple)
          raise CliBadArgument, 'specify at least one file on command line or use '\
            "--sources=#{FILE_LIST_FROM_TRANSFER_SPEC} to use transfer spec" if !file_list.is_a?(Array) || file_list.empty?
        when FILE_LIST_FROM_TRANSFER_SPEC
          Log.log.debug('assume list provided in transfer spec')
          special_case_direct_with_list =
            @opt_mgr.get_option(:transfer, is_type: :mandatory).eql?(:direct) &&
            Fasp::Parameters.ts_has_ascp_file_list(@transfer_spec_cmdline,@opt_mgr.get_option(:transfer_info))
          raise CliBadArgument, 'transfer spec on command line must have sources' if @transfer_paths.nil? && !special_case_direct_with_list
          # here we assume check of sources is made in transfer agent
          return @transfer_paths
        when Array
          Log.log.debug('getting file list as extended value')
          raise CliBadArgument, 'sources must be a Array of String' if !file_list.reject{|f|f.is_a?(String)}.empty?
        else
          raise CliBadArgument, "sources must be a Array, not #{file_list.class}"
        end
        # here, file_list is an Array or String
        if !@transfer_paths.nil?
          Log.log.warn('--sources overrides paths from --ts')
        end
        case @opt_mgr.get_option(:src_type, is_type: :mandatory)
        when :list
          # when providing a list, just specify source
          @transfer_paths = file_list.map{|i|{'source' => i}}
        when :pair
          raise CliBadArgument, "When using pair, provide an even number of paths: #{file_list.length}" unless file_list.length.even?
          @transfer_paths = file_list.each_slice(2).to_a.map{|s, d|{'source' => s, 'destination' => d}}
        else raise 'Unsupported src_type'
        end
        Log.log.debug{"paths=#{@transfer_paths}"}
        return @transfer_paths
      end

      # start a transfer and wait for completion, plugins shall use this method
      # @param transfer_spec [Hash]
      # @param rest_token [Rest] if oauth token regeneration supported
      def start(transfer_spec, rest_token: nil)
        # check parameters
        raise 'transfer_spec must be hash' unless transfer_spec.is_a?(Hash)
        # process :src option
        case transfer_spec['direction']
        when Fasp::TransferSpec::DIRECTION_RECEIVE
          # init default if required in any case
          @transfer_spec_cmdline['destination_root'] ||= destination_folder(transfer_spec['direction'])
        when Fasp::TransferSpec::DIRECTION_SEND
          if transfer_spec.dig('tags', 'aspera', 'node', 'access_key')
            # gen4
            @transfer_spec_cmdline.delete('destination_root') if @transfer_spec_cmdline.key?('destination_root_id')
          elsif transfer_spec.key?('token')
            # gen3
            # in that case, destination is set in return by application (API/upload_setup)
            # but to_folder was used in initial API call
            @transfer_spec_cmdline.delete('destination_root')
          else
            # init default if required
            @transfer_spec_cmdline['destination_root'] ||= destination_folder(transfer_spec['direction'])
          end
        end
        # update command line paths, unless destination already has one
        @transfer_spec_cmdline['paths'] = transfer_spec['paths'] || ts_source_paths
        transfer_spec.merge!(@transfer_spec_cmdline)
        # remove values that are nil (user wants to delete)
        transfer_spec.delete_if { |_key, value| value.nil? }
        # create transfer agent
        set_agent_by_options
        Log.log.debug{"transfer agent is a #{@agent.class}"}
        @agent.start_transfer(transfer_spec, token_regenerator: rest_token)
        # list of : :success or error message
        result = @agent.wait_for_transfers_completion
        @progress_listener.reset
        Fasp::AgentBase.validate_status_list(result)
        send_email_transfer_notification(transfer_spec, result)
        return result
      end

      def send_email_transfer_notification(transfer_spec, statuses)
        return if @opt_mgr.get_option(:notif_to).nil?
        global_status = self.class.session_status(statuses)
        email_vars = {
          global_transfer_status: global_status,
          subject:                "#{PROGRAM_NAME} transfer: #{global_status}",
          body:                   "Transfer is: #{global_status}",
          ts:                     transfer_spec
        }
        @config.send_email_template(email_template_default: DEFAULT_TRANSFER_NOTIF_TMPL, values: email_vars)
      end

      # shut down if agent requires it
      def shutdown
        @agent.shutdown if @agent.respond_to?(:shutdown)
      end
    end
  end
end
