module Asperalm
  module Cli
    # base class for plugins modules
    class Plugin
      attr_accessor :options
      def initialize(a_option_parser)
        self.options=a_option_parser
      end
      def set_options
        self.options.separator "    no option"
      end
      def action_list
        ["list to be provided in plugin: #{self.class}"]
      end
      def execute_action
        raise StandardError,"This method shall be redefined by subclass"
      end
    end # Plugin
  end # Cli
end # Asperalm
