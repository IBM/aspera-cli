require "thor"
require "asperalm/cli/plugin"

module Asperalm
  module Cli
    class Config < Thor
      @@CONFIG_ITEMS=Plugin.get_plugin_list.unshift(:global)
      desc "list", "list configuration options"
      option :plugin,:required=>false,:banner=>'name',:desc=>"name of plugin"
      def list(plugin=nil)
        puts @@CONFIG_ITEMS.join("\n")
      end
    end

    class ThorMain < Thor
      desc "config SUBCOMMAND ... ARGS", "manage set of tracked repositories"
      subcommand "config", Config
    end
  end
end
