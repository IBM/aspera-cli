require 'asperalm/cli/main'
require 'asperalm/cli/plugins/node'
require 'asperalm/oauth'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions
      # https://52.44.83.163/docs/pub/
      class Ats < Plugin
        # main url for ATS API
        ATS_API_URL = 'https://ats.aspera.io/pub/v1'
        # local address to receive code on authentication
        LOCAL_REDIRECT_URI="http://localhost:12345"
        # cache file for CLI for API keys
        API_KEY_REPOSITORY=File.join(Main.tool.config_folder,"ats_api_keys.json")
        def declare_options
          Main.tool.options.add_opt_simple(:ats_id,"ATS_ID","ATS key identifier (ats_xxx)")
          Main.tool.options.add_opt_simple(:params,"JSON","parameters for access key")
          Main.tool.options.add_opt_simple(:cloud,"PROVIDER","cloud provider")
          Main.tool.options.add_opt_simple(:region,"REGION","cloud region")
        end

        # currently supported clouds
        # note: shall be an API call
        @@SUPPORTED_CLOUDS={
          :aws =>'Amazon Web Services',
          :azure =>'Microsoft Azure',
          :google =>'Google Cloud',
          :limelight =>'Limelight',
          :rackspace =>'Rackspace',
          :softlayer =>'IBM Cloud'
        }

        # all available ATS servers
        def all_servers
          if @all_servers.nil?
            @all_servers=[]
            @@SUPPORTED_CLOUDS.keys.each { |name| @api_pub.read("servers/#{name.to_s.upcase}")[:data].each {|i| @all_servers.push(i)}}
          end
          return @all_servers
        end

        # all ATS API keys stored in cache file
        def repo_api_keys
          if @repo_api_keys.nil?
            @repo_api_keys=[]
            if File.exist?(API_KEY_REPOSITORY)
              @repo_api_keys=JSON.parse(File.read(API_KEY_REPOSITORY))
            end
          end
          @repo_api_keys
        end

        # write ATS API keys cache file after modification
        def save_key_repo
          File.write(API_KEY_REPOSITORY,JSON.generate(repo_api_keys))
        end

        # get an api key
        # either first one stored in repository
        # or the one specified on command line
        # or creates a new one
        def current_api_key
          if @current_api_key_info.nil?
            requested_id=Main.tool.options.get_option(:ats_id,:optional)
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
          # get login page url in exception code 3xx
          res=@api_pub.call({:operation=>'POST',:subpath=>"api_keys",:return_error=>true,:headers=>{'Accept'=>'application/json'},:url_params=>{:description => "created by aslmcli",:redirect_uri=>LOCAL_REDIRECT_URI}})
          # TODO: check code is 3xx ?
          login_page_url=res[:http]['Location']
          new_api_key_info=Oauth.goto_page_and_get_request(LOCAL_REDIRECT_URI,login_page_url)
          @current_api_key_info=new_api_key_info
          # add extra information on api key to identify different subscriptions
          subscription=api_auth.read("subscriptions")[:data]
          new_api_key_info['subscription_name']=subscription['name']
          new_api_key_info['organization_name']=subscription['aspera_id_user']['organization']['name']
          repo_api_keys.push(new_api_key_info)
          save_key_repo
          return new_api_key_info
        end

        # authenticated API
        def api_auth
          if @api_auth.nil?
            @api_auth=Rest.new(ATS_API_URL,{:auth => {:type=>:basic,:username=>current_api_key['ats_id'],:password=>current_api_key['ats_secret']}})
          end
          @api_auth
        end

        #
        def server_by_cloud_region
          cloud=Main.tool.options.get_option(:cloud,:mandatory).upcase
          region=Main.tool.options.get_option(:region,:mandatory)
          return @api_pub.read("servers/#{cloud}/#{region}")[:data]
        end

        def execute_action_access_key
          command=Main.tool.options.get_next_argument('command',[:list,:id,:create,:server])
          case command
          when :server
            api_ak_auth=Rest.new(ATS_API_URL,{:auth => {:type=>:basic,:username=>Main.tool.options.get_next_argument("access key"),:password=>Main.tool.options.get_next_argument("secret")}})
            return {:type=>:key_val_list, :data=>api_ak_auth.read("servers")[:data]}
          when :create #
            params=Main.tool.options.get_option(:params,:optional)
            params={} if params.nil?
            # if transfer_server_id not provided, get it from options
            if !params.has_key?('transfer_server_id')
              params['transfer_server_id']=server_by_cloud_region['id']
            end
            if params.has_key?('storage')
              case params['storage']['type']
              # here we need somehow to map storage type to field to get for auth end point
              when 'softlayer_swift'
                if !params['storage'].has_key?('authentication_endpoint')
                  server_data=all_servers.select {|i| i['id'].eql?(params['transfer_server_id'])}.first
                  params['storage']['credentials']['authentication_endpoint'] = server_data['swift_authentication_endpoint']
                end
              end
            end
            res=api_auth.create("access_keys",params)
            return {:type=>:key_val_list, :data=>res[:data]}
            # TODO : action : modify, with "PUT"
          when :list #
            res=api_auth.read("access_keys",{'offset'=>0,'max_results'=>1000})
            return {:type=>:hash_array, :data=>res[:data]['data'], :name => 'access_key'}
          when :id #
            access_key=Main.tool.options.get_next_argument("access_key")
            command=Main.tool.options.get_next_argument('command',[:show,:delete,:node,:server])
            case command
            when :show #
              res=api_auth.read("access_keys/#{access_key}")
              return {:type=>:key_val_list, :data=>res[:data]}
            when :delete #
              res=api_auth.delete("access_keys/#{access_key}")
              return {:type=>:status, :data=>"deleted #{access_key}"}
            when :node
              ak_data=api_auth.read("access_keys/#{access_key}")[:data]
              server_data=all_servers.select {|i| i['id'].eql?(ak_data['transfer_server_id'])}.first
              api_node=Rest.new(server_data['transfer_setup_url'],{:auth=>{:type=>:basic,:username=>ak_data['id'], :password=>ak_data['secret']}})
              command=Main.tool.options.get_next_argument('command',Node.common_actions)
              Node.execute_common(command,api_node)
            when :server
              ak_data=api_auth.read("access_keys/#{access_key}")[:data]
              api_ak_auth=Rest.new(ATS_API_URL,{:auth => {:type=>:basic,:username=>ak_data['id'],:password=>ak_data['secret']}})
              return {:type=>:key_val_list, :data=>api_ak_auth.read("servers")[:data]}
            end
          end
        end

        def execute_action_server
          command=Main.tool.options.get_next_argument('command',[:list,:id])
          case command
          when :list #
            command=Main.tool.options.get_next_argument('command',[:provisioned,:clouds,:instance])
            case command
            when :provisioned #
              return {:type=>:hash_array, :data=>all_servers, :fields=>['id','cloud','region']}
            when :clouds #
              return {:type=>:key_val_list, :data=>@@SUPPORTED_CLOUDS, :columns=>['id','name']}
            when :instance #
              return {:type=>:key_val_list, :data=>server_by_cloud_region}
            end
          when :id #
            server_id=Main.tool.options.get_next_argument('server id',all_servers.map{|i| i['id']})
            server_data=all_servers.select {|i| i['id'].eql?(server_id)}.first
            return {:type=>:key_val_list, :data=>server_data}
          end
        end

        def execute_action_api_key
          command=Main.tool.options.get_next_argument('command',[:current,:create,:repository,:list,:id])
          case command
          when :current #
            return {:type=>:key_val_list, :data=>current_api_key}
          when :repository #
            command=Main.tool.options.get_next_argument('command',[:list,:delete])
            case command
            when :list #
              return {:type=>:hash_array, :data=>repo_api_keys, :fields =>['ats_id','ats_secret','ats_description','subscription_name','organization_name']}
            when :delete #
              ats_id=Main.tool.options.get_next_argument('ats_id',repo_api_keys.map{|i| i['ats_id']})
              #raise CliBadArgument,"no such id" if repo_api_keys.select{|i| i['ats_id'].eql?(ats_id)}.empty?
              repo_api_keys.select!{|i| !i['ats_id'].eql?(ats_id)}
              save_key_repo
              return {:type=>:hash_array, :data=>[{'ats_id'=>ats_id,'status'=>'deleted'}]}
            end
          when :create #
            return {:type=>:key_val_list, :data=>create_new_api_key}
          when :list #
            res=api_auth.read("api_keys",{'offset'=>0,'max_results'=>1000})
            return {:type=>:value_list, :data=>res[:data]['data'], :name => 'ats_id'}
          when :id #
            ats_id=Main.tool.options.get_next_argument("ats_id")
            command=Main.tool.options.get_next_argument('command',[:show,:delete])
            case command
            when :show #
              res=api_auth.read("api_keys/#{ats_id}")
              return {:type=>:key_val_list, :data=>res[:data]}
            when :delete #
              res=api_auth.delete("api_keys/#{ats_id}")
              return {:type=>:status, :data=>"deleted #{ats_id}"}
            end
          end
        end

        def action_list; [ :server, :api_key, :subscriptions, :access_key ];end

        def execute_action
          # API without authentication
          @api_pub=Rest.new(ATS_API_URL)
          command=Main.tool.options.get_next_argument('command',action_list)
          case command
          when :access_key
            return execute_action_access_key
          when :subscriptions
            return {:type=>:key_val_list, :data=>api_auth.read("subscriptions")[:data]}
          when :server
            return execute_action_server
          when :api_key
            return execute_action_api_key
          end
        end
      end
    end
  end # Cli
end # Asperalm
