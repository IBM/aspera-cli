# frozen_string_literal: true

require 'aspera/cli/plugins/base'
require 'aspera/cli/plugins/node'
require 'aspera/api/cos_node'
require 'aspera/assert'

module Aspera
  module Cli
    module Plugins
      class Cos < Base
        command :node, description: 'Execute COS node commands', setup: :setup_cos_node

        commands_under(:node) do
          Node::COMMANDS_COS.each do |cmd|
            command(cmd, description: "Node #{cmd} command")
          end
        end

        def initialize(**_)
          super
          options.declare(:bucket, 'Bucket name')
          options.declare(:endpoint, 'Storage endpoint (URL)')
          options.declare(:apikey, 'Storage API key')
          options.declare(:crn, 'Resource instance id (CRN)')
          options.declare(:service_credentials, 'IBM Cloud service credentials', allowed: [Hash, NilClass])
          options.declare(:region, 'Storage region')
          options.declare(:identity, "Authentication URL (#{Api::CosNode::IBM_CLOUD_TOKEN_URL})", default: Api::CosNode::IBM_CLOUD_TOKEN_URL)
          options.parse_options!
          Node.declare_options(options)
        end

        # Build the COS Node API and plugin from CLI options.
        # @return [Hash] context hash containing :node_plugin
        def setup_cos_node
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
          {node_plugin: Node.new(context: context, api: api_node)}
        end

        # One handler per COMMANDS_COS command — delegates to the Node plugin's dispatch_v3_command.
        Node::COMMANDS_COS.each do |cmd|
          define_method(:"handle_node_#{cmd}") do |node_plugin:|
            node_plugin.dispatch_v3_command(cmd)
          end
        end
      end
    end
  end
end
