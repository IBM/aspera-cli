# frozen_string_literal: true

require 'aspera/cli/plugins/base'
require 'aspera/cli/plugins/node'
require 'aspera/api/cos_node'
require 'aspera/assert'

module Aspera
  module Cli
    module Plugins
      class Cos < Base
        application_name 'IBM Cloud Object Storage'

        command :node, description: 'Execute COS node commands',
          mount: {plugin: Node, instance: :cos_node_plugin, only: Node::COMMANDS_COS}

        option :bucket,              description: 'Bucket name'
        option :endpoint,            description: 'Storage endpoint (URL)'
        option :apikey,              description: 'Storage API key'
        option :crn,                 description: 'Resource instance id (CRN)'
        option :service_credentials, description: 'IBM Cloud service credentials', allowed: [Hash, NilClass]
        option :region,              description: 'Storage region'
        option :identity,            description: "Authentication URL (#{Api::CosNode::IBM_CLOUD_TOKEN_URL})", default: Api::CosNode::IBM_CLOUD_TOKEN_URL

        use_options Node

        def initialize(**_)
          super
          options.parse_options!
        end

        # node - mount target: build the COS Node API and plugin from CLI options.
        # @return [Node] Node plugin instance on the COS bucket
        def cos_node_plugin(**)
          # get service credentials, Hash, e.g. @json:@file:...
          service_credentials = options.get_option(:service_credentials)
          cos_node_params = {
            auth_url: options.get_option(:identity, mandatory: true),
            bucket:   options.get_option(:bucket, mandatory: true),
            endpoint: options.get_option(:endpoint)
          }
          if service_credentials.nil?
            Aspera.assert(!cos_node_params[:endpoint].nil?, 'endpoint required when service credentials not provided', type: Cli::BadArgument)
            cos_node_params[:api_key] = options.get_option(:apikey, mandatory: true)
            cos_node_params[:instance_id] = options.get_option(:crn, mandatory: true)
          else
            Aspera.assert(cos_node_params[:endpoint].nil?, 'endpoint not allowed when service credentials provided', type: Cli::BadArgument)
            cos_node_params.merge!(Api::CosNode.parameters_from_svc_credentials(service_credentials, options.get_option(:region, mandatory: true)))
          end
          api_node = Api::CosNode.new(**cos_node_params)
          Node.new(context: context, api: api_node)
        end
      end
    end
  end
end
