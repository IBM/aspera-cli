require 'asperalm/fasp/local'
require 'asperalm/fasp/connect'
require 'asperalm/fasp/node'
require 'asperalm/cli/listener/logger'
require 'asperalm/cli/listener/progress_multi'

module Asperalm
  module Cli
    # options to select one of the transfer agents (fasp client)
    class TransferAgent
      private
      @@ARGS_PARAM='@args'
      @@TS_PARAM='@ts'
      def initialize(env)
        @env=env
        @transfer_spec_cmdline={}
        @agent=nil
        @transfer_paths=nil
      end
      public

      def option_transfer_spec; @transfer_spec_cmdline; end

      def option_transfer_spec=(value); @transfer_spec_cmdline.merge!(value); end

      def declare_transfer_options
        @env[:options].set_obj_attr(:ts,self,:option_transfer_spec)
        @env[:options].add_opt_simple(:ts,"override transfer spec values (Hash, use @json: prefix), current=#{@env[:options].get_option(:ts,:optional)}")
        @env[:options].add_opt_simple(:to_folder,"destination folder for downloaded files")
        @env[:options].add_opt_simple(:sources,"list of source files (see doc)")
        @env[:options].add_opt_list(:transfer,[:direct,:connect,:node,:files],"type of transfer")
        @env[:options].add_opt_simple(:transfer_info,"additional information for transfer client")
        @env[:options].set_option(:transfer,:direct)
      end

      # @return one of the Fasp:: agents based on parameters
      def set_agent_by_options
        if @agent.nil?
          case @env[:options].get_option(:transfer,:mandatory)
          when :direct
            @agent=Fasp::Local.instance
            if !@env[:options].get_option(:fasp_proxy,:optional).nil?
              @transfer_spec_cmdline['EX_fasp_proxy_url']=@env[:options].get_option(:fasp_proxy,:optional)
            end
            if !@env[:options].get_option(:http_proxy,:optional).nil?
              @transfer_spec_cmdline['EX_http_proxy_url']=@env[:options].get_option(:http_proxy,:optional)
            end
            # TODO: option to choose progress format
            # here we disable native stdout progress
            @agent.quiet=true
            Log.log.debug(">>>>#{@transfer_spec_cmdline}".red)
          when :connect
            @agent=Fasp::Connect.instance
          when :node
            @agent=Fasp::Node.instance
            # way for code to setup alternate node api in avance
            if @agent.node_api.nil?
              # support: @param:<name>
              # support extended values
              node_config=@env[:options].get_option(:transfer_info,:optional)
              # of not specified, use default node
              if node_config.nil?
                param_set_name=@env[:config].get_plugin_default_config_name(:node)
                raise CliBadArgument,"No default node configured, Please specify --#{:transfer_info.to_s.gsub('_','-')}" if param_set_name.nil?
                node_config=@env[:config].preset_by_name(param_set_name)
              end
              Log.log.debug("node=#{node_config}")
              raise CliBadArgument,"the node configuration shall be a hash, use either @json:<json> or @preset:<parameter set name>" if !node_config.is_a?(Hash)
              # now check there are required parameters
              sym_config={}
              [:url,:username,:password].each do |param|
                raise CliBadArgument,"missing parameter [#{param}] in node specification: #{node_config}" if !node_config.has_key?(param.to_s)
                sym_config[param]=node_config[param.to_s]
              end
              @agent.node_api=Rest.new({:base_url=>sym_config[:url],:auth_type=>:basic,:basic_username=>sym_config[:username], :basic_password=>sym_config[:password]})
            end
          else raise "ERROR"
          end
          @agent.add_listener(Listener::Logger.new)
          @agent.add_listener(Listener::ProgressMulti.new)
        end
        return nil
      end

      # return destination folder for transfers
      # sets default if needed
      # param: 'send' or 'receive'
      def destination_folder(direction)
        dest_folder=@env[:options].get_option(:to_folder,:optional)
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
      def ts_source_paths
        return @transfer_paths unless @transfer_paths.nil?
        # start with lower priority : get paths from transfer spec on command line
        @transfer_paths=@transfer_spec_cmdline['paths'] if @transfer_spec_cmdline.has_key?('paths')
        # is there a source list option ?
        file_list=@env[:options].get_option(:sources,:optional)
        case file_list
        when nil,@@ARGS_PARAM
          Log.log.debug("getting file list as parameters")
          file_list=@env[:options].get_next_argument("source file list",:multiple)
          raise CliBadArgument,"specify at least one file on command line or use --sources=#{@@TS_PARAM} to use transfer spec" if !file_list.is_a?(Array) or file_list.empty?
        when @@TS_PARAM
          Log.log.debug("assume list provided in transfer spec")
          raise CliBadArgument,"transfer spec on command line must have sources" if @transfer_paths.nil?
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
        @transfer_paths=file_list.map{|i|{'source'=>i}}
        return @transfer_paths
      end

      # plugins shall use this method to start a transfer
      # @param: options[:src] specifies how destination_root is set (how transfer spec was generated)
      # and not the default one
      def start(transfer_spec,options)
        raise "transfer_spec must be hash" unless transfer_spec.is_a?(Hash)
        raise "options must be hash" unless options.is_a?(Hash)
        case transfer_spec['direction']
        when 'receive'
          # init default if required in any case
          @transfer_spec_cmdline['destination_root']=destination_folder(transfer_spec['direction'])
        when 'send'
          case options[:src]
          when :direct
            # init default if required
            @transfer_spec_cmdline['destination_root']=destination_folder(transfer_spec['direction'])
          when :node_gen3
            # in that case, destination is set in return by application (API/upload_setup)
            # but to_folder was used in intial api call
            @transfer_spec_cmdline.delete('destination_root')
          when :node_gen4
            @transfer_spec_cmdline['destination_root']='/'
          else
            raise StandardError,"InternalError: unsupported value: #{options[:src]}"
          end
        end

        # only used here
        options.delete(:src)

        #  update command line paths, unless destination already has one
        @transfer_spec_cmdline['paths']=transfer_spec['paths'] || ts_source_paths

        transfer_spec.merge!(@transfer_spec_cmdline)
        # add bypass keys if there is a token, also prevents connect plugin to ask password
        transfer_spec['authentication']='token' if transfer_spec.has_key?('token')
        self.set_agent_by_options
        Log.log.debug("mgr is a #{@agent.class}")
        @agent.start_transfer(transfer_spec,options)
        return @agent.wait_for_transfers_completion
      end

      def shutdown
        @agent.shutdown if @agent.respond_to?(:shutdown)
      end

      # @return list of status
      def wait_for_transfers_completion
        raise "no transfer agent" if @agent.nil?
        return @agent.wait_for_transfers_completion
      end

      # helper method for above method
      def self.session_status(statuses)
        error_statuses=statuses.select{|i|!i.eql?(:success)}
        return :success if error_statuses.empty?
        return error_statuses.first
      end
    end
  end
end
