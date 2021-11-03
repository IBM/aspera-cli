module Aspera
  module Cli
    # base class for plugins modules
    class Plugin
      # operation without id
      GLOBAL_OPS=[:create,:list]
      # operation on specific instance
      INSTANCE_OPS=[:modify,:delete,:show]
      ALL_OPS=[GLOBAL_OPS,INSTANCE_OPS].flatten
      # max number of items for list command
      MAX_ITEMS='max'
      # max number of pages for list command
      MAX_PAGES='pmax'

      @@done=false

      def initialize(env)
        @agents=env
        raise StandardError,"execute_action shall be redefined by subclass #{self.class}" unless respond_to?(:execute_action)
        raise StandardError,"ACTIONS shall be redefined by subclass" unless self.class.constants.include?(:ACTIONS)
        unless env[:skip_option_header]
          self.options.parser.separator ""
          self.options.parser.separator "COMMAND: #{self.class.name.split('::').last.downcase}"
          self.options.parser.separator "SUBCOMMANDS: #{self.class.const_get(:ACTIONS).map{ |p| p.to_s}.join(' ')}"
          self.options.parser.separator "OPTIONS:"
        end
        unless @@done
          self.options.add_opt_simple(:value,"extended value for create, update, list filter")
          self.options.add_opt_simple(:property,"name of property to set")
          self.options.add_opt_simple(:id,"resource identifier (#{INSTANCE_OPS.join(",")})")
          self.options.parse_options!
          @@done=true
        end
      end

      def entity_command(command,rest_api,res_class_path,display_fields,id_symb,id_default=nil,use_subkey=false)
        if INSTANCE_OPS.include?(command)
          begin
            one_res_id=self.options.get_option(id_symb,:mandatory)
          rescue => e
            raise e if id_default.nil?
            one_res_id=id_default
          end
          one_res_path="#{res_class_path}/#{one_res_id}"
        end
        # parameters mandatory for create/modify
        if [:create,:modify].include?(command)
          parameters=self.options.get_option(:value,:mandatory)
        end
        # parameters optional for list
        if [:list].include?(command)
          parameters=self.options.get_option(:value,:optional)
        end
        case command
        when :create
          return {:type => :single_object, :data=>rest_api.create(res_class_path,parameters)[:data], :fields=>display_fields}
        when :show
          return {:type => :single_object, :data=>rest_api.read(one_res_path)[:data], :fields=>display_fields}
        when :list
          resp=rest_api.read(res_class_path,parameters)
          data=resp[:data]
          # TODO: not generic : which application is this for ?
          if resp[:http]['Content-Type'].start_with?('application/vnd.api+json')
            data=data[res_class_path]
          end
          data=data[res_class_path] if use_subkey
          return {:type => :object_list, :data=>data, :fields=>display_fields}
        when :modify
          property=self.options.get_option(:property,:optional)
          parameters={property => parameters} unless property.nil?
          rest_api.update(one_res_path,parameters)
          return Main.result_status('modified')
        when :delete
          rest_api.delete(one_res_path)
          return Main.result_status("deleted")
        else
          raise "unknown action: #{command}"
        end
        raise "internal error should not reach here"
      end

      # implement generic rest operations on given resource path
      def entity_action(rest_api,res_class_path,display_fields,id_symb,id_default=nil,use_subkey=false)
        #res_name=res_class_path.gsub(%r{^.*/},'').gsub(%r{s$},'').gsub('_',' ')
        command=self.options.get_next_command(ALL_OPS)
        return entity_command(command,rest_api,res_class_path,display_fields,id_symb,id_default,use_subkey)
      end

      # shortcuts for plugin environment
      def options; return @agents[:options];end

      def transfer; return @agents[:transfer];end

      def config; return @agents[:config];end

      def format; return @agents[:formater];end

      def persistency; return @agents[:persistency];end

    end # Plugin
  end # Cli
end # Aspera
