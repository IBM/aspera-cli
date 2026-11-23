# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../cli/plugins/base'
require_relative '../../cli/error'
require_relative '../node/commands'
require_relative 'api'
require_relative '../../assert'

module Aspera
  module Plugins
    module Cos
      class Commands < Cli::Plugins::Base
        application_name 'IBM Cloud Object Storage'

        command :node, description: 'Execute COS node commands',
          mount: {plugin: Node::Commands, instance: :cos_node_plugin, only: Node::Commands::COMMANDS_COS}

        option :bucket,              description: 'Bucket name'
        option :endpoint,            description: 'Storage endpoint (URL)'
        option :apikey,              description: 'Storage API key'
        option :crn,                 description: 'Resource instance id (CRN)'
        option :service_credentials, description: 'IBM Cloud service credentials', allowed: [Hash, NilClass]
        option :region,              description: 'Storage region'
        option :identity,            description: "Authentication URL (#{Api::IBM_CLOUD_TOKEN_URL})", default: Api::IBM_CLOUD_TOKEN_URL

        use_options Node::Commands

        # node - mount target: build the COS Node API and plugin from CLI options.
        # @return [Node::Commands] Node plugin instance on the COS bucket
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
            cos_node_params.merge!(Api.parameters_from_svc_credentials(service_credentials, options.get_option(:region, mandatory: true)))
          end
          api_node = Api.new(**cos_node_params)
          Node::Commands.new(context: context, api: api_node)
        end
      end
    end
  end
end
