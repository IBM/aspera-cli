require 'asperalm/cli/plugins/node'
require 'asperalm/ats_api'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions
      # https://52.44.83.163/docs/pub/
      class Ats < Plugin
        def declare_options(skip_common=false)
          unless skip_common
            self.options.add_opt_simple(:secret,"Access key secret")
          end
          self.options.add_opt_simple(:ibm_api_key,"IBM API key, see https://console.bluemix.net/iam/#/apikeys")
          self.options.add_opt_simple(:instance,"ATS instance in bluemix")
          self.options.add_opt_simple(:ats_key,"ATS key identifier (ats_xxx)")
          self.options.add_opt_simple(:ats_secret,"ATS key secret")
          self.options.add_opt_simple(:params,"Parameters access key creation (@json:)")
          self.options.add_opt_simple(:cloud,"Cloud provider")
          self.options.add_opt_simple(:region,"Cloud region")
        end

        #
        def server_by_cloud_region
          # todo: provide list ?
          cloud=self.options.get_option(:cloud,:mandatory).upcase
          region=self.options.get_option(:region,:mandatory)
          return @ats_api_pub.read("servers/#{cloud}/#{region}")[:data]
        end

        # require api key only if needed
        def ats_api_auth
          return @ats_api_auth_cache unless @ats_api_auth_cache.nil?
          @ats_api_auth_cache=Rest.new({
            :base_url       => AtsApi.base_url+'/pub/v1',
            :auth_type      => :basic,
            :basic_username => self.options.get_option(:ats_key,:mandatory),
            :basic_password => self.options.get_option(:ats_secret,:mandatory)
          })
        end

        def execute_action_access_key
          commands=[:create,:list,:show,:delete,:node,:cluster]
          command=self.options.get_next_command(commands)
          # those dont require access key id
          unless [:create,:list].include?(command)
            access_key_id=self.options.get_option(:id,:mandatory)
          end
          case command
          when :create
            params=self.options.get_option(:params,:optional) || {}
            server_data=nil
            # if transfer_server_id not provided, get it from command line options
            if !params.has_key?('transfer_server_id')
              server_data=server_by_cloud_region
              params['transfer_server_id']=server_data['id']
            end
            Log.log.debug("using params: #{params}".bg_red.gray)
            if params.has_key?('storage')
              case params['storage']['type']
              # here we need somehow to map storage type to field to get for auth end point
              when 'softlayer_swift'
                if !params['storage'].has_key?('authentication_endpoint')
                  server_data||=@ats_api_pub.all_servers.select{|i|i['id'].eql?(params['transfer_server_id'])}.first
                  params['storage']['credentials']['authentication_endpoint'] = server_data['swift_authentication_endpoint']
                end
              end
            end
            res=ats_api_auth.create("access_keys",params)
            return {:type=>:single_object, :data=>res[:data]}
            # TODO : action : modify, with "PUT"
          when :list
            params=self.options.get_option(:params,:optional) || {'offset'=>0,'max_results'=>1000}
            res=ats_api_auth.read("access_keys",params)
            return {:type=>:object_list, :data=>res[:data]['data'], :fields => ['name','id','secret','created','modified']}
          when :show
            res=ats_api_auth.read("access_keys/#{access_key_id}")
            return {:type=>:single_object, :data=>res[:data]}
          when :delete
            res=ats_api_auth.delete("access_keys/#{access_key_id}")
            return Main.result_status("deleted #{access_key_id}")
          when :node
            ak_data=ats_api_auth.read("access_keys/#{access_key_id}")[:data]
            server_data=@ats_api_pub.all_servers.select {|i| i['id'].start_with?(ak_data['transfer_server_id'])}.first
            raise CliError,"no such server found" if server_data.nil?
            api_node=Rest.new({:base_url=>server_data['transfer_setup_url'],:auth_type=>:basic,:basic_username=>ak_data['id'], :basic_password=>ak_data['secret']})
            command=self.options.get_next_command(Node.common_actions)
            return Node.new(@agents).set_api(api_node).execute_action(command)
          when :cluster
            rest_params={
              :base_url       => ats_api_auth.params[:base_url],
              :auth_type      => :basic,
              :basic_username => access_key_id,
              :basic_password => self.options.get_option(:secret,:optional)
            }
            # if no access key id provided, then we get from ATS API
            if rest_params[:basic_password].nil?
              ak_data=ats_api_auth.read("access_keys/#{access_key_id}")[:data]
              #rest_params[:username]=ak_data['id']
              rest_params[:basic_password]=ak_data['secret']
            end
            api_ak_auth=Rest.new(rest_params)
            return {:type=>:single_object, :data=>api_ak_auth.read("servers")[:data]}
          else raise "INTERNAL ERROR"
          end
        end

        def execute_action_cluster_pub
          command=self.options.get_next_command([ :clouds, :list, :show])
          case command
          when :clouds
            return {:type=>:single_object, :data=>@ats_api_pub.cloud_names, :columns=>['id','name']}
          when :list
            return {:type=>:object_list, :data=>@ats_api_pub.all_servers, :fields=>['id','cloud','region']}
          when :show
            server_id=self.options.get_option(:id,:optional)
            if server_id.nil?
              server_data=server_by_cloud_region
            else
              server_data=@ats_api_pub.all_servers.select {|i| i['id'].eql?(server_id)}.first
              raise "no such server id" if server_data.nil?
            end
            return {:type=>:single_object, :data=>server_data}
          end
        end

        def ats_api_auth_ibm(add_headers={})
          bluemix=Rest.new({:base_url=>'https://iam.bluemix.net'})
          data={
            'grant_type'    => 'urn:ibm:params:oauth:grant-type:apikey',
            'response_type' => 'cloud_iam',
            'apikey'        => self.options.get_option(:ibm_api_key,:mandatory)}
          xx=bluemix.create('identity/token',data,:www_body_params)[:data]
          return Rest.new({
            :base_url => AtsApi.base_url+'/v2',
            :headers  => {'Authorization'=>"#{xx['token_type']} #{xx['access_token']}"}.merge(add_headers)
          })
        end

        def execute_action_api_key
          command=self.options.get_next_command([:instances, :create, :list, :show, :delete])
          if [:show,:delete].include?(command)
            modified_ats_id=self.options.get_option(:id,:mandatory)
          end
          add_header={}
          add_header={'X-ATS-Service-Instance-Id'=>self.options.get_option(:instance,:mandatory)} unless command.eql?(:instances)
          ats_ibm_api=ats_api_auth_ibm(add_header)
          case command
          when :instances
            instances=ats_ibm_api.read('instances')[:data]
            Log.log.warn("more instances remaining: #{instances['remaining']}") unless instances['remaining'].to_i.eql?(0)
            return {:type=>:value_list, :data=>instances['data'], :name=>'instance'}
          when :create
            create_value=self.options.get_option(:value,:optional)||{}
            created_key=ats_ibm_api.create('api_keys',create_value)[:data]
            return {:type=>:single_object, :data=>created_key}
          when :list # list known api keys in ATS (this require an api_key ...)
            res=ats_ibm_api.read('api_keys',{'offset'=>0,'max_results'=>1000})
            return {:type=>:value_list, :data=>res[:data]['data'], :name => 'ats_id'}
          when :show # show one of api_key in ATS
            res=ats_ibm_api.read("api_keys/#{modified_ats_id}")
            return {:type=>:single_object, :data=>res[:data]}
          when :delete #
            res=ats_ibm_api.delete("api_keys/#{modified_ats_id}")
            return Main.result_status("deleted #{modified_ats_id}")
          else raise "INTERNAL ERROR"
          end
        end

        def action_list; [ :cluster, :access_key ,:api_key];end

        # called for legacy and AoC
        def execute_action_gen(ats_api_auth_arg)
          actions=action_list
          actions.delete(:api_key) unless ats_api_auth_arg.nil?
          command=self.options.get_next_command(actions)
          @ats_api_auth_cache=ats_api_auth_arg
          # keep as member variable as we may want to use the api in AoC name space
          @ats_api_pub = AtsApi.new
          case command
          when :cluster # display general ATS cluster information, this uses public API, no auth
            return execute_action_cluster_pub
          when :access_key
            return execute_action_access_key
          when :api_key # manage credential to access ATS API
            return execute_action_api_key
          else raise "ERROR"
          end
        end

        # called for legacy ATS only
        def execute_action
          execute_action_gen(nil)
        end
      end
    end
  end # Cli
end # Asperalm
