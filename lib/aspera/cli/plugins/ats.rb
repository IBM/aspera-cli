# frozen_string_literal: true

require 'aspera/cli/plugins/node'
require 'aspera/ats_api'

module Aspera
  module Cli
    module Plugins
      # Access Aspera Transfer Service
      # https://developer.ibm.com/aspera/docs/ats-api-reference/creating-ats-api-keys/
      class Ats < Aspera::Cli::Plugin
        CLOUD_TABLE = %w[id name].freeze
        def initialize(env)
          super(env)
          options.declare(:ibm_api_key, 'IBM API key, see https://cloud.ibm.com/iam/apikeys')
          options.declare(:instance, 'ATS instance in ibm cloud')
          options.declare(:ats_key, 'ATS key identifier (ats_xxx)')
          options.declare(:ats_secret, 'ATS key secret')
          options.declare(:params, 'Parameters access key creation (@json:)')
          options.declare(:cloud, 'Cloud provider')
          options.declare(:region, 'Cloud region')
          options.parse_options!
        end

        def server_by_cloud_region
          # TODO: provide list ?
          cloud = options.get_option(:cloud, mandatory: true).upcase
          region = options.get_option(:region, mandatory: true)
          return @ats_api_pub.read("servers/#{cloud}/#{region}")[:data]
        end

        # require api key only if needed
        def ats_api_pub_v1
          return @ats_api_pub_v1_cache unless @ats_api_pub_v1_cache.nil?
          @ats_api_pub_v1_cache = Rest.new({
            base_url: AtsApi.base_url + '/pub/v1',
            auth:     {
              type:     :basic,
              username: options.get_option(:ats_key, mandatory: true),
              password: options.get_option(:ats_secret, mandatory: true)}
          })
        end

        def execute_action_access_key
          commands = %i[create list show modify delete node cluster entitlement]
          command = options.get_next_command(commands)
          # those do not require access key id
          access_key_id = instance_identifier unless %i[create list].include?(command)
          case command
          when :create
            params = options.get_option(:params) || {}
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
                  server_data2 = @ats_api_pub.all_servers.find{|s|s['id'].eql?(params['transfer_server_id'])}
                  raise "no such transfer server id: #{params['transfer_server_id']}" if server_data2.nil?
                else
                  server_data2 = @ats_api_pub.all_servers.find do |s|
                    s['cloud'].eql?(server_data['cloud']) &&
                      s['region'].eql?(server_data['region']) &&
                      s.key?('s3_authentication_endpoint')
                  end
                  raise "no such transfer server id: #{params['transfer_server_id']}" if server_data2.nil?
                  # specific one do not have s3 end point in id
                  params['transfer_server_id'] = server_data2['id']
                end
                if !params['storage'].key?('authentication_endpoint')
                  params['storage']['endpoint'] = server_data2['s3_authentication_endpoint']
                end
              end
            end
            res = ats_api_pub_v1.create('access_keys', params)
            return {type: :single_object, data: res[:data]}
            # TODO : action : modify, with "PUT"
          when :list
            params = options.get_option(:params) || {'offset' => 0, 'max_results' => 1000}
            res = ats_api_pub_v1.read('access_keys', params)
            return {type: :object_list, data: res[:data]['data'], fields: ['name', 'id', 'created.at', 'modified.at']}
          when :show
            res = ats_api_pub_v1.read("access_keys/#{access_key_id}")
            return {type: :single_object, data: res[:data]}
          when :modify
            params = value_create_modify(command: command)
            params['id'] = access_key_id
            ats_api_pub_v1.update("access_keys/#{access_key_id}", params)
            return Main.result_status('modified')
          when :entitlement
            ak = ats_api_pub_v1.read("access_keys/#{access_key_id}")[:data]
            api_bss = AoC.metering_api(ak['license']['entitlement_id'], ak['license']['customer_id'])
            return {type: :single_object, data: api_bss.read('entitlement')[:data]}
          when :delete
            ats_api_pub_v1.delete("access_keys/#{access_key_id}")
            return Main.result_status("deleted #{access_key_id}")
          when :node
            ak_data = ats_api_pub_v1.read("access_keys/#{access_key_id}")[:data]
            server_data = @ats_api_pub.all_servers.find {|i| i['id'].start_with?(ak_data['transfer_server_id'])}
            raise Cli::Error, 'no such server found' if server_data.nil?
            node_url = server_data['transfer_setup_url']
            api_node = Aspera::Node.new(params: {
              base_url: node_url,
              auth:     {
                type:     :basic,
                username: access_key_id,
                password: @agents[:config].lookup_secret(url: node_url, username: access_key_id)
              }})
            command = options.get_next_command(Node::COMMANDS_GEN4)
            return Node.new(@agents, api: api_node).execute_command_gen4(command, ak_data['root_file_id'])
          when :cluster
            ats_url = ats_api_pub_v1.params[:base_url]
            rest_params = {
              base_url: ats_url,
              auth:     {
                type:     :basic,
                username: access_key_id,
                password: @agents[:config].lookup_secret(url: ats_url, username: access_key_id)
              }}
            api_ak_auth = Rest.new(rest_params)
            return {type: :single_object, data: api_ak_auth.read('servers')[:data]}
          else raise 'INTERNAL ERROR'
          end
        end

        def execute_action_cluster_pub
          command = options.get_next_command(%i[clouds list show])
          case command
          when :clouds
            return {type: :object_list, data: @ats_api_pub.cloud_names.map { |k, v| CLOUD_TABLE.zip([k, v]).to_h }}
          when :list
            return {type: :object_list, data: @ats_api_pub.all_servers, fields: %w[id cloud region]}
          when :show
            if options.get_option(:cloud) || options.get_option(:region)
              server_data = server_by_cloud_region
            else
              server_id = instance_identifier
              server_data = @ats_api_pub.all_servers.find {|i| i['id'].eql?(server_id)}
              raise 'no such server id' if server_data.nil?
            end
            return {type: :single_object, data: server_data}
          end
        end

        def ats_api_v2_auth_ibm(rest_add_headers={})
          return Rest.new({
            base_url: AtsApi.base_url + '/v2',
            headers:  rest_add_headers,
            auth:     {
              type:         :oauth2,
              base_url:     'https://iam.bluemix.net/identity',
              # does not work:  base_url:    'https://iam.cloud.ibm.com/identity',
              grant_method: :generic,
              generic:      {
                grant_type:    'urn:ibm:params:oauth:grant-type:apikey',
                response_type: 'cloud_iam',
                apikey:        options.get_option(:ibm_api_key, mandatory: true)
              }}})
        end

        def execute_action_api_key
          command = options.get_next_command(%i[instances create list show delete])
          if %i[show delete].include?(command)
            concerned_id = instance_identifier
          end
          rest_add_header = {}
          if !command.eql?(:instances)
            instance = options.get_option(:instance)
            if instance.nil?
              # Take the first Aspera on Cloud transfer service instance ID if not provided by user
              instance = ats_api_v2_auth_ibm.read('instances')[:data]['data'].first
              formatter.display_status("using first instance: #{instance}")
            end
            rest_add_header = {'X-ATS-Service-Instance-Id' => instance}
          end
          ats_ibm_api = ats_api_v2_auth_ibm(rest_add_header)
          case command
          when :instances
            instances = ats_ibm_api.read('instances')[:data]
            Log.log.warn{"more instances remaining: #{instances['remaining']}"} unless instances['remaining'].to_i.eql?(0)
            return {type: :value_list, data: instances['data'], name: 'instance'}
          when :create
            created_key = ats_ibm_api.create('api_keys', value_create_modify(command: command, default: {}))[:data]
            return {type: :single_object, data: created_key}
          when :list # list known api keys in ATS (this require an api_key ...)
            res = ats_ibm_api.read('api_keys', {'offset' => 0, 'max_results' => 1000})
            return {type: :value_list, data: res[:data]['data'], name: 'ats_id'}
          when :show # show one of api_key in ATS
            res = ats_ibm_api.read("api_keys/#{concerned_id}")
            return {type: :single_object, data: res[:data]}
          when :delete
            ats_ibm_api.delete("api_keys/#{concerned_id}")
            return Main.result_status("deleted #{concerned_id}")
          else raise 'INTERNAL ERROR'
          end
        end

        ACTIONS = %i[cluster access_key api_key aws_trust_policy].freeze

        # called for legacy and AoC
        def execute_action_gen(ats_api_arg)
          actions = ACTIONS.dup
          actions.delete(:api_key) unless ats_api_arg.nil?
          command = options.get_next_command(actions)
          @ats_api_pub_v1_cache = ats_api_arg
          # keep as member variable as we may want to use the api in AoC name space
          @ats_api_pub = AtsApi.new
          case command
          when :cluster # display general ATS cluster information, this uses public API, no auth
            return execute_action_cluster_pub
          when :access_key
            return execute_action_access_key
          when :api_key # manage credential to access ATS API
            return execute_action_api_key
          when :aws_trust_policy
            res = ats_api_pub_v1.read('aws/trustpolicy', {region: options.get_option(:region, mandatory: true)})[:data]
            return {type: :single_object, data: res}
          else raise 'ERROR'
          end
        end

        # called for legacy ATS only
        def execute_action
          execute_action_gen(nil)
        end
      end
    end
  end # Cli
end # Aspera
