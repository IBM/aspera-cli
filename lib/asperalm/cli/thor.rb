require "thor"
require "asperalm/cli/plugin"

module Asperalm
  module Cli
    class Shares < Thor
      desc "browse PATH", "browse shares repository"
      option :plugin,:required=>false,:banner=>'name',:desc=>"name of plugin"
      def browse(path)
        puts "#{path} #{options[:url]}"
      end
    end

    class ThorMain < Thor
      desc "shares SUBCOMMAND ... ARGS", "Aspera Shares application"
      option :url, required: true
      subcommand "shares", Shares
    end
  end
end
