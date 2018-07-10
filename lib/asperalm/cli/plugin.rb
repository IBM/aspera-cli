module Asperalm
  module Cli
    # base class for plugins modules
    class Plugin
      # set reference to CLI manager
      def self.manager=(manager)
        @@manager=manager
      end

      def self.result_none
        return {:type => :empty, :data => :nil }
      end

      def self.result_status(status)
        return {:type => :status, :data => status }
      end

      def self.result_success
        return result_status('complete')
      end
      GLOBAL_OPS=[:create,:list]
      INSTANCE_OPS=[:modify,:delete,:show]
      ALL_OPS=[GLOBAL_OPS,INSTANCE_OPS].flatten

      # implement generic rest operations on given resource path
      def self.entity_action(rest_api,res_class_path,display_fields,id_symb)
        res_name=res_class_path.gsub(%r{.*/},'').gsub(%r{^s$},'').gsub('_',' ')
        command=Main.tool.options.get_next_argument('command',ALL_OPS)
        if INSTANCE_OPS.include?(command)
          one_res_id=Main.tool.options.get_option(id_symb,:mandatory)
          one_res_path="#{res_class_path}/#{one_res_id}"
        end
        if [:create,:modify].include?(command)
          parameters=Main.tool.options.get_option(:value,:mandatory)
        end
        if [:list].include?(command)
          parameters=Main.tool.options.get_option(:value,:optional)
        end
        case command
        when :create
          return {:type => :key_val_list, :data=>rest_api.create(res_class_path,parameters)[:data], :fields=>display_fields}
        when :show
          return {:type => :key_val_list, :data=>rest_api.read(one_res_path)[:data], :fields=>display_fields}
        when :list
          return {:type => :hash_array, :data=>rest_api.read(res_class_path,parameters)[:data], :fields=>display_fields}
        when :modify
          rest_api.update(one_res_path,parameters)
          return Main.result_status('modified')
        when :delete
          rest_api.delete(one_res_path)
          return Main.result_status("deleted")
        end
      end

      # helper : get CLI manager
      def manager
        @@manager
      end

      # helper : get CLI option parser
      def options
        @@manager.options
      end

      def initialize
        super()
      end

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
