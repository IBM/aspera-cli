class ::Hash
  def deep_merge!(second)
    merger = proc { |key, v1, v2| v1.is_a?(Hash) and v2.is_a?(Hash) ? v1.merge!(v2, &merger) : v2 }
    self.merge!(second, &merger)
  end
end

module Asperalm
  module Cli
    # base class for plugins modules
    class Plugin
      GLOBAL_OPS=[:create,:list]
      INSTANCE_OPS=[:modify,:delete,:show]
      ALL_OPS=[GLOBAL_OPS,INSTANCE_OPS].flatten

      @@done=false

      def initialize(env)
        @agents=env
        self.options.parser.separator "COMMAND: #{self.class.name.split('::').last.downcase}"
        self.options.parser.separator "SUBCOMMANDS: #{self.action_list.map{ |p| p.to_s}.join(', ')}"
        self.options.parser.separator "OPTIONS:"
        unless @@done
          self.options.add_opt_simple(:value,"extended value for create, update, list filter")
          self.options.add_opt_simple(:id,"resource identifier (#{INSTANCE_OPS.join(",")})")
          self.options.parse_options!
          @@done=true
        end
      end

      # first level command for the main tool
      def self.name_sym;self.name.split('::').last.downcase.to_sym;end

      # implement generic rest operations on given resource path
      def entity_action(rest_api,res_class_path,display_fields,id_symb)
        res_name=res_class_path.gsub(%r{.*/},'').gsub(%r{^s$},'').gsub('_',' ')
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

      def declare_options
        raise StandardError,"declare_options shall be redefined by subclass"
      end

      def action_list
        raise StandardError,"action_list shall be redefined by subclass"
      end

      def execute_action
        raise StandardError,"execute_action shall be redefined by subclass"
      end
    end # Plugin
  end # Cli
end # Asperalm
