require 'singleton'

module Asperalm
  module Cli
    # The main CLI class
    class TransferAgent
      include Singleton
      private
      def initialize
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
      public
      def self.declare_transfer_options
        Main.instance.options.add_opt_list(:transfer,[:direct,:connect,:node],"type of transfer")
        Main.instance.options.add_opt_simple(:transfer_node,"name of configuration used to transfer when using --transfer=node")
        Main.instance.options.set_option(:transfer,:direct)
      end
      attr_reader :agent
      # transfer agent singleton
      def transfer_manager
        if @agent.nil?
        end
        return @agent
      end
    end
  end
end
