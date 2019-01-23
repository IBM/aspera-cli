module Asperalm
  module Cli
    # base class for plugins modules
    class Plugin
      GLOBAL_OPS=[:create,:list]
      INSTANCE_OPS=[:modify,:delete,:show]
      ALL_OPS=[GLOBAL_OPS,INSTANCE_OPS].flatten
      private_constant :GLOBAL_OPS,:INSTANCE_OPS,:ALL_OPS

      @@done=false

      def initialize(env)
        Log.log.debug("--|>>> #{self.class.constants}")
        @agents=env
        raise StandardError,"execute_action shall be redefined by subclass" unless respond_to?(:execute_action)
        raise StandardError,"ACTIONS shall be redefined by subclass" unless self.class.constants.include?(:ACTIONS)
        unless env[:skip_option_header]
          self.options.parser.separator "COMMAND: #{self.class.name.split('::').last.downcase}"
          self.options.parser.separator "SUBCOMMANDS: #{self.actions.map{ |p| p.to_s}.join(', ')}"
          self.options.parser.separator "OPTIONS:"
        end
        unless @@done
          self.options.add_opt_simple(:value,"extended value for create, update, list filter")
          self.options.add_opt_simple(:id,"resource identifier (#{INSTANCE_OPS.join(",")})")
          self.options.parse_options!
          @@done=true
        end
      end
      
      def actions; self.class.const_get(:ACTIONS); end

      # implement generic rest operations on given resource path
      def entity_action(rest_api,res_class_path,display_fields,id_symb)
        #res_name=res_class_path.gsub(%r{^.*/},'').gsub(%r{s$},'').gsub('_',' ')
        command=self.options.get_next_command(ALL_OPS)
        if INSTANCE_OPS.include?(command)
          one_res_id=self.options.get_option(id_symb,:mandatory)
          one_res_path="#{res_class_path}/#{one_res_id}"
        end
        if [:create,:modify].include?(command)
          parameters=self.options.get_option(:value,:mandatory)
        end
        if [:list].include?(command)
          parameters=self.options.get_option(:value,:optional)
        end
        case command
        when :create
          return {:type => :single_object, :data=>rest_api.create(res_class_path,parameters)[:data], :fields=>display_fields}
        when :show
          return {:type => :single_object, :data=>rest_api.read(one_res_path)[:data], :fields=>display_fields}
        when :list
          return {:type => :object_list, :data=>rest_api.read(res_class_path,parameters)[:data], :fields=>display_fields}
        when :modify
          rest_api.update(one_res_path,parameters)
          return Main.result_status('modified')
        when :delete
          rest_api.delete(one_res_path)
          return Main.result_status("deleted")
        end
      end

      def options;@agents[:options];end

      def transfer;@agents[:transfer];end

      def config;return @agents[:config];end

      def format;return @agents[:formater];end

    end # Plugin
  end # Cli
end # Asperalm
