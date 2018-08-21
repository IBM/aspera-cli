require 'asperalm/cli/plugin'
require 'asperalm/sync'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions, select FASP implementation
      class Sync < Plugin
        def declare_options; end

        def action_list; [ :start ];end

        def execute_action
          command=self.options.get_next_argument('command',action_list)
          case command
          when :start
            args,env=Asperalm::Sync.new(self.options.get_next_argument('params',:single)).compute_args
            return {:type=>:value_list,:name=>'param',:data=>args}
          end
        end
      end # Sync
    end # Plugins
  end # Cli
end # Asperalm
