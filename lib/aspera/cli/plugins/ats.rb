# frozen_string_literal: true

# cspell:ignore trustpolicy

require 'aspera/cli/plugins/base'
require 'aspera/cli/plugins/node'
require 'aspera/api/ats'
require 'aspera/api/aoc'
require 'aspera/api/alee'
require 'aspera/assert'

module Aspera
  module Cli
    module Plugins
      # Access Aspera Transfer Service
      # https://developer.ibm.com/aspera/docs/ats-api-reference/creating-ats-api-keys/
      class Ats < Base
        application_name 'Aspera Transfer Service'
        # columns for list of cloud providers
        CLOUD_TABLE = %w[id name].freeze
        private_constant :CLOUD_TABLE

        option :ibm_api_key, description: 'IBM API key, see https://cloud.ibm.com/iam/apikeys'
        option :instance,    description: 'ATS instance in ibm cloud'
        option :ats_key,     description: 'ATS key identifier (ats_xxx)'
        option :ats_secret,  description: 'ATS key secret'
        option :cloud,       description: 'Cloud provider'
        option :region,      description: 'Cloud region'

        def initialize(api: nil, **base_args)
          super(**base_args)
          @ats_api_open = Api::Ats.new
          @ats_api_auth = api
          options.parse_options!
          Node.declare_options(options)
        end

        # --- DSL ---

        command :cluster,    description: 'Display general ATS cluster information (public API, no auth)'
        command :access_key, description: 'Manage ATS access keys'
        command :api_key,    description: 'Manage credential to access ATS API', condition: :api_key_available?
        command :aws_trust_policy, description: 'Show AWS trust policy', handler: lambda{Result::SingleObject.new(ats_api.read('aws/trustpolicy', {region: options.get_option(:region, mandatory: true)}))}

        commands_under(:cluster) do
          command :clouds, description: 'List cloud providers', handler: lambda{Result::ObjectList.new(@ats_api_open.cloud_names.map{ |k, v| CLOUD_TABLE.zip([k, v]).to_h})}
          command :list,   description: 'List ATS servers',     handler: lambda{Result::ObjectList.new(@ats_api_open.all_servers, fields: %w[id cloud region])}
          command :show,   description: 'Show a specific server'
        end

        commands_under(:access_key) do
          command :create,      description: 'Create an access key'
          command(:list,        description: 'List access keys', handler: lambda do
            res = ats_api.read('access_keys', query_read_delete(default: {'offset' => 0, 'max_results' => 1000}))
            Result::ObjectList.new(res['data'], fields: ['name', 'id', 'created.at', 'modified.at'])
          end)
          command :show,        description: 'Show an access key',        instance_arg: :access_key_id,
            handler: ->(access_key_id:, **){Result::SingleObject.new(ats_api.read("access_keys/#{access_key_id}"))}
          command :modify,      description: 'Modify an access key',      instance_arg: :access_key_id
          command :delete,      description: 'Delete an access key',      instance_arg: :access_key_id
          command :node,        description: 'Execute node commands via ATS access key', instance_arg: :access_key_id, setup: :setup_ak_node
          command :cluster,     description: 'Show cluster info for an access key', instance_arg: :access_key_id
          command :entitlement, description: 'Show ATS entitlement for an access key', instance_arg: :access_key_id
        end

        commands_under(%i[access_key node]) do
          Node::COMMANDS_GEN4.each do |cmd|
            command(cmd, description: "Node Gen4 #{cmd} command")
          end
        end

        commands_under(:api_key) do
          command(:instances, description: 'List ATS instances in IBM Cloud', handler: lambda do
            instances = ats_api_v2_auth_ibm.read('instances')
            Log.log.warn{"more instances remaining: #{instances['remaining']}"} unless instances['remaining'].to_i.eql?(0)
            Result::ValueList.new(instances['data'], name: 'instance')
          end)
          command :create, description: 'Create an ATS API key', handler: lambda{Result::SingleObject.new(build_ats_ibm_api_with_instance.create('api_keys', value_create_modify(command: :create, default: {})))}
          command :list,   description: 'List ATS API keys',     handler: lambda{Result::ValueList.new(build_ats_ibm_api_with_instance.read('api_keys', {'offset' => 0, 'max_results' => 1000})['data'], name: 'ats_id')}
          command :show,   description: 'Show an ATS API key',   instance_arg: :api_key_id,
            handler: ->(api_key_id:, **){Result::SingleObject.new(build_ats_ibm_api_with_instance.read("api_keys/#{api_key_id}"))}
          command :delete, description: 'Delete an ATS API key', instance_arg: :api_key_id
        end

        # --- conditions ---

        # api_key sub-tree is only available when authenticated via ATS key (not injected API)
        def api_key_available?
          @ats_api_auth.nil?
        end

        # --- helpers ---

        def server_by_cloud_region
          # TODO: provide list ?
          cloud = options.get_option(:cloud, mandatory: true).upcase
          region = options.get_option(:region, mandatory: true)
          return @ats_api_open.read("servers/#{cloud}/#{region}")
        end

        # require api key only if needed
        def ats_api
          return @ats_api_auth unless @ats_api_auth.nil?
          @ats_api_auth = Rest.new(
            base_url: "#{Api::Ats::SERVICE_BASE_URL}/pub/v1",
            auth:     {
              type:     :basic,
              username: options.get_option(:ats_key, mandatory: true),
              password: options.get_option(:ats_secret, mandatory: true)
            }
          )
        end

        def ats_api_v2_auth_ibm(rest_add_headers = {})
          return Rest.new(
            base_url: "#{Api::Ats::SERVICE_BASE_URL}/v2",
            headers:  rest_add_headers,
            auth:     {
              type:          :oauth2,
              grant_method:  :generic,
              base_url:      'https://iam.bluemix.net/identity',
              # does not work:  base_url:    'https://iam.cloud.ibm.com/identity',
              grant_type:    'urn:ibm:params:oauth:grant-type:apikey',
              response_type: 'cloud_iam',
              params:        {
                apikey: options.get_option(:ibm_api_key, mandatory: true)
              }
            }
          )
        end

        def handle_cluster_show
          if options.get_option(:cloud) || options.get_option(:region)
            server_data = server_by_cloud_region
          else
            server_id = options.instance_identifier
            server_data = @ats_api_open.all_servers.find{ |i| i['id'].eql?(server_id)}
            raise BadIdentifier.new('server', server_id) if server_data.nil?
          end
          Result::SingleObject.new(server_data)
        end

        def handle_access_key_create
          params = value_create_modify(command: :create, default: {})
          server_data = nil
          # if transfer_server_id not provided, get it from command line options
          if !params.key?('transfer_server_id')
            server_data = server_by_cloud_region
            params['transfer_server_id'] = server_data['id']
          end
          Log.log.debug{"using params: #{params}".bg_red.gray}
          if params.key?('storage')
            case params['storage']['type']
            # here we need somehow to map storage type to field to get for auth end point
            when 'ibm-s3'
              server_data2 = nil
              if server_data.nil?
                server_data2 = @ats_api_open.all_servers.find{ |s| s['id'].eql?(params['transfer_server_id'])}
                raise "no such transfer server id: #{params['transfer_server_id']}" if server_data2.nil?
              else
                server_data2 = @ats_api_open.all_servers.find do |s|
                  s['cloud'].eql?(server_data['cloud']) &&
                    s['region'].eql?(server_data['region']) &&
                    s.key?('s3_authentication_endpoint')
                end
                raise "no such transfer server id: #{params['transfer_server_id']}" if server_data2.nil?
                # specific one do not have s3 end point in id
                params['transfer_server_id'] = server_data2['id']
              end
              params['storage']['endpoint'] = server_data2['s3_authentication_endpoint'] if !params['storage'].key?('authentication_endpoint')
            end
          end
          res = ats_api.create('access_keys', params)
          return Result::SingleObject.new(res)
          # TODO : action : modify, with "PUT"
        end

        def handle_access_key_modify(access_key_id:, **)
          params = value_create_modify(command: :modify)
          params['id'] = access_key_id
          ats_api.update("access_keys/#{access_key_id}", params)
          return Result::Status.new('modified')
        end

        def handle_access_key_delete(access_key_id:, **)
          ats_api.delete("access_keys/#{access_key_id}")
          Result::Status.new("deleted #{access_key_id}")
        end

        def handle_access_key_entitlement(access_key_id:, **)
          ak = ats_api.read("access_keys/#{access_key_id}")
          api_bss = Api::Alee.new(ak['license']['entitlement_id'], ak['license']['customer_id'])
          return Result::SingleObject.new(api_bss.read('entitlement'))
        end

        # Build the Node plugin for an ATS access key.
        # access_key_id: is already in ctx via instance_arg: on the :node command.
        # @return [Hash] context hash containing :ak_node_plugin and :ak_root_file_id
        def setup_ak_node(access_key_id:, **)
          ak_data = ats_api.read("access_keys/#{access_key_id}")
          server_data = @ats_api_open.all_servers.find{ |i| i['id'].start_with?(ak_data['transfer_server_id'])}
          raise Cli::Error, 'no such server found' if server_data.nil?
          node_url = server_data['transfer_setup_url']
          api_node = Api::Node.new(
            base_url: node_url,
            auth:     {
              type:     :basic,
              username: access_key_id,
              password: context.secret_finder.lookup(url: node_url, username: access_key_id)
            }
          )
          {
            ak_node_plugin:  Node.new(context: context, api: api_node),
            ak_root_file_id: ak_data['root_file_id']
          }
        end

        # One handler per COMMANDS_GEN4 - delegates to the Node plugin's DSL registry.
        Node::COMMANDS_GEN4.each do |cmd|
          define_method(:"handle_access_key_node_#{cmd}") do |ak_node_plugin:, ak_root_file_id:|
            # For permission: the handler consumes the path first then re-dispatches to sub-commands.
            # Calling dispatch_from_registry with skip_setup would bypass path consumption and fail.
            next ak_node_plugin.send(:"handle_access_keys_do_#{cmd}", do_root_file_id: ak_root_file_id) if cmd.eql?(:permission)
            ak_node_plugin.dispatch_from_registry([:access_keys, :do, cmd], {do_root_file_id: ak_root_file_id}, skip_setup: true)
          end
        end

        def handle_access_key_cluster(access_key_id:, **)
          ats_url = ats_api.base_url
          api_ak_auth = Rest.new(
            base_url: ats_url,
            auth:     {
              type:     :basic,
              username: access_key_id,
              password: context.secret_finder.lookup(url: ats_url, username: access_key_id)
            }
          )
          return Result::SingleObject.new(api_ak_auth.read('servers'))
        end

        private

        # Build the IBM Cloud ATS v2 API with an instance header.
        # Reads instance from options; falls back to first available instance.
        def build_ats_ibm_api_with_instance
          instance = options.get_option(:instance)
          if instance.nil?
            instance = ats_api_v2_auth_ibm.read('instances')['data'].first
            formatter.display_status("using first instance: #{instance}")
          end
          ats_api_v2_auth_ibm({'X-ATS-Service-Instance-Id' => instance})
        end
      end
    end
  end
end
