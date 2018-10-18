require 'asperalm/fasp/local'
require 'asperalm/fasp/connect'
require 'asperalm/fasp/node'
require 'singleton'

module Asperalm
  module Cli
    # options to select one of the transfer agents
    class TransferAgent
      include Singleton
      private
      def initialize
        @transfer_spec_cmdline={}
        @agent=nil
        @transfer_paths=nil
      end
      public

      def option_transfer_spec; @transfer_spec_cmdline; end

      def option_transfer_spec=(value); @transfer_spec_cmdline.merge!(value); end

      def declare_transfer_options
        Main.instance.options.set_obj_attr(:ts,self,:option_transfer_spec)
        Main.instance.options.add_opt_simple(:ts,"override transfer spec values (Hash, use @json: prefix), current=#{Main.instance.options.get_option(:ts,:optional)}")
        Main.instance.options.add_opt_simple(:to_folder,"destination folder for downloaded files")
        Main.instance.options.add_opt_simple(:sources,"list of source files (see doc)")
        Main.instance.options.add_opt_list(:transfer,[:direct,:connect,:node],"type of transfer")
        Main.instance.options.add_opt_simple(:transfer_node,"name of configuration used to transfer when using --transfer=node")
        Main.instance.options.set_option(:transfer,:direct)
      end

      def agent
        if @agent.nil?
          case Main.instance.options.get_option(:transfer,:mandatory)
          when :direct
            @agent=Fasp::Local.instance
            if !Main.instance.options.get_option(:fasp_proxy,:optional).nil?
              @transfer_spec_cmdline['EX_fasp_proxy_url']=Main.instance.options.get_option(:fasp_proxy,:optional)
            end
            if !Main.instance.options.get_option(:http_proxy,:optional).nil?
              @transfer_spec_cmdline['EX_http_proxy_url']=Main.instance.options.get_option(:http_proxy,:optional)
            end
            # TODO: option to choose progress format
            # here we disable native stdout progress
            @agent.quiet=true
            Log.log.debug(">>>>#{@transfer_spec_cmdline}".red)
          when :connect
            @agent=Fasp::Connect.instance
          when :node
            # support: @param:<name>
            # support extended values
            transfer_node_spec=Main.instance.options.get_option(:transfer_node,:optional)
            # of not specified, use default node
            case transfer_node_spec
            when nil
              param_set_name=Plugins::Config.instance.get_plugin_default_config_name(:node)
              raise CliBadArgument,"No default node configured, Please specify --transfer-node" if param_set_name.nil?
              node_config=config_presets[param_set_name]
            when /^@param:/
              param_set_name=transfer_node_spec.gsub!(/^@param:/,'')
              Log.log.debug("param_set_name=#{param_set_name}")
              raise CliBadArgument,"no such parameter set: [#{param_set_name}] in config file" if !config_presets.has_key?(param_set_name)
              node_config=config_presets[param_set_name]
            else
              node_config=ExtendedValue.parse(:transfer_node,transfer_node_spec)
            end
            Log.log.debug("node=#{node_config}")
            raise CliBadArgument,"the node configuration shall be a hash, use either @json:<json> or @param:<parameter set name>" if !node_config.is_a?(Hash)
            # now check there are required parameters
            sym_config={}
            [:url,:username,:password].each do |param|
              raise CliBadArgument,"missing parameter [#{param}] in node specification: #{node_config}" if !node_config.has_key?(param.to_s)
              sym_config[param]=node_config[param.to_s]
            end
            @agent=Fasp::Node.instance
            Fasp::Node.instance.node_api=Rest.new({:base_url=>sym_config[:url],:auth_type=>:basic,:basic_username=>sym_config[:username], :basic_password=>sym_config[:password]})
          else raise "ERROR"
          end
          @agent.add_listener(Listener::Logger.new)
          @agent.add_listener(Listener::ProgressMulti.new)
        end
        return @agent
      end

      # return destination folder for transfers
      # sets default if needed
      # param: 'send' or 'receive'
      def destination_folder(direction)
        dest_folder=Main.instance.options.get_option(:to_folder,:optional)
        return dest_folder unless dest_folder.nil?
        dest_folder=@transfer_spec_cmdline['destination_root']
        return dest_folder unless dest_folder.nil?
        # default: / on remote, . on local
        case direction
        when 'send';dest_folder='/'
        when 'receive';dest_folder='.'
        else raise "wrong direction: #{direction}"
        end
        return dest_folder
      end

      # get list of {:source=>(mandatory), :destination=>(optional)}
      def transfer_paths_from_options(override_with=nil)
        return override_with unless override_with.nil?
        return @transfer_paths unless @transfer_paths.nil?
        # start with lower priority
        @transfer_paths=@transfer_spec_cmdline['paths'] if @transfer_spec_cmdline.has_key?('paths')
        sources=Main.instance.options.get_option(:sources,:optional)
        if !sources.nil?
          Log.log.warn("--sources overrides paths from --ts") unless @transfer_paths.nil?
          sources=Main.instance.options.get_next_argument("source file list",:multiple) if sources.eql?('@args')
          raise "sources must be a Array" unless sources.is_a?(Array)
          @transfer_paths=sources.map{|i|{'source'=>i}}
        end
        raise CliBadArgument,"command line must have either --sources or --ts with paths" if @transfer_paths.nil?
        return @transfer_paths
      end

      # plugins shall use this method to start a transfer
      # @param: options[:src] specifies how destination_root is set (how transfer spec was generated)
      # and not the default one
      def start_transfer_wait_result(transfer_spec,options)
        raise "transfer_spec must be hash" unless transfer_spec.is_a?(Hash)
        raise "options must be hash" unless options.is_a?(Hash)
        # initialize transfert agent
        self.agent
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
        @transfer_spec_cmdline['paths']=transfer_paths_from_options(transfer_spec['paths'])

        transfer_spec.merge!(@transfer_spec_cmdline)
        # add bypass keys if there is a token, also prevents connect plugin to ask password
        transfer_spec['authentication']='token' if transfer_spec.has_key?('token')
        Log.log.debug("mgr is a #{@agent.class}")
        @agent.start_transfer(transfer_spec,options)
        return Main.result_nothing
      end

      def shutdown(p)
        @agent.shutdown(p) unless @agent.nil?
      end
    end
  end
end
