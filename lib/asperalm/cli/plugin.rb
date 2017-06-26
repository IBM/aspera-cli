module Asperalm
  module Cli
    # base class for plugins modules
    class Plugin
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
