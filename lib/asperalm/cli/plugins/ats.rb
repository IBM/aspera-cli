require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'
require 'asperalm/Connect'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions
      class Ats < Plugin
        ATS_WEB_URL = 'https://ats.aspera.io/pub/v1'
        def declare_options
        end

        def action_list; [ :server, :api_keys ];end

        def cloud_list; [ :aws,:azure,:google,:limelight,:rackspace,:softlayer ];end

        # retrieve structure with all versions available
        def all_servers
          if @all_servers.nil?
            @all_servers=[]
            self.cloud_list.each { |name| @api_pub.read("servers/#{name.to_s.upcase}")[:data].each {|i| @all_servers.push(i)}}
          end
          return @all_servers
        end

        def execute_action
          @api_pub=Rest.new(ATS_WEB_URL)
          command=Main.tool.options.get_next_arg_from_list('command',action_list)
          case command
          when :server #
            command=Main.tool.options.get_next_arg_from_list('command',[:list,:id])
            case command
            when :list #
              return {:type=>:hash_array, :data=>all_servers, :fields=>['id','cloud','region']}
            when :id #
              server_id=Main.tool.options.get_next_arg_from_list('server id',all_servers.map{|i| i['id']})
              server_data=all_servers.select {|i| i['id'].eql?(server_id)}.first
              return {:type=>:key_val_list, :data=>server_data}
            end
          when :api_keys
            raise "not implemented"
          end
        end
      end
    end
  end # Cli
end # Asperalm
