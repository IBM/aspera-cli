# frozen_string_literal: true

# cspell:ignore trustpolicy

require 'aspera/cli/plugins/base'
require 'aspera/cli/plugins/node'
require 'aspera/api/ats'
require 'aspera/api/aoc'
require 'aspera/api/alee'
require 'aspera/assert'
require 'aspera/rainbow'
using Rainbow

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

        use_options Node

        def initialize(api: nil, **base_args)
          super(**base_args)
          @ats_api_open = Api::Ats.new
          @ats_api_auth = api
          options.parse_options!
        end

        # --- DSL ---

        command :cluster,    description: 'Show general ATS cluster information (public API, no auth)'
        command :access_key, description: 'Manage ATS access keys'
        command :api_key,    description: 'Manage credential to access ATS API', condition: :api_key_available?
        command :aws_trust_policy, description: 'Show AWS trust policy', action: ->(**) { Result::SingleObject.new(ats_api.read('aws/trustpolicy', {region: options.get_option(:region, mandatory: true)})) }

        commands_under :cluster do
          command :clouds, description: 'List cloud providers', action: ->(**) { Result::ObjectList.new(@ats_api_open.cloud_names.map { |k, v| CLOUD_TABLE.zip([k, v]).to_h }) }
          command :list,   description: 'List ATS servers',     action: ->(**) { Result::ObjectList.new(@ats_api_open.all_servers, fields: %w[id cloud region]) }
          command :show,   description: 'Show a specific server (or use options cloud and region)',
            arguments: [{name: :server_id, type: String, mandatory: false, default: nil}]
        end

        commands_under :access_key do
          command :create,      description: 'Create an access key',
            arguments: [{name: :access_key, type: Hash, mandatory: false, default: {}}]
          command(:list,        description: 'List access keys', action: lambda do |**|
            res = ats_api.read('access_keys', query_read_delete(default: {'offset' => 0, 'max_results' => 1000}))
            Result::ObjectList.new(res['data'], fields: ['name', 'id', 'created.at', 'modified.at'])
          end)
          command :show,        description: 'Show an access key',
            arguments: [{name: :access_key_id, type: :identifier}],
            action: ->(access_key_id:, **) { Result::SingleObject.new(ats_api.read("access_keys/#{access_key_id}")) }
          command :modify,      description: 'Modify an access key',
            arguments: [{name: :access_key_id, type: :identifier}, {name: :access_key, type: Hash}]
          command(
            :delete, description: 'Delete an access key',
            arguments: [{name: :access_key_id, type: :identifier}],
            action: lambda do |access_key_id:, **|
              ats_api.delete("access_keys/#{access_key_id}")
              Result::Status.new("deleted #{access_key_id}")
            end
          )
          command :node,        description: 'Execute node commands via ATS access key',
            arguments: [{name: :access_key_id, type: :identifier}],
            mount: {plugin: Node, at: %i[access_keys do], instance: :ak_node_plugin}
          command :cluster,     description: 'Show cluster info for an access key',
            arguments: [{name: :access_key_id, type: :identifier}]
          command(
            :entitlement, description: 'Show ATS entitlement for an access key',
            arguments: [{name: :access_key_id, type: :identifier}],
            action: lambda do |access_key_id:, **|
              ak = ats_api.read("access_keys/#{access_key_id}")
              api_bss = Api::Alee.new(ak['license']['entitlement_id'], ak['license']['customer_id'])
              return Result::SingleObject.new(api_bss.read('entitlement'))
            end
          )
        end

        commands_under :api_key do
          command(:instances, description: 'List ATS instances in IBM Cloud', action: lambda do |**|
            instances = ats_api_v2_auth_ibm.read('instances')
            Log.log.warn { "more instances remaining: #{instances['remaining']}" } unless instances['remaining'].to_i.eql?(0)
            Result::ValueList.new(instances['data'], name: 'instance')
          end)
          command :create, description: 'Create an ATS API key',
            arguments: [{name: :api_key, type: Hash, mandatory: false, default: {}}],
            action: ->(api_key:, **) { Result::SingleObject.new(build_ats_ibm_api_with_instance.create('api_keys', api_key)) }
          command :list,   description: 'List ATS API keys', action: ->(**) { Result::ValueList.new(build_ats_ibm_api_with_instance.read('api_keys', {'offset' => 0, 'max_results' => 1000})['data'], name: 'ats_id') }
          command :show,   description: 'Show an ATS API key',
            arguments: [{name: :api_key_id, type: :identifier}],
            action: ->(api_key_id:, **) { Result::SingleObject.new(build_ats_ibm_api_with_instance.read("api_keys/#{api_key_id}")) }
          command(
            :delete, description: 'Delete an ATS API key',
            arguments: [{name: :api_key_id, type: :identifier}],
            action: lambda do |api_key_id:, **|
              build_ats_ibm_api_with_instance.delete("api_keys/#{api_key_id}")
              Result::Status.new("deleted #{api_key_id}")
            end
          )
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

        def action_cluster_show(server_id: nil, **)
          if options.get_option(:cloud) || options.get_option(:region)
            server_data = server_by_cloud_region
          else
            Aspera.assert(server_id, type: Cli::MissingArgument) { 'server_id (or options cloud and region)' }
            server_data = @ats_api_open.all_servers.find { |i| i['id'].eql?(server_id) }
            raise BadIdentifier.new('server', server_id) if server_data.nil?
          end
          Result::SingleObject.new(server_data)
        end

        def action_access_key_create(access_key: {}, **)
          params = access_key
          server_data = nil
          # if transfer_server_id not provided, get it from command line options
          if !params.key?('transfer_server_id')
            server_data = server_by_cloud_region
            params['transfer_server_id'] = server_data['id']
          end
          Log.log.debug { "using params: #{params}".bg(:red).white }
          if params.key?('storage')
            case params['storage']['type']
            # here we need somehow to map storage type to field to get for auth end point
            when 'ibm-s3'
              server_data2 = nil
              if server_data.nil?
                server_data2 = @ats_api_open.all_servers.find { |s| s['id'].eql?(params['transfer_server_id']) }
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

        def action_access_key_modify(access_key:, access_key_id:, **)
          params = access_key
          params['id'] = access_key_id
          ats_api.update("access_keys/#{access_key_id}", params)
          return Result::Status.new('modified')
        end

        # access_key > node - mount target: Node plugin for an ATS access key.
        # access_key_id: is already in ctx via arguments: on the :node command.
        # @return [Array(Node, Hash)] Node plugin and seed ctx for `access_keys do`
        def ak_node_plugin(access_key_id:, **)
          ak_data = ats_api.read("access_keys/#{access_key_id}")
          server_data = @ats_api_open.all_servers.find { |i| i['id'].start_with?(ak_data['transfer_server_id']) }
          Aspera.assert(!server_data.nil?, type: Cli::Error) { 'no such server found' }
          node_url = server_data['transfer_setup_url']
          api_node = Api::Node.new(
            base_url: node_url,
            auth:     {
              type:     :basic,
              username: access_key_id,
              password: context.secret_finder.lookup(url: node_url, username: access_key_id)
            }
          )
          [Node.new(context: context, api: api_node), {do_root_file_id: ak_data['root_file_id']}]
        end

        def action_api_key_instances
          instances = ats_api_v2_auth_ibm.read('instances')
          Log.log.warn { "more instances remaining: #{instances['remaining']}" } unless instances['remaining'].to_i.eql?(0)
          Result::ValueList.new(instances['data'], name: 'instance')
        end

        def action_access_key_cluster(access_key_id:, **)
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
