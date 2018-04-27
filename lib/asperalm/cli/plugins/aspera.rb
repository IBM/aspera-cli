require 'asperalm/cli/plugins/node'
require 'asperalm/cli/plugin'
require 'asperalm/oauth'
require 'asperalm/files_api'
require 'securerandom'

module Asperalm
  module Cli
    module Plugins
      class Aspera < Plugin
        def action_list; [ :packages, :files, :faspexgw, :admin, :user];end

        def declare_options
          @optmgr.add_opt_list(:download_mode,[:fasp, :node_http ],"download mode")
          @optmgr.add_opt_list(:auth,Oauth.auth_types,"type of Oauth authentication")
          @optmgr.add_opt_boolean(:bulk,"bulk operation")
          #          @optmgr.add_opt_boolean(:long,"long display")
          @optmgr.add_opt_simple(:url,"URL of application, e.g. http://org.asperafiles.com")
          @optmgr.add_opt_simple(:username,"username to log in")
          @optmgr.add_opt_simple(:password,"user's password")
          @optmgr.add_opt_simple(:client_id,"API client identifier in application")
          @optmgr.add_opt_simple(:client_secret,"API client passcode")
          @optmgr.add_opt_simple(:redirect_uri,"API client redirect URI")
          @optmgr.add_opt_simple(:private_key,"RSA private key PEM value for JWT (prefix file path with @val:@file:)")
          @optmgr.add_opt_simple(:workspace,"name of workspace")
          @optmgr.add_opt_simple(:recipient,"package recipient")
          @optmgr.add_opt_simple(:title,"package title")
          @optmgr.add_opt_simple(:note,"package note")
          @optmgr.add_opt_simple(:secret,"access key secret for node")
          @optmgr.add_opt_simple(:query,"list filter (extended value: encode_www_form)")
          @optmgr.add_opt_simple(:id,"resource identifier")
          @optmgr.add_opt_simple(:name,"resource name")
          @optmgr.set_option(:download_mode,:fasp)
          @optmgr.set_option(:bulk,:no)
          #          @optmgr.set_option(:long,:no)
          @optmgr.set_option(:redirect_uri,'http://localhost:12345')
          @optmgr.set_option(:auth,:web)
        end

        # returns a node API for access key
        # no scope: requires secret
        # if secret present: use it
        def get_files_node_api(node_info,node_scope=nil)
          # if no scope, or secret provided on command line ...
          if node_scope.nil? or !@optmgr.get_option(:secret,:optional).nil?
            return Rest.new(node_info['url'],{:auth=>{:type=>:basic,:username=>node_info['access_key'], :password=>@optmgr.get_option(:secret,:mandatory)},:headers=>{'X-Aspera-AccessKey'=>node_info['access_key']}})
          end
          Log.log.warn("ignoring secret, using bearer token") if !@optmgr.get_option(:secret,:optional).nil?
          return Rest.new(node_info['url'],{:auth=>{:type=>:oauth2,:obj=>@api_files_oauth,:scope=>FilesApi.node_scope(node_info['access_key'],node_scope)},:headers=>{'X-Aspera-AccessKey'=>node_info['access_key']}})
        end

        # returns node information (returned by API) and file id, from a "/" based path
        # supports links to secondary nodes
        # input: root node and file id, and array for path
        # output: file_id and node_info  for the given path
        def find_nodeinfo_and_fileid( top_node_id, top_file_id, element_path_string='' )
          Log.log.debug "find_nodeinfo_and_fileid: nodeid=#{top_node_id}, fileid=#{top_file_id}, path=#{element_path_string}"
          raise "error" if top_node_id.to_s.empty?
          raise "error" if top_file_id.to_s.empty?
          # initialize loop elements
          current_path_elements=element_path_string.split(PATH_SEPARATOR).select{|i| !i.empty?}
          current_node_info=@api_files_user.read("nodes/#{top_node_id}")[:data]
          current_file_id = top_file_id
          current_file_info = nil

          while !current_path_elements.empty? do
            current_element_name = current_path_elements.shift
            Log.log.debug "searching #{current_element_name}".bg_green
            # get API if changed
            current_node_api=get_files_node_api(current_node_info,FilesApi::SCOPE_NODE_USER) if current_node_api.nil?
            # get folder content
            folder_contents = current_node_api.read("files/#{current_file_id}/files")
            Log.log.debug "folder_contents: #{folder_contents}"
            matching_folders = folder_contents[:data].select { |i| i['name'].eql?(current_element_name)}
            #Log.log.debug "matching_folders: #{matching_folders}"
            raise CliBadArgument, "no such folder: #{current_element_name} in #{folder_contents[:data].map { |i| i['name']}}" if matching_folders.empty?
            current_file_info = matching_folders.first
            # process type of file
            case current_file_info['type']
            when 'file'
              current_file_id=current_file_info["id"]
              # a file shall be terminal
              if !current_path_elements.empty? then
                raise CliBadArgument, "#{current_element_name} is a file, expecting folder to find: #{current_path_elements}"
              end
            when 'link'
              current_node_info=@api_files_user.read("nodes/#{current_file_info['target_node_id']}")[:data]
              current_file_id=current_file_info["target_id"]
              current_node_api=nil
            when 'folder'
              current_file_id=current_file_info["id"]
            else
              Log.log.warn "unknown element type: #{current_file_info['type']}"
            end
          end
          Log.log.info("file_id=#{current_file_id},node_info=#{current_node_info}")
          return current_node_info,current_file_id
        end

        # generate a transfer spec from node information and file id
        # NOTE: important: transfer id must be unique: generate random id (using a non unique id results in discard of tags, and package is not finalized)
        def info_to_tspec(app,direction,node_info,file_id)
          return {
            'direction'        => direction,
            'remote_user'      => 'xfer',
            'remote_host'      => node_info['host'],
            'fasp_port'        => 33001, # TODO: always the case ?
            'ssh_port'         => 33001, # TODO: always the case ?
            'token'            => @api_files_oauth.get_authorization(FilesApi.node_scope(node_info['access_key'],FilesApi::SCOPE_NODE_USER)),
            'tags'             => { "aspera" => {
            'app'   => app,
            'files' => { 'node_id' => node_info['id']},
            'node'  => { 'access_key' => node_info['access_key'], "file_id" => file_id } } } }
        end

        PATH_SEPARATOR='/'

        def execute_node_action(home_node_id,home_file_id)
          command_repo=@optmgr.get_next_argument('command',[ :browse, :mkdir, :rename, :delete, :upload, :download, :node, :file  ])
          case command_repo
          when :browse
            thepath=@optmgr.get_next_argument("path")
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,thepath)
            node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            items=node_api.read("files/#{file_id}/files")[:data]
            return {:type=>:hash_array,:data=>items,:fields=>['name','type','recursive_size','size','modified_time','access_level']}
          when :mkdir
            thepath=@optmgr.get_next_argument("path")
            containing_folder_path = thepath.split(PATH_SEPARATOR)
            new_folder=containing_folder_path.pop
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,containing_folder_path.join(PATH_SEPARATOR))
            node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            result=node_api.create("files/#{file_id}/files",{:name=>new_folder,:type=>:folder})[:data]
            return Plugin.result_status("created: #{result['name']} (id=#{result['id']})")
          when :rename
            thepath=@optmgr.get_next_argument("source path")
            newname=@optmgr.get_next_argument("new name")
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,thepath)
            node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            result=node_api.update("files/#{file_id}",{:name=>newname})[:data]
            return Plugin.result_status("renamed #{thepath} to #{newname}")
          when :delete
            thepath=@optmgr.get_next_argument("path")
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,thepath)
            node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            result=node_api.delete("files/#{file_id}")[:data]
            return Plugin.result_status("deleted: #{thepath}")
          when :upload
            filelist = @optmgr.get_next_argument("file list",:multiple)
            Log.log.debug("file list=#{filelist}")
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,@main.destination_folder('send'))
            tspec=info_to_tspec('files','send',node_info,file_id)
            tspec['paths']=filelist.map { |i| {'source'=>i} }
            return @main.start_transfer(tspec,:node_gen4)
          when :download
            source_file=@optmgr.get_next_argument('source')
            case @optmgr.get_option(:download_mode,:mandatory)
            when :fasp
              file_path = source_file.split(PATH_SEPARATOR)
              file_name = file_path.pop
              node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,file_path.join(PATH_SEPARATOR))
              tspec=info_to_tspec('files','receive',node_info,file_id)
              tspec['paths']=[{'source'=>file_name}]
              return @main.start_transfer(tspec,:node_gen4)
            when :node_http
              file_path = source_file.split(PATH_SEPARATOR)
              file_name = file_path.last
              node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,source_file)
              node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
              node_api.call({:operation=>'GET',:subpath=>"files/#{file_id}/content",:save_to_file=>File.join(@main.destination_folder('receive'),file_name)})
              return Plugin.result_status("downloaded: #{file_name}")
            end # download_mode
          when :node
            # Note: other "common" actions are unauthorized with user scope
            command_legacy=@optmgr.get_next_argument('command',Node.simple_actions)
            # TODO: shall we support all methods here ? what if there is a link ?
            node_info=@api_files_user.read("nodes/#{home_node_id}")[:data]
            node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            return Node.new(self).execute_common(command_legacy,node_api)
          when :file
            fileid=@optmgr.get_next_argument("file id")
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,fileid)
            node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            items=node_api.read("files/#{file_id}")[:data]
            return {:type=>:key_val_list,:data=>items}
          end # command_repo
        end # def

        # initialize apis and authentication
        # returns true if in default workspace
        def init_apis

          api_info=FilesApi.info(@optmgr.get_option(:url,:mandatory))

          auth_data={
            :baseurl            => api_info[:api_url],
            :authorize_path     => api_info[:oauth_authorize],
            :token_path         => api_info[:oauth_token],
            :persist_folder     => @main.config_folder,
            :type               => @optmgr.get_option(:auth,:mandatory),
            :client_id          => @optmgr.get_option(:client_id,:mandatory),
            :client_secret      => @optmgr.get_option(:client_secret,:mandatory)
          }

          case auth_data[:type]
          when :basic
            auth_data[:username]=@optmgr.get_option(:username,:mandatory)
            auth_data[:password]=@optmgr.get_option(:password,:mandatory)
          when :web
            auth_data[:redirect_uri]=@optmgr.get_option(:redirect_uri,:mandatory)
            Log.log.info("redirect_uri=#{auth_data[:redirect_uri]}")
          when :jwt
            private_key_PEM_string=@optmgr.get_option(:private_key,:mandatory)
            auth_data[:private_key_obj]=OpenSSL::PKey::RSA.new(private_key_PEM_string)
            auth_data[:username]=@optmgr.get_option(:username,:mandatory)
            auth_data[:audience]=api_info[:jwt_audience]
            Log.log.info("private_key=#{auth_data[:private_key_obj]}")
            Log.log.info("subject=#{auth_data[:username]}")
          when :url_token
            auth_data[:url_token]=@optmgr.get_option(:url_token,:mandatory)
          else
            raise "unknown auth type: #{auth_data[:type].class}:#{auth_data[:type]}"
          end

          # auth API
          @api_files_oauth=Oauth.new(auth_data)

          # create objects for REST calls to Aspera (user and admin scope)
          @api_files_user=Rest.new(api_info[:api_url],{:auth=>{:type=>:oauth2,:obj=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_USER}})
          @api_files_admin=Rest.new(api_info[:api_url],{:auth=>{:type=>:oauth2,:obj=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_ADMIN}})

          # get our user's default information
          @self_data=@api_files_user.read("self")[:data]

          ws_name=@optmgr.get_option(:workspace,:optional)
          if ws_name.nil?
            # get default workspace
            @workspace_id=@self_data['default_workspace_id']
            @workspace_data=@api_files_user.read("workspaces/#{@workspace_id}")[:data]
          else
            # lookup another workspace
            wss=@api_files_user.read("workspaces",{'q'=>ws_name})[:data]
            wss=wss.select { |i| i['name'].eql?(ws_name) }
            case wss.length
            when 0
              raise CliBadArgument,"no such workspace: #{ws_name}"
            when 1
              @workspace_data=wss[0]
              @workspace_id=@workspace_data['id']
            else
              raise "unexpected case"
            end
          end

          Log.log.debug("workspace_id=#{@workspace_id},workspace_data=#{@workspace_data}".red)

          @home_node_id=@workspace_data['home_node_id']
          @home_file_id=@workspace_data['home_file_id']
          raise "error" if @home_node_id.to_s.empty?
          raise "error" if @home_file_id.to_s.empty?

          nil
        end

        def do_bulk_operation(params,success,&do_action)
          params=[params] unless @optmgr.get_option(:bulk)
          raise "expecting Array" unless params.is_a?(Array)
          result=[]
          params.each do |p|
            # todo: manage exception and display status by default
            one=do_action.call(p)
            one['status']=success
            result.push(one)
          end
          return {:type=>:hash_array,:data=>result,:fields=>['id','status']}
        end

        def execute_action
          init_apis
          command=@optmgr.get_next_argument('command',action_list)
          if @optmgr.get_option(:format,:optional).eql?(:table) and !command.eql?(:admin)
            default_ws=@workspace_id == @self_data['default_workspace_id'] ? ' (default)' : ''
            puts "Current Workspace: #{@workspace_data['name'].red}#{default_ws}"
          end

          # display name of default workspace
          Log.log.info("current workspace is "+@workspace_data['name'].red)

          case command
          when :user
            command=@optmgr.get_next_argument('command',[ :workspaces,:info ])
            case command
            when :workspaces
              return {:type=>:hash_array,:data=>@api_files_user.read("workspaces")[:data],:fields=>['id','name']}
              #              when :settings
              #                return {:type=>:hash_array,:data=>@api_files_user.read("client_settings/")[:data]}
            when :info
              resource_instance_path="users/#{@self_data['id']}"
              command=@optmgr.get_next_argument('command',[ :show,:modify ])
              case command
              when :show
                object=@api_files_admin.read(resource_instance_path)[:data]
                return { :type=>:key_val_list, :data =>object }
              when :modify
                changes=@optmgr.get_next_argument('modified parameters (hash)')
                @api_files_admin.update(resource_instance_path,changes)
                return Plugin.result_status('modified')
              end
            end
          when :packages
            command_pkg=@optmgr.get_next_argument('command',[ :send, :recv, :list, :show ])
            case command_pkg
            when :send
              # list of files to include in package
              filelist = @optmgr.get_next_argument("file list",:multiple)

              # lookup users
              recipient_data=@optmgr.get_option(:recipient,:mandatory).split(',').map { |recipient|
                user_lookup=@api_files_user.read("contacts",{'current_workspace_id'=>@workspace_id,'q'=>recipient})[:data]
                raise CliBadArgument,"no such user: #{recipient}" unless !user_lookup.nil? and user_lookup.length == 1
                recipient_user_id=user_lookup.first
                {"id"=>recipient_user_id['source_id'],"type"=>recipient_user_id['source_type']}
              }

              #  create a new package with one file
              the_package=@api_files_user.create("packages",{"workspace_id"=>@workspace_id,"name"=>@optmgr.get_option(:title,:mandatory),"file_names"=>filelist,"note"=>@optmgr.get_option(:note,:mandatory),"recipients"=>recipient_data})[:data]

              #  get node information for the node on which package must be created
              node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]

              # tell Aspera what to expect in package: 1 transfer (can also be done after transfer)
              resp=@api_files_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})[:data]

              tspec=info_to_tspec('packages','send',node_info,the_package['contents_file_id'])
              tspec['tags']['aspera']['files'].merge!({"package_id" => the_package['id'], "package_operation" => "upload"})
              tspec['paths']=filelist.map { |i| {'source'=>i} }
              return @main.start_transfer(tspec,:node_gen4)
            when :recv
              package_id=@optmgr.get_next_argument('package ID')
              the_package=@api_files_user.read("packages/#{package_id}")[:data]
              node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]
              tspec=info_to_tspec('packages','receive',node_info,the_package['contents_file_id'])
              tspec['tags']['aspera']['files'].merge!({"package_id" => the_package['id'], "package_operation" => "download"})
              tspec['paths']=[{'source'=>'.'}]
              return @main.start_transfer(tspec,:node_gen4)
            when :show
              package_id=@optmgr.get_next_argument('package ID')
              the_package=@api_files_user.read("packages/#{package_id}")[:data]
              #              if @optmgr.get_option(:long)
              #                node_info,file_id = find_nodeinfo_and_fileid(the_package['node_id'],the_package['contents_file_id'])
              #                node_api=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
              #                items=node_api.read("files/#{file_id}/files")[:data]
              #                file=node_api.read("files/#{items.first['id']}")[:data]
              #                the_package['X_contents_path']=file['path']
              #              end
              return { :type=>:key_val_list, :data =>the_package }
            when :list
              # list all packages ('page'=>1,'per_page'=>10,)'sort'=>'-sent_at',
              packages=@api_files_user.read("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>@workspace_id})[:data]
              return {:type=>:hash_array,:data=>packages,:fields=>['id','name','bytes_transferred']}
            end
          when :files
            return execute_node_action(@home_node_id,@home_file_id)
          when :faspexgw
            require 'asperalm/faspex_gw'
            FaspexGW.instance.start_server(@api_files_user,@workspace_id)
          when :admin
            command_admin=@optmgr.get_next_argument('command',[ :resource, :events, :set_client_key, :usage_reports, :search_nodes  ])
            case command_admin
            when :search_nodes
              ak=@optmgr.get_next_argument('access_key')
              nodes=@api_files_admin.read("search_nodes",{'q'=>'access_key:"'+ak+'"'})[:data]
              return {:type=>:other_struct,:data=>nodes}
            when :events
              # page=1&per_page=10&q=type:(file_upload+OR+file_delete+OR+file_download+OR+file_rename+OR+folder_create+OR+folder_delete+OR+folder_share+OR+folder_share_via_public_link)&sort=-date
              #events=@api_files_admin.read('events',{'q'=>'type:(file_upload OR file_download)'})[:data]
              #Log.log.info "events=#{JSON.generate(events)}"
              node_info=@api_files_user.read("nodes/#{@home_node_id}")[:data]
              # get access to node API, note the additional header
              api_node=get_files_node_api(node_info,FilesApi::SCOPE_NODE_USER)
              # can add filters: tag=aspera.files.package_id%3DLA8OU3p8w
              #'tag'=>'aspera.files.package_id%3DJvbl0w-5A'
              # filter= 'id', 'short_summary', or 'summary'
              # count=nnn
              # tag=x.y.z%3Dvalue
              # iteration_token=nnn
              # active_only=true|false
              events=api_node.read("ops/transfers",{'count'=>100,'filter'=>'summary','active_only'=>'true'})[:data]
              return {:type=>:hash_array,:data=>events,:fields=>['id','status']}
              #transfers=api_node.make_request_ex({:operation=>'GET',:subpath=>'ops/transfers',:args=>{'count'=>25,'filter'=>'id'}})
              #transfers=api_node.read("events") # after_time=2016-05-01T23:53:09Z
            when :set_client_key
              the_client_id=@optmgr.get_next_argument('client_id')
              the_private_key=@optmgr.get_next_argument('private_key')
              @api_files_admin.update("clients/#{the_client_id}",{:jwt_grant_enabled=>true, :public_key=>OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s})
              return Plugin.result_success
            when :resource
              resource_type=@optmgr.get_next_argument('resource',[:self,:user,:group,:client,:contact,:dropbox,:node,:operation,:package,:saml_configuration, :workspace, :dropbox_membership,:short_link])
              resource_class_path=resource_type.to_s+case resource_type;when :dropbox;'es';when :self;'';else; 's';end
              singleton_object=[:self].include?(resource_type)
              global_operations=[:create,:list]
              supported_operations=[:show]
              supported_operations.push(:modify,:delete,*global_operations) unless singleton_object
              supported_operations.push(:do) if resource_type.eql?(:node)
              supported_operations.push(:shared_folders) if resource_type.eql?(:workspace)
              command=@optmgr.get_next_argument('command',supported_operations)
              # require identifier for non global commands
              if !singleton_object and !global_operations.include?(command)
                res_id=@optmgr.get_option(:id)
                res_name=@optmgr.get_option(:name)
                if res_id.nil?
                  raise "Use either id or name" if res_name.nil?
                  matching=@api_files_admin.read(resource_class_path,{:q=>res_name})[:data]
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
                list_or_one=@optmgr.get_next_argument("creation data (Hash)")
                return do_bulk_operation(list_or_one,'created')do|params|
                  raise "expecting Hash" unless params.is_a?(Hash)
                  @api_files_admin.create(resource_class_path,params)[:data]
                end
              when :list
                default_fields=['id','name']
                case resource_type
                when :node; default_fields.push('host','access_key')
                when :operation; default_fields=nil
                when :contact; default_fields=["email","name","source_id","source_type"]
                end
                query=@optmgr.get_option(:query,:optional)
                Log.log.debug("Query=#{query}".bg_red)
                return {:type=>:hash_array,:data=>@api_files_admin.read(resource_class_path,query)[:data],:fields=>default_fields}
              when :show
                object=@api_files_admin.read(resource_instance_path)[:data]
                fields=object.keys.select{|k|!k.eql?('certificate')}
                return { :type=>:key_val_list, :data =>object, :fields=>fields }
              when :modify
                changes=@optmgr.get_next_argument('modified parameters (hash)')
                @api_files_admin.update(resource_instance_path,changes)
                return Plugin.result_status('modified')
              when :delete
                return do_bulk_operation(res_id,'deleted')do|one_id|
                  @api_files_admin.delete("#{resource_class_path}/#{one_id.to_s}")
                  {'id'=>one_id}
                end
              when :do
                res_data=@api_files_admin.read(resource_instance_path)[:data]
                api_node=get_files_node_api(res_data)
                ak_data=api_node.call({:operation=>'GET',:subpath=>"access_keys/#{res_data['access_key']}",:headers=>{'Accept'=>'application/json'}})[:data]
                return execute_node_action(res_id,ak_data['root_file_id'])
              when :shared_folders
                res_data=@api_files_admin.read("#{resource_class_path}/#{res_id}/permissions")[:data]
                return { :type=>:hash_array, :data =>res_data , :fields=>['id','node_name','file_id']} #
              else raise :ERROR
              end
            when :usage_reports
              return {:type=>:hash_array,:data=>@api_files_admin.read("usage_reports",{:workspace_id=>@workspace_id})[:data]}
            end
          end # action
          raise RuntimeError, "internal error"
        end
      end # Aspera
    end # Plugins
  end # Cli
end # Asperalm
