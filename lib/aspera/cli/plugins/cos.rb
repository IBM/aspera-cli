# frozen_string_literal: true

require 'aspera/cli/plugin'
require 'aspera/cli/plugins/node'
require 'aspera/cos_node'
require 'aspera/assert'

module Aspera
  module Cli
    module Plugins
      class Cos < Aspera::Cli::Plugin
        def initialize(env)
          super(env)
          options.declare(:bucket, 'Bucket name')
          options.declare(:endpoint, 'Storage endpoint url')
          options.declare(:apikey, 'Storage API key')
          options.declare(:crn, 'Resource instance id')
          options.declare(:service_credentials, 'IBM Cloud service credentials', types: Hash)
          options.declare(:region, 'Storage region')
          options.declare(:identity, "Authentication url (#{CosNode::IBM_CLOUD_TOKEN_URL})", default: CosNode::IBM_CLOUD_TOKEN_URL)
          options.parse_options!
        end

        ACTIONS = %i[node].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :node
            bucket_name = options.get_option(:bucket, mandatory: true)
            # get service credentials, Hash, e.g. @json:@file:...
            service_credentials = options.get_option(:service_credentials)
            storage_endpoint = options.get_option(:endpoint)
            assert(service_credentials.nil? ^ storage_endpoint.nil?, exception_class: Cli::BadArgument){'endpoint and service_credentials are mutually exclusive'}
            if service_credentials.nil?
              service_api_key = options.get_option(:apikey, mandatory: true)
              instance_id = options.get_option(:crn, mandatory: true)
            else
              params = CosNode.parameters_from_svc_credentials(service_credentials, options.get_option(:region, mandatory: true))
              storage_endpoint = params[:storage_endpoint]
              service_api_key = params[:service_api_key]
              instance_id = params[:instance_id]
            end
            api_node = CosNode.new(bucket_name, storage_endpoint, instance_id, service_api_key, options.get_option(:identity, mandatory: true))
            node_plugin = Node.new(@agents, api: api_node)
            command = options.get_next_command(Node::COMMANDS_COS)
            return node_plugin.execute_action(command)
          end
        end
      end
    end
  end
end
