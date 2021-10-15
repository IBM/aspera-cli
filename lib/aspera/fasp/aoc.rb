require 'aspera/fasp/node'
require 'aspera/log'
require 'aspera/aoc.rb'

module Aspera
  module Fasp
    class Aoc < Node
      def initialize(aoc_options)
        @app=aoc_options[:app] || AoC::FILES_APP
        @api_aoc=AoC.new(aoc_options)
        Log.log.warn("Under Development")
        server_node_file = @api_aoc.resolve_node_file(server_home_node_file,server_folder)
        # force node as transfer agent
        node_api=Fasp::Node.new(@api_aoc.get_node_api(client_node_file[:node_info],scope: AoC::SCOPE_NODE_USER))
        super(node_api)
        # additional node to node TS info
        @add_ts={
          'remote_access_key'   => server_node_file[:node_info]['access_key'],
          'destination_root_id' => server_node_file[:file_id]
        }
      end
    end
  end
end
