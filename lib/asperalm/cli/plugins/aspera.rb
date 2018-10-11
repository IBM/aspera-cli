require 'asperalm/cli/plugins/node'
require 'asperalm/cli/plugins/ats'
require 'asperalm/cli/plugin'
require 'asperalm/files_api'
require 'securerandom'
require 'singleton'

module Asperalm
  module Cli
    module Plugins
      class Aspera < Plugin
        include Singleton
        def action_list; [ :packages, :files, :faspexgw, :admin, :user, :organization];end

        def declare_options
          @ats=Ats.instance
          @ats.declare_options(true)

          Main.instance.options.add_opt_list(:download_mode,[:fasp, :node_http ],"download mode")
          Main.instance.options.add_opt_list(:auth,Oauth.auth_types,"type of Oauth authentication")
          Main.instance.options.add_opt_boolean(:bulk,"bulk operation")
          #Main.instance.options.add_opt_boolean(:long,"long display")
          Main.instance.options.add_opt_simple(:url,"URL of application, e.g. http://org.asperafiles.com")
          Main.instance.options.add_opt_simple(:username,"username to log in")
          Main.instance.options.add_opt_simple(:password,"user's password")
          Main.instance.options.add_opt_simple(:client_id,"API client identifier in application")
          Main.instance.options.add_opt_simple(:client_secret,"API client passcode")
          Main.instance.options.add_opt_simple(:redirect_uri,"API client redirect URI")
          Main.instance.options.add_opt_simple(:private_key,"RSA private key PEM value for JWT (prefix file path with @val:@file:)")
          Main.instance.options.add_opt_simple(:workspace,"name of workspace")
          Main.instance.options.add_opt_simple(:recipient,"package recipient")
          Main.instance.options.add_opt_simple(:secret,"access key secret for node")
          Main.instance.options.add_opt_simple(:eid,"identifier")
          Main.instance.options.add_opt_simple(:name,"resource name")
          Main.instance.options.add_opt_simple(:link,"link to shared resource")
          Main.instance.options.add_opt_simple(:public_token,"token value of public link")
          Main.instance.options.set_option(:download_mode,:fasp)
          Main.instance.options.set_option(:bulk,:no)
          #Main.instance.options.set_option(:long,:no)
          Main.instance.options.set_option(:redirect_uri,'http://localhost:12345')
          Main.instance.options.set_option(:auth,:web)
        end

        def self.execute_node_gen4_action(api_files,home_node_id,home_file_id)
          command_repo=Main.instance.options.get_next_argument('command',[ :access_key, :browse, :mkdir, :rename, :delete, :upload, :download, :node, :file  ])
          case command_repo
          when :access_key
            node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id)
            node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            return Plugin.entity_action(node_api,'access_keys',['id','root_file_id','storage','license'],:eid)
          when :browse
            thepath=Main.instance.options.get_next_argument("path")
            node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id,thepath)
            node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            items=node_api.read("files/#{file_id}/files")[:data]
            return {:type=>:object_list,:data=>items,:fields=>['name','type','recursive_size','size','modified_time','access_level']}
          when :mkdir
            thepath=Main.instance.options.get_next_argument("path")
            containing_folder_path = thepath.split(FilesApi::PATH_SEPARATOR)
            new_folder=containing_folder_path.pop
            node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id,containing_folder_path.join(FilesApi::PATH_SEPARATOR))
            node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            result=node_api.create("files/#{file_id}/files",{:name=>new_folder,:type=>:folder})[:data]
            return Main.result_status("created: #{result['name']} (id=#{result['id']})")
          when :rename
            thepath=Main.instance.options.get_next_argument("source path")
            newname=Main.instance.options.get_next_argument("new name")
            node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id,thepath)
            node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            result=node_api.update("files/#{file_id}",{:name=>newname})[:data]
            return Main.result_status("renamed #{thepath} to #{newname}")
          when :delete
            thepath=Main.instance.options.get_next_argument("path")
            node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id,thepath)
            node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            result=node_api.delete("files/#{file_id}")[:data]
            return Main.result_status("deleted: #{thepath}")
          when :upload
            filelist = Main.instance.options.get_next_argument("file list",:multiple)
            Log.log.debug("file list=#{filelist}")
            node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id,Main.instance.destination_folder('send'))
            return Main.instance.start_transfer_wait_result(api_files.ts('files','send',node_info,file_id,{'paths'=>filelist.map{|i|{'source'=>i}}}),:node_gen4)
          when :download
            source_file=Main.instance.options.get_next_argument('source')
            case Main.instance.options.get_option(:download_mode,:mandatory)
            when :fasp
              file_path = source_file.split(FilesApi::PATH_SEPARATOR)
              file_name = file_path.pop
              node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id,file_path.join(FilesApi::PATH_SEPARATOR))
              return Main.instance.start_transfer_wait_result(api_files.ts('files','receive',node_info,file_id,{'paths'=>[{'source'=>file_name}]}),:node_gen4)
            when :node_http
              file_path = source_file.split(FilesApi::PATH_SEPARATOR)
              file_name = file_path.last
              node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,home_file_id,source_file)
              node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
              node_api.call({:operation=>'GET',:subpath=>"files/#{file_id}/content",:save_to_file=>File.join(Main.instance.destination_folder('receive'),file_name)})
              return Main.result_status("downloaded: #{file_name}")
            end # download_mode
          when :node
            # Note: other "common" actions are unauthorized with user scope
            command_legacy=Main.instance.options.get_next_argument('command',Node.simple_actions)
            # TODO: shall we support all methods here ? what if there is a link ?
            node_info=api_files.read("nodes/#{home_node_id}")[:data]
            node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            return Node.execute_common(command_legacy,node_api)
          when :file
            fileid=Main.instance.options.get_next_argument("file id")
            node_info,file_id = api_files.find_nodeinfo_and_fileid(home_node_id,fileid)
            node_api=api_files.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            items=node_api.read("files/#{file_id}")[:data]
            return {:type=>:single_object,:data=>items}
          end # command_repo
        end # def

        attr_accessor :api_files_admn
        attr_accessor :api_files_user

        # build REST object parameters based on command line options
        def get_aoc_rest_params
          public_link_url=Main.instance.options.get_option(:link,:optional)

          # if auth is a public link, option "link" is a shortcut for options: url, auth, public_token
          unless public_link_url.nil?
            uri=URI.parse(public_link_url)
            public_link_url=nil #no more needed
            unless uri.path.eql?(FilesApi.PATH_PUBLIC_PACKAGE)
              raise CliArgument,"only public package link is supported: #{FilesApi.PATH_PUBLIC_PACKAGE}"
            end
            url_token_value=URI::decode_www_form(uri.query).select{|e|e.first.eql?('token')}.first
            if url_token_value.nil?
              raise CliArgument,"link option must be url with 'token' parameter"
            end
            Main.instance.options.set_option(:url,'https://'+uri.host)
            Main.instance.options.set_option(:public_token,url_token_value)
            Main.instance.options.set_option(:auth,:url_token)
            Main.instance.options.set_option(:client_id,FilesApi.random.first)
            Main.instance.options.set_option(:client_secret,FilesApi.random.last)
          end
          # Connection paramaters (url and auth) to Aspera on Cloud
          # pre populate rest parameters based on URL
          aoc_rest_params=
          FilesApi.base_rest_params(Main.instance.options.get_option(:url,:mandatory)).merge({
            :oauth_type          => Main.instance.options.get_option(:auth,:mandatory),
            :oauth_client_id     => Main.instance.options.get_option(:client_id,:mandatory),
            :oauth_client_secret => Main.instance.options.get_option(:client_secret,:mandatory)
          })

          # fill other auth parameters based on Oauth method
          case aoc_rest_params[:oauth_type]
          when :web
            aoc_rest_params.merge!({
              :oauth_redirect_uri => Main.instance.options.get_option(:redirect_uri,:mandatory)
            })
          when :jwt
            private_key_PEM_string=Main.instance.options.get_option(:private_key,:mandatory)
            aoc_rest_params.merge!({
              :oauth_jwt_subject         => Main.instance.options.get_option(:username,:mandatory),
              :oauth_jwt_private_key_obj => OpenSSL::PKey::RSA.new(private_key_PEM_string)
            })
          when :url_token
            aoc_rest_params.merge!({
              :oauth_url_token     => Main.instance.options.get_option(:public_token,:mandatory),
            })
          else raise "ERROR: unsupported auth method"
          end
          Log.log.debug("REST params=#{aoc_rest_params}")
          return aoc_rest_params
        end

        # initialize apis and authentication
        # set:
        # @api_files_user
        # @api_files_admn
        # @default_workspace_id
        # @workspace_name
        # @workspace_id
        # @user_id
        # @home_file_id
        # @home_node_id
        # @ak_secret
        # returns nil
        def init_apis
          aoc_rest_params=get_aoc_rest_params

          # create objects for REST calls to Aspera (user and admin scope)
          # Note: bearev token is created on first use
          @api_files_user=FilesApi.new(aoc_rest_params.merge!({:oauth_scope=>FilesApi::SCOPE_FILES_USER}))
          @api_files_admn=FilesApi.new(aoc_rest_params.merge!({:oauth_scope=>FilesApi::SCOPE_FILES_ADMIN}))

          @org_data=@api_files_user.read("organization")[:data]
          if aoc_rest_params.has_key?(:oauth_url_token)
            url_token_data=@api_files_user.read("url_tokens")[:data].first
            @default_workspace_id=url_token_data['data']['workspace_id']
            @user_id='todo' # TODO : @org_data ?
            Main.instance.options.set_option(:id,url_token_data['data']['package_id'])
            @home_node_id=url_token_data['data']['node_id']
            @home_file_id=url_token_data['data']['file_id']
            url_token_data=nil # no more needed
          else
            # get our user's default information
            self_data=@api_files_user.read("self")[:data]
            @default_workspace_id=self_data['default_workspace_id']
            @user_id=self_data['id']
          end

          ws_name=Main.instance.options.get_option(:workspace,:optional)
          if ws_name.nil?
            Log.log.debug("using default workspace".green)
            if @default_workspace_id.eql?(nil)
              raise CliError,"no default workspace defined for user"
            end
            # get default workspace
            @workspace_id=@default_workspace_id
          else
            # lookup another workspace
            wss=@api_files_user.read("workspaces",{'q'=>ws_name})[:data]
            wss=wss.select { |i| i['name'].eql?(ws_name) }
            case wss.length
            when 0
              raise CliBadArgument,"no such workspace: #{ws_name}"
            when 1
              @workspace_id=wss.first['id']
            else
              raise "unexpected case"
            end
          end
          workspace_data=@api_files_user.read("workspaces/#{@workspace_id}")[:data]

          Log.log.debug("workspace_id=#{@workspace_id},workspace_data=#{workspace_data}".red)

          @workspace_name||=workspace_data['name']
          @home_node_id||=workspace_data['home_node_id']||workspace_data['node_id']
          @home_file_id||=workspace_data['home_file_id']
          raise "ERROR: assert: no home node id" if @home_node_id.to_s.empty?
          raise "ERROR: assert: no home file id" if @home_file_id.to_s.empty?

          @ak_secret=Main.instance.options.get_option(:secret,:optional)

          return nil
        end

        def do_bulk_operation(params,success,&do_action)
          params=[params] unless Main.instance.options.get_option(:bulk)
          raise "expecting Array" unless params.is_a?(Array)
          result=[]
          params.each do |p|
            # todo: manage exception and display status by default
            one=do_action.call(p)
            one['status']=success
            result.push(one)
          end
          return {:type=>:object_list,:data=>result,:fields=>['id','status']}
        end

        def execute_action
          init_apis
          command=Main.instance.options.get_next_argument('command',action_list)
          if Main.instance.options.get_option(:format,:optional).eql?(:table) and !command.eql?(:admin)
            default_ws=@workspace_id == @default_workspace_id ? ' (default)' : ''
            Main.instance.display_status "Current Workspace: #{@workspace_name.red}#{default_ws}"
          end

          # display name of current workspace
          Log.log.info("current workspace is "+@workspace_name.red)

          case command
          when :organization
            return { :type=>:single_object, :data =>@org_data }
          when :user
            command=Main.instance.options.get_next_argument('command',[ :workspaces,:info ])
            case command
            when :workspaces
              return {:type=>:object_list,:data=>@api_files_user.read("workspaces")[:data],:fields=>['id','name']}
              #              when :settings
              #                return {:type=>:object_list,:data=>@api_files_user.read("client_settings/")[:data]}
            when :info
              resource_instance_path="users/#{@user_id}"
              command=Main.instance.options.get_next_argument('command',[ :show,:modify ])
              case command
              when :show
                object=@api_files_user.read(resource_instance_path)[:data]
                return { :type=>:single_object, :data =>object }
              when :modify
                changes=Main.instance.options.get_next_argument('modified parameters (hash)')
                @api_files_user.update(resource_instance_path,changes)
                return Main.result_status('modified')
              end
            end
          when :packages
            command_pkg=Main.instance.options.get_next_argument('command',[ :send, :recv, :list, :show ])
            case command_pkg
            when :send
              package_creation=Main.instance.options.get_option(:value,:mandatory)
              raise CliBadArgument,"value must be hash, refer to doc" unless package_creation.is_a?(Hash)
              package_creation['workspace_id']=@workspace_id

              # list of files to include in package
              filelist=Main.instance.options.get_next_argument('file list',:multiple)
              package_creation['file_names']=filelist

              # lookup users
              package_creation['recipients']=Main.instance.options.get_option(:recipient,:mandatory).split(',').map do |recipient|
                user_lookup=@api_files_user.read('contacts',{'current_workspace_id'=>@workspace_id,'q'=>recipient})[:data]
                raise CliBadArgument,"no such user: #{recipient}" unless !user_lookup.nil? and user_lookup.length == 1
                recipient_user_id=user_lookup.first
                {'id'=>recipient_user_id['source_id'],'type'=>recipient_user_id['source_type']}
              end

              #  create a new package with one file
              the_package=@api_files_user.create('packages',package_creation)[:data]

              #  get node information for the node on which package must be created
              node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]

              # tell Aspera what to expect in package: 1 transfer (can also be done after transfer)
              resp=@api_files_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})[:data]
              return Main.instance.start_transfer_wait_result(@api_files_user.ts('packages','send',node_info,the_package['contents_file_id'],{
                'tags'=>{'aspera'=>{'files'=>{"package_id"=>the_package['id'],"package_operation"=>"upload"}}},
                'paths'=>filelist.map{|i|{'source'=>i}}
              }),:node_gen4)
            when :recv
              package_id=Main.instance.options.get_option(:id,:mandatory)
              the_package=@api_files_user.read("packages/#{package_id}")[:data]
              node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]
              return Main.instance.start_transfer_wait_result(@api_files_user.ts('packages','receive',node_info,the_package['contents_file_id'],{
                'tags'  => {'aspera'=>{'files'=>{'package_id'=>the_package['id'],'package_operation'=>'download'}}},
                'paths' => [{'source'=>'.'}]
              }),:node_gen4)
            when :show
              package_id=Main.instance.options.get_next_argument('package ID')
              the_package=@api_files_user.read("packages/#{package_id}")[:data]
              #              if Main.instance.options.get_option(:long)
              #                node_info,file_id = @api_files_user.find_nodeinfo_and_fileid(the_package['node_id'],the_package['contents_file_id'])
              #                node_api=@api_files_user.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
              #                items=node_api.read("files/#{file_id}/files")[:data]
              #                file=node_api.read("files/#{items.first['id']}")[:data]
              #                the_package['X_contents_path']=file['path']
              #              end
              return { :type=>:single_object, :data =>the_package }
            when :list
              # list all packages ('page'=>1,'per_page'=>10,)'sort'=>'-sent_at',
              packages=@api_files_user.read("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>@workspace_id})[:data]
              return {:type=>:object_list,:data=>packages,:fields=>['id','name','bytes_transferred']}
            end
          when :files
            @api_files_user.secrets[@home_node_id]=@ak_secret
            return self.class.execute_node_gen4_action(@api_files_user,@home_node_id,@home_file_id)
          when :faspexgw
            require 'asperalm/faspex_gw'
            FaspexGW.instance.start_server(@api_files_user,@workspace_id)
          when :admin
            command_admin=Main.instance.options.get_next_argument('command',[ :ats, :resource, :events, :set_client_key, :usage_reports, :search_nodes  ])
            case command_admin
            when :ats
              @ats.ats_api_public = @ats.ats_api_secure = Rest.new(@api_files_admn.params.clone.merge!({
                :base_url    => @api_files_admn.params[:base_url]+'/admin/ats/pub/v1',
                :oauth_scope => FilesApi::SCOPE_FILES_ADMIN_USER
              }))

              return @ats.execute_action_gen
            when :search_nodes
              ak=Main.instance.options.get_next_argument('access_key')
              nodes=@api_files_admn.read("search_nodes",{'q'=>'access_key:"'+ak+'"'})[:data]
              return {:type=>:other_struct,:data=>nodes}
            when :events
              # page=1&per_page=10&q=type:(file_upload+OR+file_delete+OR+file_download+OR+file_rename+OR+folder_create+OR+folder_delete+OR+folder_share+OR+folder_share_via_public_link)&sort=-date
              #events=@api_files_admn.read('events',{'q'=>'type:(file_upload OR file_download)'})[:data]
              #Log.log.info "events=#{JSON.generate(events)}"
              node_info=@api_files_user.read("nodes/#{@home_node_id}")[:data]
              # get access to node API, note the additional header
              @api_files_user.secrets[@home_node_id]=@ak_secret
              api_node=@api_files_user.get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
              # can add filters: tag=aspera.files.package_id%3DLA8OU3p8w
              #'tag'=>'aspera.files.package_id%3DJvbl0w-5A'
              # filter= 'id', 'short_summary', or 'summary'
              # count=nnn
              # tag=x.y.z%3Dvalue
              # iteration_token=nnn
              # active_only=true|false
              events=api_node.read("ops/transfers",{'count'=>100,'filter'=>'summary','active_only'=>'true'})[:data]
              return {:type=>:object_list,:data=>events,:fields=>['id','status']}
              #transfers=api_node.make_request_ex({:operation=>'GET',:subpath=>'ops/transfers',:args=>{'count'=>25,'filter'=>'id'}})
              #transfers=api_node.read("events") # after_time=2016-05-01T23:53:09Z
            when :set_client_key
              the_client_id=Main.instance.options.get_next_argument('client_id')
              the_private_key=Main.instance.options.get_next_argument('private_key')
              @api_files_admn.update("clients/#{the_client_id}",{:jwt_grant_enabled=>true, :public_key=>OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s})
              return Main.result_success
            when :resource
              resource_type=Main.instance.options.get_next_argument('resource',[:self,:user,:group,:client,:contact,:dropbox,:node,:operation,:package,:saml_configuration, :workspace, :dropbox_membership,:short_link,:workspace_membership])
              resource_class_path=resource_type.to_s+case resource_type;when :dropbox;'es';when :self;'';else; 's';end
              singleton_object=[:self].include?(resource_type)
              global_operations=[:create,:list]
              supported_operations=[:show]
              supported_operations.push(:modify,:delete,*global_operations) unless singleton_object
              supported_operations.push(:do) if resource_type.eql?(:node)
              supported_operations.push(:shared_folders) if resource_type.eql?(:workspace)
              command=Main.instance.options.get_next_argument('command',supported_operations)
              # require identifier for non global commands
              if !singleton_object and !global_operations.include?(command)
                res_id=Main.instance.options.get_option(:id)
                res_name=Main.instance.options.get_option(:name)
                if res_id.nil?
                  raise "Use either id or name" if res_name.nil?
                  matching=@api_files_admn.read(resource_class_path,{:q=>res_name})[:data]
                  raise CliError,"no resource match name" if matching.empty?
                  raise CliError,"several resources match name" unless matching.length.eql?(1)
                  res_id=matching.first['id']
                else
                  raise "Use either id or name" unless res_name.nil?
                end
                resource_instance_path="#{resource_class_path}/#{res_id}"
              end
              resource_instance_path=resource_class_path if singleton_object
              case command
              when :create
                list_or_one=Main.instance.options.get_next_argument("creation data (Hash)")
                return do_bulk_operation(list_or_one,'created')do|params|
                  raise "expecting Hash" unless params.is_a?(Hash)
                  @api_files_admn.create(resource_class_path,params)[:data]
                end
              when :list
                default_fields=['id','name']
                case resource_type
                when :node; default_fields.push('host','access_key')
                when :operation; default_fields=nil
                when :contact; default_fields=["email","name","source_id","source_type"]
                end
                query=Main.instance.options.get_option(:query,:optional)
                Log.log.debug("Query=#{query}".bg_red)
                begin
                  URI.encode_www_form(query) unless query.nil?
                rescue => e
                  raise CliBadArgument,"query must be an extended value which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
                end
                return {:type=>:object_list,:data=>@api_files_admn.read(resource_class_path,query)[:data],:fields=>default_fields}
              when :show
                object=@api_files_admn.read(resource_instance_path)[:data]
                fields=object.keys.select{|k|!k.eql?('certificate')}
                return { :type=>:single_object, :data =>object, :fields=>fields }
              when :modify
                changes=Main.instance.options.get_next_argument('modified parameters (hash)')
                @api_files_admn.update(resource_instance_path,changes)
                return Main.result_status('modified')
              when :delete
                return do_bulk_operation(res_id,'deleted')do|one_id|
                  @api_files_admn.delete("#{resource_class_path}/#{one_id.to_s}")
                  {'id'=>one_id}
                end
              when :do
                res_data=@api_files_admn.read(resource_instance_path)[:data]
                @api_files_admn.secrets[res_data['id']]=@ak_secret
                api_node=@api_files_admn.get_files_node_api(res_data,nil)
                ak_data=api_node.call({:operation=>'GET',:subpath=>"access_keys/#{res_data['access_key']}",:headers=>{'Accept'=>'application/json'}})[:data]
                return self.class.execute_node_gen4_action(@api_files_admn,res_id,ak_data['root_file_id'])
              when :shared_folders
                res_data=@api_files_admn.read("#{resource_class_path}/#{res_id}/permissions")[:data]
                return { :type=>:object_list, :data =>res_data , :fields=>['id','node_name','file_id']} #
              else raise :ERROR
              end
            when :usage_reports
              return {:type=>:object_list,:data=>@api_files_admn.read("usage_reports",{:workspace_id=>@workspace_id})[:data]}
            end
          end # action
          raise RuntimeError, "internal error"
        end
      end # Aspera
    end # Plugins
  end # Cli
end # Asperalm
