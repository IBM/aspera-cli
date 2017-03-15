require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Tool < Plugin
        def command_list; [:test];end

        def init_defaults
        end

        def set_options
        end

        def dojob(command,argv)
          puts ">>>#{command}"
        end
      end
    end
  end
end
