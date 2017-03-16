require 'asperalm/cli/plugin'

module Asperalm
  module Cli
    module Plugins
      class Tool < Plugin
        def command_list; [:listconfig];end

        def set_options
        end

        def dojob(command,argv)
          case command
          when :listconfig
          end
          puts ">>>#{command}"
        end
      end
    end
  end
end
