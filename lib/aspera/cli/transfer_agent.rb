require 'aspera/fasp/local'
require 'aspera/fasp/parameters'
require 'aspera/fasp/connect'
require 'aspera/fasp/node'
require 'aspera/fasp/http_gw'
require 'aspera/cli/listener/logger'
require 'aspera/cli/listener/progress_multi'

module Aspera
  module Cli
    # The Transfer agent is a common interface to start a transfer using
    # one of the supported transfer agents
    # provides CLI options to select one of the transfer agents (FASP/ascp client)
    class TransferAgent
      # special value for --sources : read file list from arguments
      FILE_LIST_FROM_ARGS='@args'
      # special value for --sources : read file list from transfer spec (--ts)
      FILE_LIST_FROM_TRANSFER_SPEC='@ts'
      DEFAULT_TRANSFER_NOTIF_TMPL=<<END_OF_TEMPLATE
From: <%=from_name%> <<%=from_email%>>
To: <<%=to%>>
Subject: <%=subject%>

Transfer is: <%=global_transfer_status%>

<%=ts.to_yaml%>
END_OF_TEMPLATE
      #%
      private_constant :FILE_LIST_FROM_ARGS,:FILE_LIST_FROM_TRANSFER_SPEC,:DEFAULT_TRANSFER_NOTIF_TMPL
      # @param env external objects: option manager, config file manager
      def initialize(env)
        # same as plugin environment
        @env=env
        # command line can override transfer spec
        @transfer_spec_cmdline={'create_dir'=>true}
        # the currently selected transfer agent
        @agent=nil
        @progress_listener=Listener::ProgressMulti.new
        # source/destination pair, like "paths" of transfer spec
        @transfer_paths=nil
        options.set_obj_attr(:ts,self,:option_transfer_spec)
        options.add_opt_simple(:ts,"override transfer spec values (Hash, use @json: prefix), current=#{options.get_option(:ts,:optional)}")
        options.add_opt_simple(:local_resume,"set resume policy (Hash, use @json: prefix), current=#{options.get_option(:local_resume,:optional)}")
        options.add_opt_simple(:to_folder,"destination folder for downloaded files")
        options.add_opt_simple(:sources,"list of source files (see doc)")
        options.add_opt_simple(:transfer_info,"parameters for transfer agent")
        options.add_opt_list(:src_type,[:list,:pair],"type of file list")
        options.add_opt_list(:transfer,[:direct,:httpgw,:connect,:node],"type of transfer agent")
        options.add_opt_list(:progress,[:none,:native,:multi],"type of progress bar")
        options.set_option(:transfer,:direct)
        options.set_option(:src_type,:list)
        options.set_option(:progress,:native) # use native ascp progress bar as it is more reliable
        options.parse_options!
      end

      def options; @env[:options];end

      def config; @env[:config];end

      def option_transfer_spec; @transfer_spec_cmdline; end

      # multiple option are merged
      def option_transfer_spec=(value); @transfer_spec_cmdline.merge!(value); end

      def option_transfer_spec_deep_merge(ts); @transfer_spec_cmdline.deep_merge!(ts); end

      def set_agent_instance(instance)
        @agent=instance
        @agent.add_listener(Listener::Logger.new)
        # use local progress bar if asked so, or if native and non local ascp (because only local ascp has native progress bar)
        if options.get_option(:progress,:mandatory).eql?(:multi) or
        (options.get_option(:progress,:mandatory).eql?(:native) and !options.get_option(:transfer,:mandatory).eql?(:direct))
          @agent.add_listener(@progress_listener)
        end
      end

      # analyze options and create new agent if not already created or set
      def set_agent_by_options
        return nil unless @agent.nil?
        agent_type=options.get_option(:transfer,:mandatory)
        case agent_type
        when :direct
          agent_options=options.get_option(:transfer_info,:optional)
          agent_options=agent_options.symbolize_keys if agent_options.is_a?(Hash)
          new_agent=Fasp::Local.new(agent_options)
          new_agent.quiet=false if options.get_option(:progress,:mandatory).eql?(:native)
        when :httpgw
          httpgw_config=options.get_option(:transfer_info,:mandatory)
          new_agent=Fasp::HttpGW.new(httpgw_config)
        when :connect
          new_agent=Fasp::Connect.new
        when :node
          # way for code to setup alternate node api in advance
          # support: @preset:<name>
          # support extended values
          node_config=options.get_option(:transfer_info,:optional)
          # if not specified: use default node
          if node_config.nil?
            param_set_name=config.get_plugin_default_config_name(:node)
            raise CliBadArgument,"No default node configured, Please specify --#{:transfer_info.to_s.gsub('_','-')}" if param_set_name.nil?
            node_config=config.preset_by_name(param_set_name)
          end
          Log.log.debug("node=#{node_config}")
          raise CliBadArgument,"the node configuration shall be Hash, not #{node_config.class} (#{node_config}), use either @json:<json> or @preset:<parameter set name>" unless node_config.is_a?(Hash)
          # here, node_config is a Hash
          node_config=node_config.symbolize_keys
          # Check mandatory params
          [:url,:username,:password].each { |k| raise CliBadArgument,"missing parameter [#{k}] in node specification: #{node_config}" unless node_config.has_key?(k) }
          if node_config[:password].match(/^Bearer /)
            node_api=Rest.new({
              base_url: node_config[:url],
              headers: {
              'X-Aspera-AccessKey'=>node_config[:username],
              'Authorization'     =>node_config[:password]}})
          else
            node_api=Rest.new({
              base_url: node_config[:url],
              auth:     {
              type:     :basic,
              username: node_config[:username],
              password: node_config[:password]
              }})
          end
          new_agent=Fasp::Node.new(node_api)
          # add root id if it's an access key
          new_agent.options={root_id: node_config[:root_id]} if node_config.has_key?(:root_id)
        else
          raise "Unexpected transfer agent type: #{agent_type}"
        end
        set_agent_instance(new_agent)
        return nil
      end

      # return destination folder for transfers
      # sets default if needed
      # param: 'send' or 'receive'
      def destination_folder(direction)
        dest_folder=options.get_option(:to_folder,:optional)
        return dest_folder unless dest_folder.nil?
        dest_folder=@transfer_spec_cmdline['destination_root']
        return dest_folder unless dest_folder.nil?
        # default: / on remote, . on local
        case direction.to_s
        when 'send';dest_folder='/'
        when 'receive';dest_folder='.'
        else raise "wrong direction: #{direction}"
        end
        return dest_folder
      end

      # This is how the list of files to be transfered is specified
      # get paths suitable for transfer spec from command line
      # @return {:source=>(mandatory), :destination=>(optional)}
      # computation is done only once, cache is kept in @transfer_paths
      def ts_source_paths
        # return cache if set
        return @transfer_paths unless @transfer_paths.nil?
        # start with lower priority : get paths from transfer spec on command line
        @transfer_paths=@transfer_spec_cmdline['paths'] if @transfer_spec_cmdline.has_key?('paths')
        # is there a source list option ?
        file_list=options.get_option(:sources,:optional)
        case file_list
        when nil,FILE_LIST_FROM_ARGS
          Log.log.debug("getting file list as parameters")
          # get remaining arguments
          file_list=options.get_next_argument("source file list",:multiple)
          raise CliBadArgument,"specify at least one file on command line or use --sources=#{FILE_LIST_FROM_TRANSFER_SPEC} to use transfer spec" if !file_list.is_a?(Array) or file_list.empty?
        when FILE_LIST_FROM_TRANSFER_SPEC
          Log.log.debug("assume list provided in transfer spec")
          special_case_direct_with_list=options.get_option(:transfer,:mandatory).eql?(:direct) and Fasp::Parameters.ts_has_file_list(@transfer_spec_cmdline)
          raise CliBadArgument,"transfer spec on command line must have sources" if @transfer_paths.nil? and !special_case_direct_with_list
          # here we assume check of sources is made in transfer agent
          return @transfer_paths
        when Array
          Log.log.debug("getting file list as extended value")
          raise CliBadArgument,"sources must be a Array of String" if !file_list.select{|f|!f.is_a?(String)}.empty?
        else
          raise CliBadArgument,"sources must be a Array, not #{file_list.class}"
        end
        # here, file_list is an Array or String
        if !@transfer_paths.nil?
          Log.log.warn("--sources overrides paths from --ts")
        end
        case options.get_option(:src_type,:mandatory)
        when :list
          # when providing a list, just specify source
          @transfer_paths=file_list.map{|i|{'source'=>i}}
        when :pair
          raise CliBadArgument,"When using pair, provide an even number of paths: #{file_list.length}" unless file_list.length.even?
          @transfer_paths=file_list.each_slice(2).to_a.map{|s,d|{'source'=>s,'destination'=>d}}
        else raise "Unsupported src_type"
        end
        Log.log.debug("paths=#{@transfer_paths}")
        return @transfer_paths
      end

      # start a transfer and wait for completion, plugins shall use this method
      # @param transfer_spec
      # @param tr_opts specific options for the transfer_agent
      # tr_opts[:src] specifies how destination_root is set (how transfer spec was generated)
      # other options are carried to specific agent
      def start(transfer_spec,tr_opts)
        # check parameters
        raise "transfer_spec must be hash" unless transfer_spec.is_a?(Hash)
        raise "tr_opts must be hash" unless tr_opts.is_a?(Hash)
        # process :src option
        case transfer_spec['direction']
        when 'receive'
          # init default if required in any case
          @transfer_spec_cmdline['destination_root']||=destination_folder(transfer_spec['direction'])
        when 'send'
          case tr_opts[:src]
          when :direct
            # init default if required
            @transfer_spec_cmdline['destination_root']||=destination_folder(transfer_spec['direction'])
          when :node_gen3
            # in that case, destination is set in return by application (API/upload_setup)
            # but to_folder was used in initial API call
            @transfer_spec_cmdline.delete('destination_root')
          when :node_gen4
            @transfer_spec_cmdline.delete('destination_root') if @transfer_spec_cmdline.has_key?('destination_root_id')
          else
            raise StandardError,"InternalError: unsupported value: #{tr_opts[:src]}"
          end
        end

        # only used here
        tr_opts.delete(:src)

        # update command line paths, unless destination already has one
        @transfer_spec_cmdline['paths']=transfer_spec['paths'] || ts_source_paths

        transfer_spec.merge!(@transfer_spec_cmdline)
        # create transfer agent
        self.set_agent_by_options
        Log.log.debug("transfer agent is a #{@agent.class}")
        @agent.start_transfer(transfer_spec,tr_opts)
        result=@agent.wait_for_transfers_completion
        @progress_listener.reset
        Fasp::Manager.validate_status_list(result)
        send_email_transfer_notification(transfer_spec,result)
        return result
      end

      def send_email_transfer_notification(transfer_spec,statuses)
        return if options.get_option(:notif_to,:optional).nil?
        global_status=self.class.session_status(statuses)
        email_vars={
          global_transfer_status: global_status,
          subject: "ascli transfer: #{global_status}",
          body: "Transfer is: #{global_status}",
          ts: transfer_spec
        }
        @env[:config].send_email_template(email_vars,DEFAULT_TRANSFER_NOTIF_TMPL)
      end

      # @return :success if all sessions statuses returned by "start" are success
      # else return the first error exception object
      def self.session_status(statuses)
        error_statuses=statuses.select{|i|!i.eql?(:success)}
        return :success if error_statuses.empty?
        return error_statuses.first
      end

      # shut down if agent requires it
      def shutdown
        @agent.shutdown if @agent.respond_to?(:shutdown)
      end

    end
  end
end
