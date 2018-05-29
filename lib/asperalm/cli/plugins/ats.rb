require 'asperalm/cli/plugins/node'
require 'asperalm/oauth'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions
      # https://52.44.83.163/docs/pub/
      class Ats < Plugin
        # manage access to legacy ATS
        class LegacyAts < Plugin
          # local address to receive code on authentication
          LOCAL_REDIRECT_URI="http://localhost:12345"
          # cache located in aslmcli config folder
          ATS_KEYS_FILENAME="ats_api_keys.json"
          attr_reader :ats_api_public
          def initialize
            # special
            @current_api_key_info=nil
            @repo_api_keys=nil
            @ats_api_public = Rest.new(ats_api_base_url)
            @ats_api_secure = nil
          end

          # main url for ATS API
          def ats_api_base_url
            return 'https://ats.aspera.io/pub/v1'
          end

          # authenticated API
          def ats_api_secure
            if @ats_api_secure.nil?
              @ats_api_secure=Rest.new(ats_api_base_url,{:auth => {
                :type=>:basic,
                :username=>current_api_key['ats_id'],
                :password=>current_api_key['ats_secret']
                }})
            end
            return @ats_api_secure
          end

          # all ATS API keys stored in cache file
          def repo_api_keys
            if @repo_api_keys.nil?
              @repo_api_keys=[]
              # cache file for CLI for API keys
              @api_key_repository_file=File.join(@main.config_folder,ATS_KEYS_FILENAME)
              if File.exist?(@api_key_repository_file)
                @repo_api_keys=JSON.parse(File.read(@api_key_repository_file))
              end
            end
            @repo_api_keys
          end

          # write ATS API keys cache file after modification
          def save_key_repo
            File.write(@api_key_repository_file,JSON.generate(repo_api_keys))
          end

          # get an api key
          # either first one stored in repository
          # or the one specified on command line
          # or creates a new one
          def current_api_key
            if @current_api_key_info.nil?
              requested_id=@optmgr.get_option(:ats_id,:optional)
              if requested_id.nil?
                # if no api key requested and no repo, create one
                create_new_api_key if repo_api_keys.empty?
                # else there must be only one
                raise "please select one api key with --ats-id, list with: aslmcli ats api repo list" if repo_api_keys.length != 1
                @current_api_key_info=repo_api_keys.first
              else
                selected=repo_api_keys.select{|i| i['ats_id'].eql?(requested_id)}
                raise CliBadArgument,"no such id in repository: #{requested_id}" if selected.empty?
                @current_api_key_info=selected.first
              end
            end
            return @current_api_key_info
          end

          # create a new API key , requires aspera id authentication
          def create_new_api_key
            # TODO: provide param username and password to avoid web auth
            # get login page url in exception code 3xx
            res=ats_api_public.call({:operation=>'POST',:subpath=>"api_keys",:return_error=>true,:headers=>{'Accept'=>'application/json'},:url_params=>{:description => "created by aslmcli",:redirect_uri=>LOCAL_REDIRECT_URI}})
            # TODO: check code is 3xx ?
            login_page_url=res[:http]['Location']
            new_api_key_info=Oauth.goto_page_and_get_request(LOCAL_REDIRECT_URI,login_page_url)
            @current_api_key_info=new_api_key_info
            # add extra information on api key to identify different subscriptions
            subscription=ats_api_secure.read("subscriptions")[:data]
            new_api_key_info['subscription_name']=subscription['name']
            new_api_key_info['organization_name']=subscription['aspera_id_user']['organization']['name']
            repo_api_keys.push(new_api_key_info)
            save_key_repo
            return new_api_key_info
          end

          def execute_action_api_key
            command=@optmgr.get_next_argument('command',[:create, :list, :show, :delete, :info, :subscriptions, :cache])
            if [:show,:delete].include?(command)
              modified_ats_id=@optmgr.get_option(:id,:mandatory)
            end
            case command
            when :create
              return {:type=>:key_val_list, :data=>create_new_api_key}
            when :list # list known api keys in ATS (this require an api_key ...)
              res=ats_api_secure.read("api_keys",{'offset'=>0,'max_results'=>1000})
              return {:type=>:value_list, :data=>res[:data]['data'], :name => 'ats_id'}
            when :show # show one of api_key in ATS
              res=ats_api_secure.read("api_keys/#{modified_ats_id}")
              return {:type=>:key_val_list, :data=>res[:data]}
            when :delete #
              res=ats_api_secure.delete("api_keys/#{modified_ats_id}")
              return Plugin.result_status("deleted #{modified_ats_id}")
            when :info # display current ATS credential information
              return {:type=>:key_val_list, :data=>current_api_key}
            when :subscriptions
              return {:type=>:key_val_list, :data=>ats_api_secure.read("subscriptions")[:data]}
            when :cache # list of delete entries in api_key cache
              command=@optmgr.get_next_argument('command',[:list, :delete])
              case command
              when :list
                return {:type=>:hash_array, :data=>repo_api_keys, :fields =>['ats_id','ats_secret','ats_description','subscription_name','organization_name']}
              when :delete
                deleted_ats_id=@optmgr.get_next_argument('ats_id',repo_api_keys.map{|i| i['ats_id']})
                #raise CliBadArgument,"no such id" if repo_api_keys.select{|i| i['ats_id'].eql?(ats_id)}.empty?
                repo_api_keys.select!{|i| !i['ats_id'].eql?(deleted_ats_id)}
                save_key_repo
                return {:type=>:hash_array, :data=>[{'ats_id'=>deleted_ats_id,'status'=>'deleted'}]}
              end
            else raise "INTERNAL ERROR"
            end
          end
        end # LegacyAts

        attr_accessor :ats_api_provider
        attr_writer :ats_api_secure

        def initialize
          # REST end points
          # cache of server data
          @all_servers_cache=nil
          #
          @ats_api_provider=nil
        end

        def api_public
          return ats_api_provider.ats_api_public
        end

        def api_secure
          return ats_api_provider.ats_api_secure
        end

        def declare_options(skip_common=false)
          unless skip_common
            @optmgr.add_opt_simple(:id,"Access key identifier, or server id, or api key id")
            @optmgr.add_opt_simple(:secret,"Access key secret")
          end
          @optmgr.add_opt_simple(:ats_id,"ATS key identifier (ats_xxx)")
          @optmgr.add_opt_simple(:params,"Parameters access key creation (@json:)")
          @optmgr.add_opt_simple(:cloud,"Cloud provider")
          @optmgr.add_opt_simple(:region,"Cloud region")
        end

        # currently supported clouds
        # Note to Aspera: shall be an API call
        def all_clouds
          return {
            :aws =>'Amazon Web Services',
            :azure =>'Microsoft Azure',
            :google =>'Google Cloud',
            :limelight =>'Limelight',
            :rackspace =>'Rackspace',
            :softlayer =>'IBM Cloud'
          }
        end

        # all available ATS servers
        # NOTE to Aspera: an API shall be created to retrieve all servers at once
        def all_servers
          if @all_servers_cache.nil?
            @all_servers_cache=[]
            all_clouds.keys.each do |name|
              api_public.read("servers/#{name.to_s.upcase}")[:data].each do |i|
                @all_servers_cache.push(i)
              end
            end
          end
          return @all_servers_cache
        end

        #
        def server_by_cloud_region
          # todo: provide list ?
          cloud=@optmgr.get_option(:cloud,:mandatory).upcase
          region=@optmgr.get_option(:region,:mandatory)
          return api_public.read("servers/#{cloud}/#{region}")[:data]
        end

        def execute_action_access_key
          commands=[:create,:list,:show,:delete,:node]
          if ats_api_provider.respond_to?(:execute_action_api_key)
            commands.push(:cluster)
          end
          command=@optmgr.get_next_argument('command',commands)
          # those dont require access key id
          unless [:create,:list].include?(command)
            access_key_id=@optmgr.get_option(:id,:mandatory)
          end
          case command
          when :create
            params=@optmgr.get_option(:params,:optional) || {}
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
                  server_data||=all_servers.select{|i|i['id'].eql?(params['transfer_server_id'])}.first
                  params['storage']['credentials']['authentication_endpoint'] = server_data['swift_authentication_endpoint']
                end
              end
            end
            res=api_secure.create("access_keys",params)
            return {:type=>:key_val_list, :data=>res[:data]}
            # TODO : action : modify, with "PUT"
          when :list
            params=@optmgr.get_option(:params,:optional) || {'offset'=>0,'max_results'=>1000}
            res=api_secure.read("access_keys",params)
            return {:type=>:hash_array, :data=>res[:data]['data'], :fields => ['name','id','secret','created','modified']}
          when :show
            res=api_secure.read("access_keys/#{access_key_id}")
            return {:type=>:key_val_list, :data=>res[:data]}
          when :delete
            res=api_secure.delete("access_keys/#{access_key_id}")
            return Plugin.result_status("deleted #{access_key_id}")
          when :node
            ak_data=api_secure.read("access_keys/#{access_key_id}")[:data]
            server_data=all_servers.select {|i| i['id'].start_with?(ak_data['transfer_server_id'])}.first
            raise CliError,"no such server found" if server_data.nil?
            api_node=Rest.new(server_data['transfer_setup_url'],{:auth=>{:type=>:basic,:username=>ak_data['id'], :password=>ak_data['secret']}})
            command=@optmgr.get_next_argument('command',Node.common_actions)
            Node.new(self).execute_common(command,api_node)
          when :cluster
            api_auth={
              :type=>:basic,
              :username=>access_key_id,
              :password=>@optmgr.get_option(:secret,:optional)
            }
            # if no access key id provided, then we get from ATS API
            if api_auth[:secret].nil?
              ak_data=api_secure.read("access_keys/#{access_key_id}")[:data]
              #api_auth[:username]=ak_data['id']
              api_auth[:password]=ak_data['secret']
            end
            api_ak_auth=Rest.new(ats_api_provider.ats_api_base_url,{:auth => api_auth})
            return {:type=>:key_val_list, :data=>api_ak_auth.read("servers")[:data]}
          else raise "INTERNAL ERROR"
          end
        end

        def execute_action_cluster
          command=@optmgr.get_next_argument('command',[ :clouds, :list, :show])
          case command
          when :clouds
            return {:type=>:key_val_list, :data=>all_clouds, :columns=>['id','name']}
          when :list
            return {:type=>:hash_array, :data=>all_servers, :fields=>['id','cloud','region']}
          when :show
            server_id=@optmgr.get_option(:id,:optional)
            if server_id.nil?
              server_data=server_by_cloud_region
            else
              server_data=all_servers.select {|i| i['id'].eql?(server_id)}.first
              raise "no such server id" if server_data.nil?
            end
            return {:type=>:key_val_list, :data=>server_data}
          end
        end

        def action_list;
          res=[ :cluster, :access_key ]
          if ats_api_provider.respond_to?(:execute_action_api_key)
            res.push(:credential)
          end
          return res
        end

        def execute_action_gen
          command=@optmgr.get_next_argument('command',action_list)
          case command
          when :cluster # display general ATS cluster information
            return execute_action_cluster
          when :access_key
            return execute_action_access_key
          when :credential # manage credential to access ATS API
            return ats_api_provider.execute_action_api_key
          else raise "ERROR"
          end
        end

        def execute_action
          self.ats_api_provider=LegacyAts.new
          ats_api_provider.optmgr=self.optmgr
          ats_api_provider.main=self.main
          execute_action_gen
        end
      end
    end
  end # Cli
end # Asperalm
