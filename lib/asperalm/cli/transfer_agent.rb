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
        @transfer_spec_default={}
        @agent=nil
      end
      public

      def option_transfer_spec; @transfer_spec_default; end

      def option_transfer_spec=(value); @transfer_spec_default.merge!(value); end

      def option_to_folder; @transfer_spec_default['destination_root']; end

      def option_to_folder=(value); @transfer_spec_default.merge!({'destination_root'=>value}); end

      def declare_transfer_options
        Main.instance.options.set_obj_attr(:ts,self,:option_transfer_spec)
        Main.instance.options.set_obj_attr(:to_folder,self,:option_to_folder)
        Main.instance.options.add_opt_simple(:ts,"override transfer spec values (Hash, use @json: prefix), current=#{Main.instance.options.get_option(:ts,:optional)}")
        Main.instance.options.add_opt_simple(:to_folder,"destination folder for downloaded files")
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
              @transfer_spec_default['EX_fasp_proxy_url']=Main.instance.options.get_option(:fasp_proxy,:optional)
            end
            if !Main.instance.options.get_option(:http_proxy,:optional).nil?
              @transfer_spec_default['EX_http_proxy_url']=Main.instance.options.get_option(:http_proxy,:optional)
            end
            # TODO: option to choose progress format
            # here we disable native stdout progress
            @agent.quiet=true
            Log.log.debug(">>>>#{@transfer_spec_default}".red)
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
        # set default if needed
        if @transfer_spec_default['destination_root'].nil?
          # default: / on remote, . on local
          case direction
          when 'send'
            @transfer_spec_default['destination_root']='/'
          when 'receive'
            @transfer_spec_default['destination_root']='.'
          else
            raise "wrong direction: #{direction}"
          end
        end
        return @transfer_spec_default['destination_root']
      end

      # plugins shall use this method to start a transfer
      # @param: ts_source specifies how destination_root is set (how transfer spec was generated)
      # and not the default one
      def start_transfer_wait_result(transfer_info)
        raise "transfer_info must be hash" unless transfer_info.is_a?(Hash)
        raise "transfer_info must have :ts" unless transfer_info.has_key?(:ts)
        transfer_spec=transfer_info[:ts]
        ts_source=transfer_info[:src]
        options={}
        options[:regenerate_token]=transfer_info[:regen] if transfer_info.has_key?(:regen)
        # initialize transfert agent
        self.agent
        case transfer_spec['direction']
        when 'receive'
          # init default if required in any case
          destination_folder(transfer_spec['direction'])
        when 'send'
          case ts_source
          when :direct
            # init default if required
            destination_folder(transfer_spec['direction'])
          when :node_gen3
            # in that case, destination is set in return by application (API/upload_setup)
            # but to_folder was used in intial api call
            @transfer_spec_default.delete('destination_root')
          when :node_gen4
            @transfer_spec_default['destination_root']='/'
          else
            raise StandardError,"InternalError: unsupported value: #{ts_source}"
          end
        end

        transfer_spec.merge!(@transfer_spec_default)
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
