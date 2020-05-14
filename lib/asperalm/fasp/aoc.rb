require 'asperalm/fasp/node'
require 'asperalm/log'
require 'asperalm/on_cloud.rb'

module Asperalm
  module Fasp
    class Aoc < Node
      def initialize(on_cloud_options)
        @app=on_cloud_options[:app] || OnCloud::FILES_APP
        @api_oncloud=OnCloud.new(on_cloud_options)
        Log.log.warn("Under Development")
        server_node_file = @api_oncloud.resolve_node_file(server_home_node_file,server_folder)
        # force node as transfer agent
        node_api=Fasp::Node.new(@api_oncloud.get_node_api(client_node_file[:node_info],OnCloud::SCOPE_NODE_USER))
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
