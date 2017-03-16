require "thor"
require "asperalm/cli/plugin"

module Asperalm
  module Cli
    class Config < Thor
      desc "list", "Adds a remote named <name> for the repository at <url>"
      option :product => "<product>"
      def list(product=nil)
        puts "list of plugins: #{Plugin.get_plugin_list}"
      end
    end

    class ThorMain < Thor
      desc "config SUBCOMMAND ...ARGS", "manage set of tracked repositories"
      subcommand "config", Config
    end
  end
end
