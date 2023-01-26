# frozen_string_literal: true

require 'aspera/cli/plugin'
require 'aspera/cli/plugins/node'
require 'aspera/cos_node'

module Aspera
  module Cli
    module Plugins
      class Cos < Aspera::Cli::Plugin
        def initialize(env)
          super(env)
          @service_creds = nil
          options.add_opt_simple(:bucket, 'Bucket name')
          options.add_opt_simple(:endpoint, 'Storage endpoint url')
          options.add_opt_simple(:apikey, 'Storage API key')
          options.add_opt_simple(:crn, 'Ressource instance id')
          options.add_opt_simple(:service_credentials, 'IBM Cloud service credentials (Hash)')
          options.add_opt_simple(:region, 'Storage region')
          options.add_opt_simple(:identity, "Authentication url (#{CosNode::IBM_CLOUD_TOKEN_URL})")
          options.set_option(:identity, CosNode::IBM_CLOUD_TOKEN_URL)
          options.parse_options!
        end

        ACTIONS = %i[node].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :node
            bucket_name = options.get_option(:bucket, is_type: :mandatory)
            # get service credentials, Hash, e.g. @json:@file:...
            service_credentials = options.get_option(:service_credentials)
            storage_endpoint = options.get_option(:endpoint)
            raise CliBadArgument, 'one of: endpoint or service_credentials is required' if service_credentials.nil? && storage_endpoint.nil?
            raise CliBadArgument, 'endpoint and service_credentials are mutually exclusive' unless service_credentials.nil? || storage_endpoint.nil?
            if service_credentials.nil?
              service_api_key = options.get_option(:apikey, is_type: :mandatory)
              instance_id = options.get_option(:crn, is_type: :mandatory)
            else
              params = CosNode.parameters_from_svc_creds(service_credentials, options.get_option(:region, is_type: :mandatory))
              storage_endpoint = params[:storage_endpoint]
              service_api_key = params[:service_api_key]
              instance_id = params[:instance_id]
            end
            api_node = CosNode.new(bucket_name, storage_endpoint, instance_id, service_api_key, options.get_option(:identity, is_type: :mandatory))
            node_plugin = Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node))
            command = options.get_next_command(Node::COMMANDS_COS)
            return node_plugin.execute_action(command)
          end
        end
      end
    end
  end
end
