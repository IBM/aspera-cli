# frozen_string_literal: true

require 'aspera/cli/plugin'
require 'aspera/cli/plugins/node'
require 'aspera/cos_node'

module Aspera
  module Cli
    module Plugins
      class Cos < Plugin
        def initialize(env)
          super(env)
          @service_creds = nil
          options.add_opt_simple(:bucket,'IBM Cloud Object Storage bucket name')
          options.add_opt_simple(:endpoint,'storage endpoint url')
          options.add_opt_simple(:apikey,'storage API key')
          options.add_opt_simple(:crn,'ressource instance id')
          options.add_opt_simple(:service_credentials,'IBM Cloud service credentials (Hash)')
          options.add_opt_simple(:region,'IBM Cloud Object storage region')
        end

        ACTIONS = [:node]

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :node
            bucket_name = options.get_option(:bucket,:mandatory)
            # get service credentials, Hash, e.g. @json:@file:...
            service_credentials = options.get_option(:service_credentials,:optional)
            storage_endpoint = options.get_option(:endpoint,:optional)
            raise 'one of: endpoint or service_credentials is required' if service_credentials.nil? && storage_endpoint.nil?
            raise 'endpoint and service_credentials are mutually exclusive' unless service_credentials.nil? || storage_endpoint.nil?
            if service_credentials.nil?
              service_api_key = options.get_option(:apikey,:mandatory)
              instance_id = options.get_option(:crn,:mandatory)
            else
              # check necessary contents
              raise CliBadArgument,'service_credentials must be a Hash' unless service_credentials.is_a?(Hash)
              ['apikey','resource_instance_id','endpoints'].each do |field|
                raise CliBadArgument,"service_credentials must have a field: #{field}" unless service_credentials.has_key?(field)
              end
              Aspera::Log.dump('service_credentials',service_credentials)
              # get options
              bucket_region = options.get_option(:region,:mandatory)
              # get API key from service credentials
              service_api_key = service_credentials['apikey']
              instance_id = service_credentials['resource_instance_id']
              # read endpoints from service provided in service credentials
              endpoints = Aspera::Rest.new({base_url: service_credentials['endpoints']}).read('')[:data]
              Aspera::Log.dump('endpoints',endpoints)
              storage_endpoint = endpoints.dig('service-endpoints','regional',bucket_region,'public',bucket_region)
              raise "no such region: #{bucket_region}" if storage_endpoint.nil?
              storage_endpoint = 'https://' + storage_endpoint
            end
            api_node = CosNode.new(bucket_name,storage_endpoint,instance_id,service_api_key)
            #command=self.options.get_next_command(Node::ACTIONS)
            #command=self.options.get_next_command(Node::COMMON_ACTIONS)
            command = options.get_next_command([:upload,:download,:info,:access_key,:api_details])
            node_plugin = Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node, add_request_param: api_node.add_ts))
            return node_plugin.execute_action(command)
          end
        end
      end
    end
  end
end
