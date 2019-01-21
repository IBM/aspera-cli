require 'asperalm/cli/plugins/node'
require 'asperalm/cli/plugins/ats'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/cli/transfer_agent'
require 'asperalm/files_api'
require 'asperalm/persistency_file'
require 'securerandom'
require 'resolv'

module Asperalm
  module Cli
    module Plugins
      class Aspera < BasicAuthPlugin
        @@VAL_ALL='ALL'
        def initialize(env)
          super(env)
          @ats=Ats.new(@agents.merge(skip_secret: true))
          self.options.add_opt_list(:auth,Oauth.auth_types,"type of Oauth authentication")
          self.options.add_opt_list(:operation,[:push,:pull],"client operation for transfers")
          self.options.add_opt_simple(:client_id,"API client identifier in application")
          self.options.add_opt_simple(:client_secret,"API client passcode")
          self.options.add_opt_simple(:redirect_uri,"API client redirect URI")
          self.options.add_opt_simple(:private_key,"RSA private key PEM value for JWT (prefix file path with @val:@file:)")
          self.options.add_opt_simple(:workspace,"name of workspace")
          self.options.add_opt_simple(:secret,"access key secret for node")
          self.options.add_opt_simple(:eid,"identifier")
          self.options.add_opt_simple(:name,"resource name")
          self.options.add_opt_simple(:link,"link to shared resource")
          self.options.add_opt_simple(:public_token,"token value of public link")
          self.options.add_opt_simple(:new_user_option,"new user creation option")
          self.options.add_opt_simple(:from_folder,"share to share source folder")
          self.options.add_opt_simple(:scope,"scope for AoC API calls")
          self.options.add_opt_boolean(:bulk,"bulk operation")
          self.options.set_option(:bulk,:no)
          self.options.set_option(:redirect_uri,'http://localhost:12345')
          self.options.set_option(:auth,:web)
          self.options.set_option(:new_user_option,{'package_contact'=>true})
          self.options.set_option(:operation,:push)
          self.options.parse_options!
          @default_workspace_id=nil
          @workspace_name=nil
          @workspace_id=nil
          @user_id=nil
          @home_node_file=nil
          @ak_secret=self.options.get_option(:secret,:optional)
        end

        def transfer_start(api_files,app,direction,node_file,ts_add)
          # activity tracking
          ts_add.deep_merge!({'tags'=>{'aspera'=>{'files'=>{'workspace_name'=>@workspace_name}}}})
          return self.transfer.start(*api_files.tr_spec(app,direction,node_file,@workspace_id,ts_add))
        end

        def execute_node_gen4_action(top_node_file)
          command_repo=self.options.get_next_command([ :browse, :find, :mkdir, :rename, :delete, :upload, :download, :transfer, :http_node_download, :v3, :file  ])
          case command_repo
          when :browse
            thepath=self.options.get_next_argument('path')
            node_file = @api_files.resolve_node_file(top_node_file,thepath)
            node_api=@api_files.get_files_node_api(node_file[:node_info],FilesApi::SCOPE_NODE_USER)
            result=node_api.read("files/#{node_file[:file_id]}/files",self.options.get_option(:value,:optional))
            items=result[:data]
            self.format.display_status("Items: #{result[:data].length}/#{result[:http]['X-Total-Count']}")
            return {:type=>:object_list,:data=>items,:fields=>['name','type','recursive_size','size','modified_time','access_level']}
          when :find
            thepath=self.options.get_next_argument('path')
            regex=self.options.get_option(:value,:mandatory)
            node_file=@api_files.resolve_node_file(top_node_file,thepath)
            return {:type=>:value_list,:data=>@api_files.find_files(node_file,regex),:name=>'path'}
          when :mkdir
            thepath=self.options.get_next_argument('path')
            containing_folder_path = thepath.split(FilesApi::PATH_SEPARATOR)
            new_folder=containing_folder_path.pop
            node_file = @api_files.resolve_node_file(top_node_file,containing_folder_path.join(FilesApi::PATH_SEPARATOR))
            node_api=@api_files.get_files_node_api(node_file[:node_info],FilesApi::SCOPE_NODE_USER)
            result=node_api.create("files/#{node_file[:file_id]}/files",{:name=>new_folder,:type=>:folder})[:data]
            return Main.result_status("created: #{result['name']} (id=#{result['id']})")
          when :rename
            thepath=self.options.get_next_argument('source path')
            newname=self.options.get_next_argument('new name')
            node_file = @api_files.resolve_node_file(top_node_file,thepath)
            node_api=@api_files.get_files_node_api(node_file[:node_info],FilesApi::SCOPE_NODE_USER)
            result=node_api.update("files/#{node_file[:file_id]}",{:name=>newname})[:data]
            return Main.result_status("renamed #{thepath} to #{newname}")
          when :delete
            thepath=self.options.get_next_argument('path')
            node_file = @api_files.resolve_node_file(top_node_file,thepath)
            node_api=@api_files.get_files_node_api(node_file[:node_info],FilesApi::SCOPE_NODE_USER)
            result=node_api.delete("files/#{node_file[:file_id]}")[:data]
            return Main.result_status("deleted: #{thepath}")
          when :transfer
            server_home_node_file=client_home_node_file=top_node_file
            case self.options.get_option(:operation,:mandatory)
            when :push
              client_tr_oper='send'
              client_folder=self.options.get_option(:from_folder,:mandatory)
              server_folder=self.transfer.destination_folder(client_tr_oper)
            when :pull
              client_tr_oper='receive'
              client_folder=self.transfer.destination_folder(client_tr_oper)
              server_folder=self.options.get_option(:from_folder,:mandatory)
            end
            node_file_server = @api_files.resolve_node_file(server_home_node_file,server_folder)
            node_file_client = @api_files.resolve_node_file(client_home_node_file,client_folder)
            # force node as agent
            self.options.set_option(:transfer,:node)
            # force node api in node agent
            Fasp::Node.instance.node_api=@api_files.get_files_node_api(node_file_client[:node_info],FilesApi::SCOPE_NODE_USER)
            # additional node to node TS info
            add_ts={
              'remote_access_key'   => node_file_server[:node_info]['access_key'],
              #'destination_root_id' => node_file_server[:file_id],
              'source_root_id'      => node_file_client[:file_id]
            }
            return Main.result_transfer(transfer_start(@api_files,'files',client_tr_oper,node_file_server,add_ts))
          when :upload
            node_file = @api_files.resolve_node_file(top_node_file,self.transfer.destination_folder('send'))
            add_ts={'tags'=>{'aspera'=>{'files'=>{'parentCwd'=>"#{node_file[:node_info]['id']}:#{node_file[:file_id]}"}}}}
            return Main.result_transfer(transfer_start(@api_files,'files','send',node_file,add_ts))
          when :download
            source_paths=self.transfer.ts_source_paths
            # special case for AoC : all files must be in same folder
            source_folder=source_paths.shift['source']
            # if a single file: split into folder and path
            if source_paths.empty?
              source_folder=source_folder.split(FilesApi::PATH_SEPARATOR)
              source_paths=[{'source'=>source_folder.pop}]
              source_folder=source_folder.join(FilesApi::PATH_SEPARATOR)
            end
            node_file = @api_files.resolve_node_file(top_node_file,source_folder)
            # override paths with just filename
            add_ts={'tags'=>{'aspera'=>{'files'=>{'parentCwd'=>"#{node_file[:node_info]['id']}:#{node_file[:file_id]}"}}}}
            add_ts.merge!({'paths'=>source_paths})
            return Main.result_transfer(transfer_start(@api_files,'files','receive',node_file,add_ts))
          when :http_node_download
            source_paths=self.transfer.ts_source_paths
            source_folder=source_paths.shift['source']
            if source_paths.empty?
              source_folder=source_folder.split(FilesApi::PATH_SEPARATOR)
              source_paths=[{'source'=>source_folder.pop}]
              source_folder=source_folder.join(FilesApi::PATH_SEPARATOR)
            end
            raise CliBadArgument,'one file at a time only in HTTP mode' if source_paths.length > 1
            file_name = source_paths.first['source']
            node_file = @api_files.resolve_node_file(top_node_file,File.join(source_folder,file_name))
            node_api=@api_files.get_files_node_api(node_file[:node_info],FilesApi::SCOPE_NODE_USER)
            node_api.call({:operation=>'GET',:subpath=>"files/#{node_file[:file_id]}/content",:save_to_file=>File.join(self.transfer.destination_folder('receive'),file_name)})
            return Main.result_status("downloaded: #{file_name}")
          when :v3
            # Note: other "common" actions are unauthorized with user scope
            command_legacy=self.options.get_next_command(Node.simple_actions)
            # TODO: shall we support all methods here ? what if there is a link ?
            node_api=@api_files.get_files_node_api(top_node_file[:node_info],FilesApi::SCOPE_NODE_USER)
            return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: node_api)).execute_action(command_legacy)
          when :file
            fileid=self.options.get_next_argument('file id')
            node_file = @api_files.resolve_node_file(top_node_file)
            node_api=@api_files.get_files_node_api(node_file[:node_info],FilesApi::SCOPE_NODE_USER)
            items=node_api.read("files/#{fileid}")[:data]
            return {:type=>:single_object,:data=>items}
          end # command_repo
        end # execute_node_gen4_action

        attr_accessor :api_files

        # build REST object parameters based on command line options
        def get_aoc_api(is_admin)
          public_link_url=self.options.get_option(:link,:optional)

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
            self.options.set_option(:url,'https://'+uri.host)
            self.options.set_option(:public_token,url_token_value)
            self.options.set_option(:auth,:url_token)
            client_data=FilesApi.random_drive
            self.options.set_option(:client_id,client_data.first)
            self.options.set_option(:client_secret,client_data.last)
          end
          # Connection paramaters (url and auth) to Aspera on Cloud
          # pre populate rest parameters based on URL
          aoc_rest_params=FilesApi.base_rest_params(self.options.get_option(:url,:mandatory))
          aoc_rest_auth=aoc_rest_params[:auth]
          aoc_rest_auth.merge!({
            :grant         => self.options.get_option(:auth,:mandatory),
            :client_id     => self.options.get_option(:client_id,:mandatory),
            :client_secret => self.options.get_option(:client_secret,:mandatory)
          })

          # add jwt payload for global ids
          if FilesApi.is_global_client_id?(aoc_rest_auth[:client_id])
            org=aoc_rest_auth[:base_url].gsub(/.*\//,'')
            aoc_rest_auth.merge!({:jwt_add=>{org: org}})
          end

          # fill other auth parameters based on Oauth method
          case aoc_rest_auth[:grant]
          when :web
            aoc_rest_auth.merge!({
              :redirect_uri => self.options.get_option(:redirect_uri,:mandatory)
            })
          when :jwt
            private_key_PEM_string=self.options.get_option(:private_key,:mandatory)
            aoc_rest_auth.merge!({
              :jwt_subject         => self.options.get_option(:username,:mandatory),
              :jwt_private_key_obj => OpenSSL::PKey::RSA.new(private_key_PEM_string)
            })
          when :url_token
            aoc_rest_auth.merge!({
              :url_token     => self.options.get_option(:public_token,:mandatory),
            })
          else raise "ERROR: unsupported auth method"
          end
          aoc_rest_auth.merge!({
            :scope=>self.options.get_option(:scope,:optional) || is_admin ? FilesApi::SCOPE_FILES_ADMIN : FilesApi::SCOPE_FILES_USER
          })
          return FilesApi.new(aoc_rest_params)
        end

        # initialize apis and authentication
        # set:
        # @default_workspace_id
        # @workspace_name
        # @workspace_id
        # @user_id
        # @home_node_file  (hash with :node_info and :file_id)
        # returns nil
        def set_workspace_info
          if @api_files.params[:auth].has_key?(:url_token)
            url_token_data=@api_files.read("url_tokens")[:data].first
            @default_workspace_id=url_token_data['data']['workspace_id']
            @user_id='todo' # TODO : @api_files.read('organization')[:data] ?
            self.options.set_option(:id,url_token_data['data']['package_id'])
            home_node_id=url_token_data['data']['node_id']
            home_file_id=url_token_data['data']['file_id']
            url_token_data=nil # no more needed
          else
            # get our user's default information
            self_data=@api_files.read("self")[:data]
            @default_workspace_id=self_data['default_workspace_id']
            @user_id=self_data['id']
          end

          ws_name=self.options.get_option(:workspace,:optional)
          if ws_name.nil?
            Log.log.debug("using default workspace".green)
            if @default_workspace_id.eql?(nil)
              raise CliError,"no default workspace defined for user, please specify workspace"
            end
            # get default workspace
            @workspace_id=@default_workspace_id
          else
            # lookup another workspace
            wss=@api_files.read("workspaces",{'q'=>ws_name})[:data]
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
          @workspace_data=@api_files.read("workspaces/#{@workspace_id}")[:data]
          Log.log.debug("workspace_id=#{@workspace_id},@workspace_data=#{@workspace_data}".red)

          @workspace_name||=@workspace_data['name']
          Log.log.info("current workspace is "+@workspace_name.red)

          home_node_id||=@workspace_data['home_node_id']||@workspace_data['node_id']
          home_file_id||=@workspace_data['home_file_id']
          raise "node_id must be defined" if home_node_id.to_s.empty?
          @home_node_file={
            node_info: @api_files.read("nodes/#{home_node_id}")[:data],
            file_id: home_file_id
          }
          @api_files.check_get_node_file(@home_node_file)

          return nil
        end

        def do_bulk_operation(params,success,&do_action)
          params=[params] unless self.options.get_option(:bulk)
          raise "expecting Array" unless params.is_a?(Array)
          result=[]
          params.each do |p|
            one={'id'=>p}
            # todo: manage exception and display status by default
            res=do_action.call(p)
            one=res if p.is_a?(Hash)
            one['status']=success
            result.push(one)
          end
          return {:type=>:object_list,:data=>result,:fields=>['id','status']}
        end

        def resolve_package_recipients(package_creation,recipient_list_field)
          return unless package_creation.has_key?(recipient_list_field)
          raise CliBadArgument,"#{recipient_list_field} must be an Array" unless package_creation[recipient_list_field].is_a?(Array)
          new_user_option=self.options.get_option(:new_user_option,:mandatory)
          resolved_list=[]
          package_creation[recipient_list_field].each do |recipient_email|
            user_lookup=@api_files.read('contacts',{'current_workspace_id'=>@workspace_id,'q'=>recipient_email})[:data]
            case user_lookup.length
            when 1; recipient_user_id=user_lookup.first
            when 0; recipient_user_id=@api_files.create('contacts',{'current_workspace_id'=>@workspace_id,'email'=>recipient_email}.merge(new_user_option))[:data]
            else raise CliBadArgument,"multiple match for: #{recipient}"
            end
            resolved_list.push({'id'=>recipient_user_id['source_id'],'type'=>recipient_user_id['source_type']})
          end
          package_creation[recipient_list_field]=resolved_list
        end

        def package_tags(package_info,operation)
          return {'tags'=>{'aspera'=>{'files'=>{
            'package_id'        => package_info['id'],
            'package_name'      => package_info['name'],
            'package_operation' => operation
            }}}}
        end

        def url_query(default)
          query=self.options.get_option(:query,:optional)||default
          Log.log.debug("Query=#{query}".bg_red)
          begin
            # check it is suitable
            URI.encode_www_form(query) unless query.nil?
          rescue => e
            raise CliBadArgument,"query must be an extended value which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
          end
          return query
        end

        def action_list; [ :apiinfo, :bearer_token, :organization, :user, :workspace, :packages, :files, :faspexgw, :admin];end

        def execute_action
          command=self.options.get_next_command(action_list)
          # create objects for REST calls to Aspera
          # Note: bearer token is created on first use, or taken from cache
          @api_files=get_aoc_api(command.eql?(:admin))

          if [:workspace, :packages, :files, :faspexgw].include?(command)
            # populate workspace information for commands other than "admin"
            set_workspace_info
            # display workspace
            self.format.display_status("Current Workspace: #{@workspace_name.red}#{@workspace_id == @default_workspace_id ? ' (default)' : ''}")
          end

          case command
          when :apiinfo
            api_info={}
            num=1
            Resolv::DNS.open{|dns|dns.each_address('api.ibmaspera.com'){|a| api_info["api.#{num}"]=a;num+=1}}
            return {:type=>:single_object,:data=>api_info}
          when :bearer_token
            return {:type=>:text,:data=>@api_files.oauth_token}
          when :organization
            return { :type=>:single_object, :data =>@api_files.read('organization')[:data] }
          when :user
            command=self.options.get_next_command([ :workspaces,:info ])
            case command
            when :workspaces
              return {:type=>:object_list,:data=>@api_files.read("workspaces")[:data],:fields=>['id','name']}
              #              when :settings
              #                return {:type=>:object_list,:data=>@api_files.read("client_settings/")[:data]}
            when :info
              command=self.options.get_next_command([ :show,:modify ])
              my_user=@api_files.read('self')[:data]
              case command
              when :show
                return { :type=>:single_object, :data =>my_user }
              when :modify
                @api_files.update("users/#{my_user['id']}",self.options.get_next_argument('modified parameters (hash)'))
                return Main.result_status('modified')
              end
            end
          when :workspace # show current workspace parameters
            return { :type=>:single_object, :data =>@workspace_data }
          when :packages
            command_pkg=self.options.get_next_command([ :send, :recv, :list, :show, :delete ])
            case command_pkg
            when :send
              package_creation=self.options.get_option(:value,:mandatory)
              raise CliBadArgument,"value must be hash, refer to doc" unless package_creation.is_a?(Hash)
              package_creation['workspace_id']=@workspace_id

              # list of files to include in package
              package_creation['file_names']=self.transfer.ts_source_paths.map{|i|File.basename(i['source'])}

              # lookup users
              resolve_package_recipients(package_creation,'recipients')
              resolve_package_recipients(package_creation,'bcc_recipients')

              #  create a new package with one file
              package_info=@api_files.create('packages',package_creation)[:data]

              #  get node information for the node on which package must be created
              node_info=@api_files.read("nodes/#{package_info['node_id']}")[:data]

              # tell Aspera what to expect in package: 1 transfer (can also be done after transfer)
              resp=@api_files.update("packages/#{package_info['id']}",{'sent'=>true,'transfers_expected'=>1})[:data]

              # execute transfer
              node_file = {node_info: node_info, file_id: package_info['contents_file_id']}
              return Main.result_transfer(transfer_start(@api_files,'packages','send',node_file,package_tags(package_info,'upload')))
            when :recv
              # scalar here
              ids_to_download=self.options.get_option(:id,:mandatory)
              # non nil if persistence
              skip_ids_persistency=PersistencyFile.new('aoc_recv',{
                :url      => self.options.get_option(:url,:mandatory),
                :ids      => [@user_id,@workspace_name],
                :active   => self.options.get_option(:once_only,:mandatory),
                :default  => [],
                :delete   => lambda{|d|d.nil? or d.empty?}})
              if ids_to_download.eql?(@@VAL_ALL)
                # get list of packages in inbox
                package_info=@api_files.read('packages',{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>@workspace_id})[:data]
                # remove from list the ones already downloaded
                ids_to_download=package_info.map{|e|e['id']}
                # array here
                ids_to_download.select!{|id|!skip_ids_persistency.data.include?(id)}
              end # ALL
              # list here
              ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
              result_transfer=[]
              self.format.display_status("found #{ids_to_download.length} package(s).")
              ids_to_download.each do |package_id|
                package_info=@api_files.read("packages/#{package_id}")[:data]
                node_info=@api_files.read("nodes/#{package_info['node_id']}")[:data]
                self.format.display_status("downloading package: #{package_info['name']}")
                add_ts={'paths'=>[{'source'=>'.'}]}
                node_file = {node_info: node_info, file_id: package_info['contents_file_id']}
                statuses=transfer_start(@api_files,'packages','receive',node_file,package_tags(package_info,'download').merge(add_ts))
                result_transfer.push({'package'=>package_id,'status'=>statuses.map{|i|i.to_s}.join(',')})
                # update skip list only if all sessions completed
                skip_ids_persistency.data.push(package_id) if TransferAgent.session_status(statuses).eql?(:success)
              end
              skip_ids_persistency.save
              return {:type=>:object_list,:data=>result_transfer}
            when :show
              package_id=self.options.get_next_argument('package ID')
              package_info=@api_files.read("packages/#{package_id}")[:data]
              return { :type=>:single_object, :data =>package_info }
            when :list
              # list all packages ('page'=>1,'per_page'=>10,)'sort'=>'-sent_at',
              packages=@api_files.read("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>@workspace_id})[:data]
              return {:type=>:object_list,:data=>packages,:fields=>['id','name','bytes_transferred']}
            when :delete
              list_or_one=self.options.get_option(:id,:mandatory)
              return do_bulk_operation(list_or_one,'deleted')do|id|
                raise "expecting String identifier" unless id.is_a?(String) or id.is_a?(Integer)
                @api_files.delete("packages/#{id}")[:data]
              end
            end
          when :files
            @api_files.secrets[@home_node_file[:node_info]['id']]=@ak_secret
            return execute_node_gen4_action(@home_node_file)
          when :faspexgw
            require 'asperalm/faspex_gw'
            FaspexGW.instance.start_server(@api_files,@workspace_id)
          when :admin
            command_admin=self.options.get_next_command([ :ats, :resource, :set_client_key, :usage_reports, :search_nodes, :events ])
            case command_admin
            when :ats
              ats_api = Rest.new(@api_files.params.deep_merge({
                :base_url => @api_files.params[:base_url]+'/admin/ats/pub/v1',
                :auth     => {:scope => FilesApi::SCOPE_FILES_ADMIN_USER}
              }))
              return @ats.execute_action_gen(ats_api)
            when :search_nodes
              ak=self.options.get_next_argument('access_key')
              nodes=@api_files.read("search_nodes",{'q'=>'access_key:"'+ak+'"'})[:data]
              return {:type=>:other_struct,:data=>nodes}
            when :events
              events=@api_files.read("admin/events",url_query({q: '*'}))[:data]
              events.map!{|i|i['_source']['_score']=i['_score'];i['_source']}
              return {:type=>:object_list,:data=>events,:fields=>['user.name','type','data.files_transfer_action','data.workspace_name','date']}
            when :set_client_key
              the_client_id=self.options.get_next_argument('client_id')
              the_private_key=self.options.get_next_argument('private_key')
              @api_files.update("clients/#{the_client_id}",{:jwt_grant_enabled=>true, :public_key=>OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s})
              return Main.result_success
            when :resource
              resource_type=self.options.get_next_argument('resource',[:self,:user,:group,:client,:contact,:dropbox,:node,:operation,:package,:saml_configuration, :workspace, :dropbox_membership,:short_link,:workspace_membership])
              resource_class_path=resource_type.to_s+case resource_type;when :dropbox;'es';when :self;'';else; 's';end
              singleton_object=[:self].include?(resource_type)
              global_operations=[:create,:list]
              supported_operations=[:show]
              supported_operations.push(:modify,:delete,*global_operations) unless singleton_object
              supported_operations.push(:v4,:v3,:info) if resource_type.eql?(:node)
              supported_operations.push(:shared_folders) if resource_type.eql?(:workspace)
              command=self.options.get_next_command(supported_operations)
              # require identifier for non global commands
              if !singleton_object and !global_operations.include?(command)
                res_id=self.options.get_option(:id)
                res_name=self.options.get_option(:name)
                if res_id.nil? and res_name.nil? and resource_type.eql?(:node)
                  set_workspace_info
                  res_id=@home_node_file[:node_info]['id']
                end
                if !res_name.nil?
                  Log.log.warn("name overrides id") unless res_id.nil?
                  matching=@api_files.read(resource_class_path,{:q=>res_name})[:data]
                  raise CliError,"no resource match name" if matching.empty?
                  raise CliError,"several resources match name" unless matching.length.eql?(1)
                  res_id=matching.first['id']
                end
                raise CliBadArgument,"provide either id or name" if res_id.nil?
                resource_instance_path="#{resource_class_path}/#{res_id}"
              end
              resource_instance_path=resource_class_path if singleton_object
              case command
              when :create
                list_or_one=self.options.get_next_argument("creation data (Hash)")
                return do_bulk_operation(list_or_one,'created')do|params|
                  raise "expecting Hash" unless params.is_a?(Hash)
                  @api_files.create(resource_class_path,params)[:data]
                end
              when :list
                default_fields=['id','name']
                case resource_type
                when :node; default_fields.push('host','access_key')
                when :operation; default_fields=nil
                when :contact; default_fields=["email","name","source_id","source_type"]
                end
                return {:type=>:object_list,:data=>@api_files.read(resource_class_path,url_query(nil))[:data],:fields=>default_fields}
              when :show
                object=@api_files.read(resource_instance_path)[:data]
                fields=object.keys.select{|k|!k.eql?('certificate')}
                return { :type=>:single_object, :data =>object, :fields=>fields }
              when :modify
                changes=self.options.get_next_argument('modified parameters (hash)')
                @api_files.update(resource_instance_path,changes)
                return Main.result_status('modified')
              when :delete
                return do_bulk_operation(res_id,'deleted')do|one_id|
                  @api_files.delete("#{resource_class_path}/#{one_id.to_s}")
                  {'id'=>one_id}
                end
              when :v3,:v4
                res_data=@api_files.read(resource_instance_path)[:data]
                # mandatory secret : we have only AK
                self.options.get_option(:secret,:mandatory)
                @api_files.secrets[res_data['id']]=@ak_secret unless @ak_secret.nil?
                api_node=@api_files.get_files_node_api(res_data,nil)
                return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node)).execute_action if command.eql?(:v3)
                ak_data=api_node.call({:operation=>'GET',:subpath=>"access_keys/#{res_data['access_key']}",:headers=>{'Accept'=>'application/json'}})[:data]
                return execute_node_gen4_action({node_info: res_data, file_id: ak_data['root_file_id']})
              when :info
                object=@api_files.read(resource_instance_path)[:data]
                access_key=object['access_key']
                match_list=@api_files.read('admin/search_nodes',{:q=>"access_key:\"#{access_key}\""})[:data]
                result=match_list.select{|i|i["_source"]["access_key_recursive_counts"].first["access_key"].eql?(access_key)}
                return Main.result_status('Private node') if result.empty?
                raise CliError,"more than one match" unless result.length.eql?(1)
                result=result.first["_source"]
                result.merge!(result['access_key_recursive_counts'].first)
                result.delete('access_key_recursive_counts')
                result.delete('token')
                return { :type=>:single_object, :data =>result}
              when :shared_folders
                res_data=@api_files.read("#{resource_class_path}/#{res_id}/permissions")[:data]
                return { :type=>:object_list, :data =>res_data , :fields=>['id','node_name','file_id']} #
              else raise :ERROR
              end
            when :usage_reports
              return {:type=>:object_list,:data=>@api_files.read("usage_reports",{:workspace_id=>@workspace_id})[:data]}
            end
          end # action
          raise RuntimeError, "internal error"
        end
      end # Aspera
    end # Plugins
  end # Cli
end # Asperalm
