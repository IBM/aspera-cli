require 'asperalm/cli/plugins/node'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions
      # https://52.44.83.163/docs/pub/
      class Ats < Plugin
        # manage access to legacy ATS
        class LegacyAts < Plugin
          LEGACY_ATS_URI='https://ats.aspera.io/pub/v1'
          # local address to receive code on authentication
          LOCAL_REDIRECT_URI="http://localhost:12345"
          # cache located in application's config folder
          ATS_KEYS_FILENAME="ats_api_keys.json"
          attr_reader :ats_api_public
          def initialize(env)
            super(env)
            Log.log.debug("-> #{self.options}".red)
            # special
            @current_api_key_info=nil
            @ats_api_public = Rest.new({:base_url=>LEGACY_ATS_URI})
            @ats_api_secure = nil
            @api_keys_persistency=PersistencyFile.new(ATS_KEYS_FILENAME,{
              :default  => [],
              :delete   => lambda{|d|d.nil? or d.empty?}})
          end

          # authenticated API
          def ats_api_secure
            if @ats_api_secure.nil?
              @ats_api_secure=Rest.new({
                :base_url       => LEGACY_ATS_URI,
                :auth_type      => :basic,
                :basic_username => current_api_key['ats_id'],
                :basic_password => current_api_key['ats_secret']
              })
            end
            return @ats_api_secure
          end

          # all ATS API keys stored in cache file
          def repo_api_keys; return @api_keys_persistency.data;end

          # write ATS API keys cache file after modification
          def save_key_repo; @api_keys_persistency.save;end

          # get an api key
          # either first one stored in repository
          # or the one specified on command line
          # or creates a new one
          def current_api_key
            if @current_api_key_info.nil?
              requested_id=self.options.get_option(:ats_id,:optional)
              if requested_id.nil?
                # if no api key requested and no repo, create one
                create_new_api_key if repo_api_keys.empty?
                # else there must be only one
                raise "please select one api key with --ats-id, list with: #{Main.instance.program_name} ats api repo list" if repo_api_keys.length != 1
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
            res=ats_api_public.call({:operation=>'POST',:subpath=>"api_keys",:return_error=>true,:headers=>{'Accept'=>'application/json'},:url_params=>{:description => "created by #{Main.instance.program_name}",:redirect_uri=>LOCAL_REDIRECT_URI}})
            # TODO: check code is 3xx ?
            login_page_url=res[:http]['Location']
            @current_api_key_info=Oauth.goto_page_and_get_request(LOCAL_REDIRECT_URI,login_page_url)
            # add extra information on api key to identify different subscriptions
            subscription=ats_api_secure.read("subscriptions")[:data]
            @current_api_key_info['subscription_name']=subscription['name']
            @current_api_key_info['organization_name']=subscription['aspera_id_user']['organization']['name']
            repo_api_keys.push(@current_api_key_info)
            save_key_repo
            return @current_api_key_info
          end

          def execute_action_api_key
            command=self.options.get_next_command([:create, :list, :show, :delete, :info, :subscriptions, :cache])
            if [:show,:delete].include?(command)
              modified_ats_id=self.options.get_option(:id,:mandatory)
            end
            case command
            when :create
              return {:type=>:single_object, :data=>create_new_api_key}
            when :list # list known api keys in ATS (this require an api_key ...)
              res=ats_api_secure.read("api_keys",{'offset'=>0,'max_results'=>1000})
              return {:type=>:value_list, :data=>res[:data]['data'], :name => 'ats_id'}
            when :show # show one of api_key in ATS
              res=ats_api_secure.read("api_keys/#{modified_ats_id}")
              return {:type=>:single_object, :data=>res[:data]}
            when :delete #
              res=ats_api_secure.delete("api_keys/#{modified_ats_id}")
              return Main.result_status("deleted #{modified_ats_id}")
            when :info # display current ATS credential information
              return {:type=>:single_object, :data=>current_api_key}
            when :subscriptions
              return {:type=>:single_object, :data=>ats_api_secure.read("subscriptions")[:data]}
            when :cache # list of delete entries in api_key cache
              command=self.options.get_next_command([:list, :delete])
              case command
              when :list
                return {:type=>:object_list, :data=>repo_api_keys, :fields =>['ats_id','ats_secret','ats_description','subscription_name','organization_name']}
              when :delete
                deleted_ats_id=self.options.get_next_argument('ats_id',repo_api_keys.map{|i| i['ats_id']})
                #raise CliBadArgument,"no such id" if repo_api_keys.select{|i| i['ats_id'].eql?(ats_id)}.empty?
                repo_api_keys.select!{|i| !i['ats_id'].eql?(deleted_ats_id)}
                save_key_repo
                return {:type=>:object_list, :data=>[{'ats_id'=>deleted_ats_id,'status'=>'deleted'}]}
              end
            else raise "INTERNAL ERROR"
            end
          end
        end # LegacyAts

        attr_writer :ats_legacy
        attr_writer :ats_api_public
        attr_writer :ats_api_secure

        def initialize(agents)
          super(agents)
          @agents=agents
          @ats_legacy = nil
          # REST end points
          @ats_api_public = nil
          @ats_api_secure = nil
          # cache of server data
          @all_servers_cache=nil
        end

        def api_public
          if @ats_api_public.nil?
            raise "ERROR" if @ats_legacy.nil?
            @ats_api_public = @ats_legacy.ats_api_public
          end
          return @ats_api_public
        end

        def api_secure
          if @ats_api_secure.nil?
            raise "ERROR" if @ats_legacy.nil?
            @ats_api_secure = @ats_legacy.ats_api_secure
          end
          return @ats_api_secure
        end

        def declare_options(skip_common=false)
          unless skip_common
            self.options.add_opt_simple(:secret,"Access key secret")
          end
          self.options.add_opt_simple(:ats_id,"ATS key identifier (ats_xxx)")
          self.options.add_opt_simple(:params,"Parameters access key creation (@json:)")
          self.options.add_opt_simple(:cloud,"Cloud provider")
          self.options.add_opt_simple(:region,"Cloud region")
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
          cloud=self.options.get_option(:cloud,:mandatory).upcase
          region=self.options.get_option(:region,:mandatory)
          return api_public.read("servers/#{cloud}/#{region}")[:data]
        end

        def execute_action_access_key
          commands=[:create,:list,:show,:delete,:node]
          commands.push(:cluster) unless @ats_legacy.nil?
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
                  server_data||=all_servers.select{|i|i['id'].eql?(params['transfer_server_id'])}.first
                  params['storage']['credentials']['authentication_endpoint'] = server_data['swift_authentication_endpoint']
                end
              end
            end
            res=api_secure.create("access_keys",params)
            return {:type=>:single_object, :data=>res[:data]}
            # TODO : action : modify, with "PUT"
          when :list
            params=self.options.get_option(:params,:optional) || {'offset'=>0,'max_results'=>1000}
            res=api_secure.read("access_keys",params)
            return {:type=>:object_list, :data=>res[:data]['data'], :fields => ['name','id','secret','created','modified']}
          when :show
            res=api_secure.read("access_keys/#{access_key_id}")
            return {:type=>:single_object, :data=>res[:data]}
          when :delete
            res=api_secure.delete("access_keys/#{access_key_id}")
            return Main.result_status("deleted #{access_key_id}")
          when :node
            ak_data=api_secure.read("access_keys/#{access_key_id}")[:data]
            server_data=all_servers.select {|i| i['id'].start_with?(ak_data['transfer_server_id'])}.first
            raise CliError,"no such server found" if server_data.nil?
            api_node=Rest.new({:base_url=>server_data['transfer_setup_url'],:auth_type=>:basic,:basic_username=>ak_data['id'], :basic_password=>ak_data['secret']})
            command=self.options.get_next_command(Node.common_actions)
            return Node.new(@agents).set_api(api_node).execute_action(command)
          when :cluster
            rest_params={
              :base_url       => api_secure.params[:base_url],
              :auth_type      => :basic,
              :basic_username => access_key_id,
              :basic_password => self.options.get_option(:secret,:optional)
            }
            # if no access key id provided, then we get from ATS API
            if rest_params[:basic_password].nil?
              ak_data=api_secure.read("access_keys/#{access_key_id}")[:data]
              #rest_params[:username]=ak_data['id']
              rest_params[:basic_password]=ak_data['secret']
            end
            api_ak_auth=Rest.new(rest_params)
            return {:type=>:single_object, :data=>api_ak_auth.read("servers")[:data]}
          else raise "INTERNAL ERROR"
          end
        end

        def execute_action_cluster
          command=self.options.get_next_command([ :clouds, :list, :show])
          case command
          when :clouds
            return {:type=>:single_object, :data=>all_clouds, :columns=>['id','name']}
          when :list
            return {:type=>:object_list, :data=>all_servers, :fields=>['id','cloud','region']}
          when :show
            server_id=self.options.get_option(:id,:optional)
            if server_id.nil?
              server_data=server_by_cloud_region
            else
              server_data=all_servers.select {|i| i['id'].eql?(server_id)}.first
              raise "no such server id" if server_data.nil?
            end
            return {:type=>:single_object, :data=>server_data}
          end
        end

        def action_list;
          res=[ :cluster, :access_key ]
          res.push(:credential) unless @ats_legacy.nil?
          return res
        end

        # called for legacy and AoC
        def execute_action_gen
          command=self.options.get_next_command(action_list)
          case command
          when :cluster # display general ATS cluster information
            return execute_action_cluster
          when :access_key
            return execute_action_access_key
          when :credential # manage credential to access ATS API
            return @ats_legacy.execute_action_api_key
          else raise "ERROR"
          end
        end

        # called for legacy ATS only
        def execute_action
          @ats_legacy=LegacyAts.new(@agents)
          execute_action_gen
        end
      end
    end
  end # Cli
end # Asperalm
