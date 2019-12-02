require 'asperalm/cli/plugins/node'
require 'asperalm/cli/plugins/ats'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/cli/transfer_agent'
require 'asperalm/on_cloud'
require 'asperalm/persistency_file'
require 'securerandom'
require 'resolv'
require 'date'

module Asperalm
  module Cli
    module Plugins
      class Aspera < BasicAuthPlugin
        VAL_ALL='ALL'
        MAX_REDIRECT=10
        private_constant :VAL_ALL,:MAX_REDIRECT
        attr_reader :api_aoc
        attr_accessor :option_ak_secret
        def initialize(env)
          super(env)
          @default_workspace_id=nil
          @workspace_name=nil
          @workspace_id=nil
          @persist_ids=nil
          @home_node_file=nil
          @api_aoc=nil
          @option_ak_secret=nil
          @url_token_data=nil
          @user_info=nil
          @ats=Ats.new(@agents.merge(skip_secret: true))
          self.options.set_obj_attr(:secret,self,:option_ak_secret)
          self.options.add_opt_list(:auth,Oauth.auth_types,"type of Oauth authentication")
          self.options.add_opt_list(:operation,[:push,:pull],"client operation for transfers")
          self.options.add_opt_simple(:client_id,"API client identifier in application")
          self.options.add_opt_simple(:client_secret,"API client passcode")
          self.options.add_opt_simple(:redirect_uri,"API client redirect URI")
          self.options.add_opt_simple(:private_key,"RSA private key PEM value for JWT (prefix file path with @val:@file:)")
          self.options.add_opt_simple(:workspace,"name of workspace")
          self.options.add_opt_simple(:secret,"access key secret for node")
          self.options.add_opt_simple(:eid,"identifier") # used ?
          self.options.add_opt_simple(:name,"resource name")
          self.options.add_opt_simple(:link,"public link to shared resource")
          self.options.add_opt_simple(:public_token,"token value of public link")
          self.options.add_opt_simple(:new_user_option,"new user creation option")
          self.options.add_opt_simple(:from_folder,"share to share source folder")
          self.options.add_opt_simple(:scope,"scope for AoC API calls")
          self.options.add_opt_boolean(:bulk,"bulk operation")
          self.options.set_option(:bulk,:no)
          self.options.set_option(:new_user_option,{'package_contact'=>true})
          self.options.set_option(:operation,:push)
          client_data=OnCloud.random_cli
          self.options.set_option(:auth,:jwt)
          self.options.set_option(:client_id,client_data.first)
          self.options.set_option(:client_secret,client_data.last)
          self.options.set_option(:scope,OnCloud::SCOPE_FILES_USER)
          self.options.set_option(:private_key,'@file:'+env[:private_key_path]) if env[:private_key_path].is_a?(String)
          self.options.parse_options!
          return if env[:man_only]
          update_aoc_api
        end

        def user_info
          if @user_info.nil?
            # get our user's default information
            # self?embed[]=default_workspace&embed[]=organization
            @user_info=@api_aoc.read('self')[:data] rescue {
            'name'  => 'unknown',
            'email' => 'unknown',
            }
          end
          return @user_info
        end

        # starts transfer using transfer agent
        def transfer_start(app,direction,node_file,ts_add)
          ts_add.deep_merge!(OnCloud.analytics_ts(app,direction,@workspace_id,@workspace_name))
          ts_add.deep_merge!(OnCloud.console_ts(app,user_info['name'],user_info['email']))
          return self.transfer.start(*@api_aoc.tr_spec(app,direction,node_file,ts_add))
        end

        NODE4_COMMANDS=[ :browse, :find, :mkdir, :rename, :delete, :upload, :download, :transfer, :http_node_download, :v3, :file, :bearer_token_node  ]

        def node_gen4_execute_action(top_node_file)
          command_repo=self.options.get_next_command(NODE4_COMMANDS)
          return execute_node_gen4_command(command_repo,top_node_file)
        end

        def execute_node_gen4_command(command_repo,top_node_file)
          case command_repo
          when :bearer_token_node
            thepath=self.options.get_next_argument('path')
            node_file = @api_aoc.resolve_node_file(top_node_file,thepath)
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            return Main.result_status(node_api.oauth_token)
          when :browse
            thepath=self.options.get_next_argument('path')
            node_file = @api_aoc.resolve_node_file(top_node_file,thepath)
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            file_info = node_api.read("files/#{node_file[:file_id]}")[:data]
            if file_info['type'].eql?('folder')
              result=node_api.read("files/#{node_file[:file_id]}/files",self.options.get_option(:value,:optional))
              items=result[:data]
              self.format.display_status("Items: #{result[:data].length}/#{result[:http]['X-Total-Count']}")
            else
              items=[file_info]
            end
            return {:type=>:object_list,:data=>items,:fields=>['name','type','recursive_size','size','modified_time','access_level']}
          when :find
            thepath=self.options.get_next_argument('path')
            exec_prefix='exec:'
            expression=self.options.get_option(:value,:optional)||"#{exec_prefix}true"
            node_file=@api_aoc.resolve_node_file(top_node_file,thepath)
            if expression.start_with?(exec_prefix)
              test_block=eval "lambda{|f|#{expression[exec_prefix.length..-1]}}"
            else
              test_block=lambda{|f|f['name'].match(/#{expression}/)}
            end
            return {:type=>:object_list,:data=>@api_aoc.find_files(node_file,test_block),:fields=>['path']}
          when :mkdir
            thepath=self.options.get_next_argument('path')
            containing_folder_path = thepath.split(OnCloud::PATH_SEPARATOR)
            new_folder=containing_folder_path.pop
            node_file = @api_aoc.resolve_node_file(top_node_file,containing_folder_path.join(OnCloud::PATH_SEPARATOR))
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            result=node_api.create("files/#{node_file[:file_id]}/files",{:name=>new_folder,:type=>:folder})[:data]
            return Main.result_status("created: #{result['name']} (id=#{result['id']})")
          when :rename
            thepath=self.options.get_next_argument('source path')
            newname=self.options.get_next_argument('new name')
            node_file = @api_aoc.resolve_node_file(top_node_file,thepath)
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            result=node_api.update("files/#{node_file[:file_id]}",{:name=>newname})[:data]
            return Main.result_status("renamed #{thepath} to #{newname}")
          when :delete
            thepath=self.options.get_next_argument('path')
            node_file = @api_aoc.resolve_node_file(top_node_file,thepath)
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            result=node_api.delete("files/#{node_file[:file_id]}")[:data]
            return Main.result_status("deleted: #{thepath}")
          when :transfer
            # in same workspace
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
            node_file_client = @api_aoc.resolve_node_file(client_home_node_file,client_folder)
            node_file_server = @api_aoc.resolve_node_file(server_home_node_file,server_folder)
            # force node as agent
            self.options.set_option(:transfer,:node)
            # force node api in node agent
            Fasp::Node.instance.node_api=@api_aoc.get_node_api(node_file_client[:node_info],OnCloud::SCOPE_NODE_USER)
            # additional node to node TS info
            add_ts={
              'remote_access_key'   => node_file_server[:node_info]['access_key'],
              'destination_root_id' => node_file_server[:file_id],
              'source_root_id'      => node_file_client[:file_id]
            }
            return Main.result_transfer(transfer_start(OnCloud::FILES,client_tr_oper,node_file_server,add_ts))
            #bad: return Main.result_transfer(transfer_start(OnCloud::FILES,client_tr_oper,node_file_client,add_ts))
          when :upload
            node_file = @api_aoc.resolve_node_file(top_node_file,self.transfer.destination_folder('send'))
            add_ts={'tags'=>{'aspera'=>{'files'=>{'parentCwd'=>"#{node_file[:node_info]['id']}:#{node_file[:file_id]}"}}}}
            return Main.result_transfer(transfer_start(OnCloud::FILES,'send',node_file,add_ts))
          when :download
            source_paths=self.transfer.ts_source_paths
            # special case for AoC : all files must be in same folder
            source_folder=source_paths.shift['source']
            # if a single file: split into folder and path
            if source_paths.empty?
              source_folder=source_folder.split(OnCloud::PATH_SEPARATOR)
              source_paths=[{'source'=>source_folder.pop}]
              source_folder=source_folder.join(OnCloud::PATH_SEPARATOR)
            end
            node_file = @api_aoc.resolve_node_file(top_node_file,source_folder)
            # override paths with just filename
            add_ts={'tags'=>{'aspera'=>{'files'=>{'parentCwd'=>"#{node_file[:node_info]['id']}:#{node_file[:file_id]}"}}}}
            add_ts.merge!({'paths'=>source_paths})
            return Main.result_transfer(transfer_start(OnCloud::FILES,'receive',node_file,add_ts))
          when :http_node_download
            source_paths=self.transfer.ts_source_paths
            source_folder=source_paths.shift['source']
            if source_paths.empty?
              source_folder=source_folder.split(OnCloud::PATH_SEPARATOR)
              source_paths=[{'source'=>source_folder.pop}]
              source_folder=source_folder.join(OnCloud::PATH_SEPARATOR)
            end
            raise CliBadArgument,'one file at a time only in HTTP mode' if source_paths.length > 1
            file_name = source_paths.first['source']
            node_file = @api_aoc.resolve_node_file(top_node_file,File.join(source_folder,file_name))
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            node_api.call({:operation=>'GET',:subpath=>"files/#{node_file[:file_id]}/content",:save_to_file=>File.join(self.transfer.destination_folder('receive'),file_name)})
            return Main.result_status("downloaded: #{file_name}")
          when :v3
            # Note: other "common" actions are unauthorized with user scope
            command_legacy=self.options.get_next_command(Node::SIMPLE_ACTIONS)
            # TODO: shall we support all methods here ? what if there is a link ?
            node_api=@api_aoc.get_node_api(top_node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: node_api)).execute_action(command_legacy)
          when :file
            fileid=self.options.get_next_argument('file id')
            node_file = @api_aoc.resolve_node_file(top_node_file)
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            items=node_api.read("files/#{fileid}")[:data]
            return {:type=>:single_object,:data=>items}
          end # command_repo
          throw "ERR"
        end # execute_node_gen4_command

        # check option "link"
        # if present try to get token value (resolve redirection if short links used)
        # then set options url/token/auth
        def pub_link_to_url_auth_token
          public_link_url=self.options.get_option(:link,:optional)
          return if public_link_url.nil?
          # set to token if available after redirection
          url_token_value=nil
          redirect_count=0
          loop do
            uri=URI.parse(public_link_url)
            if OnCloud::PATHS_PUBLIC_LINK.include?(uri.path)
              url_token_value=URI::decode_www_form(uri.query).select{|e|e.first.eql?('token')}.first
              if url_token_value.nil?
                raise CliBadArgument,"link option must be URL with 'token' parameter"
              end
              # ok we get it !
              self.options.set_option(:url,'https://'+uri.host)
              self.options.set_option(:public_token,url_token_value)
              self.options.set_option(:auth,:url_token)
              return
            end
            Log.log.debug("no expected format: #{public_link_url}")
            raise "exceeded max redirection: #{MAX_REDIRECT}" if redirect_count > MAX_REDIRECT
            r = Net::HTTP.get_response(uri)
            if r.code.start_with?("3")
              public_link_url = r['location']
              raise "no location in redirection" if public_link_url.nil?
              Log.log.debug("redirect to: #{public_link_url}")
            else
              # not a redirection
              raise CliBadArgument,'not redirection, so link not supported'
            end
          end # loop

          raise CliBadArgument,'too many redirections'
        end

        # Create a new AoC API REST object and set @api_aoc.
        # Parameters based on command line options
        # @return nil
        def update_aoc_api

          # if auth is a public link
          # option "link" is a shortcut for options: url, auth, public_token
          pub_link_to_url_auth_token

          # Connection paramaters (url and auth) to Aspera on Cloud
          # pre populate rest parameters based on URL
          aoc_rest_params=OnCloud.base_rest_params(self.options.get_option(:url,:mandatory))
          aoc_rest_auth=aoc_rest_params[:auth]
          aoc_rest_auth.merge!({
            :grant         => self.options.get_option(:auth,:mandatory),
            :client_id     => self.options.get_option(:client_id,:mandatory),
            :client_secret => self.options.get_option(:client_secret,:mandatory),
            :scope         => self.options.get_option(:scope,:optional)
          })

          # add jwt payload for global ids
          if OnCloud.is_global_client_id?(aoc_rest_auth[:client_id])
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
          @api_aoc=OnCloud.new(aoc_rest_params)
          return nil
        end

        # initialize apis and authentication
        # set:
        # @default_workspace_id
        # @workspace_name
        # @workspace_id
        # @persist_ids
        # returns nil
        def set_workspace_info
          if @api_aoc.params[:auth].has_key?(:url_token)
            # TODO: can there be several in list ?
            @url_token_data=@api_aoc.read('url_tokens')[:data].first
            @default_workspace_id=@url_token_data['data']['workspace_id']
            @persist_ids=[] # TODO : @url_token_data['id'] ?
          else
            @default_workspace_id=user_info['default_workspace_id']
            @persist_ids=[user_info['id']]
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
            wss=@api_aoc.read("workspaces",{'q'=>ws_name})[:data]
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
          @workspace_data=@api_aoc.read("workspaces/#{@workspace_id}")[:data]
          Log.log.debug("workspace_id=#{@workspace_id},@workspace_data=#{@workspace_data}".red)

          @workspace_name||=@workspace_data['name']
          Log.log.info("current workspace is "+@workspace_name.red)

          # display workspace
          self.format.display_status("Current Workspace: #{@workspace_name.red}#{@workspace_id == @default_workspace_id ? ' (default)' : ''}")
          return nil
        end

        # @home_node_file  (hash with :node_info and :file_id)
        def set_home_node_file
          if !@url_token_data.nil?
            assert_public_link_types(['view_shared_file'])
            home_node_id=@url_token_data['data']['node_id']
            home_file_id=@url_token_data['data']['file_id']
          end
          home_node_id||=@workspace_data['home_node_id']||@workspace_data['node_id']
          home_file_id||=@workspace_data['home_file_id']
          raise "node_id must be defined" if home_node_id.to_s.empty?
          @home_node_file={
            node_info: @api_aoc.read("nodes/#{home_node_id}")[:data],
            file_id: home_file_id
          }
          @api_aoc.check_get_node_file(@home_node_file)

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

        # package creation params can give just email, and full hash is created
        def resolve_package_recipients(package_creation,recipient_list_field)
          return unless package_creation.has_key?(recipient_list_field)
          raise CliBadArgument,"#{recipient_list_field} must be an Array" unless package_creation[recipient_list_field].is_a?(Array)
          new_user_option=self.options.get_option(:new_user_option,:mandatory)
          resolved_list=[]
          package_creation[recipient_list_field].each do |recipient_email|
            if recipient_email.is_a?(Hash) and recipient_email.has_key?('id') and recipient_email.has_key?('type')
              # already provided all information ?
              resolved_list.push(recipient_email)
            else
              # or need to resolve email
              user_lookup=@api_aoc.read('contacts',{'current_workspace_id'=>@workspace_id,'q'=>recipient_email})[:data]
              case user_lookup.length
              when 1; recipient_user_id=user_lookup.first
              when 0; recipient_user_id=@api_aoc.create('contacts',{'current_workspace_id'=>@workspace_id,'email'=>recipient_email}.merge(new_user_option))[:data]
              else raise CliBadArgument,"multiple match for: #{recipient}"
              end
              resolved_list.push({'id'=>recipient_user_id['source_id'],'type'=>recipient_user_id['source_type']})
            end
          end
          package_creation[recipient_list_field]=resolved_list
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

        def assert_public_link_types(expected)
          if !expected.include?(@url_token_data['purpose'])
            raise CliBadArgument,"public link type is #{@url_token_data['purpose']} but action requires one of #{expected.join(',')}"
          end
        end

        ACTIONS=[ :apiinfo, :bearer_token, :organization, :tier_restrictions, :user, :workspace, :packages, :files, :faspexgw, :admin, :automation]

        def execute_action
          command=self.options.get_next_command(ACTIONS)
          case command
          when :apiinfo
            api_info={}
            num=1
            Resolv::DNS.open{|dns|dns.each_address('api.ibmaspera.com'){|a| api_info["api.#{num}"]=a;num+=1}}
            return {:type=>:single_object,:data=>api_info}
          when :bearer_token
            return {:type=>:text,:data=>@api_aoc.oauth_token}
          when :organization
            return { :type=>:single_object, :data =>@api_aoc.read('organization')[:data] }
          when :tier_restrictions
            return { :type=>:single_object, :data =>@api_aoc.read('tier_restrictions')[:data] }
          when :user
            command=self.options.get_next_command([ :workspaces,:info ])
            case command
            when :workspaces
              return {:type=>:object_list,:data=>@api_aoc.read("workspaces")[:data],:fields=>['id','name']}
              #              when :settings
              #                return {:type=>:object_list,:data=>@api_aoc.read("client_settings/")[:data]}
            when :info
              command=self.options.get_next_command([ :show,:modify ])
              case command
              when :show
                return { :type=>:single_object, :data =>user_info }
              when :modify
                @api_aoc.update("users/#{user_info['id']}",self.options.get_next_argument('modified parameters (hash)'))
                return Main.result_status('modified')
              end
            end
          when :workspace # show current workspace parameters
            set_workspace_info
            return { :type=>:single_object, :data =>@workspace_data }
          when :packages
            set_workspace_info if @url_token_data.nil?
            command_pkg=self.options.get_next_command([ :send, :recv, :list, :show, :delete ])
            case command_pkg
            when :send
              package_creation=self.options.get_option(:value,:mandatory)
              raise CliBadArgument,"value must be hash, refer to doc" unless package_creation.is_a?(Hash)

              if !@url_token_data.nil?
                assert_public_link_types(['send_package_to_user','send_package_to_dropbox'])
                box_type=@url_token_data['purpose'].split('_').last
                package_creation['recipients']=[{'id'=>@url_token_data['data']["#{box_type}_id"],'type'=>box_type}]
                @workspace_id=@url_token_data['data']['workspace_id']
              end

              package_creation['workspace_id']=@workspace_id

              # list of files to include in package
              package_creation['file_names']=self.transfer.ts_source_paths.map{|i|File.basename(i['source'])}

              # lookup users
              resolve_package_recipients(package_creation,'recipients')
              resolve_package_recipients(package_creation,'bcc_recipients')

              #  create a new package with one file
              package_info=@api_aoc.create('packages',package_creation)[:data]

              #  get node information for the node on which package must be created
              node_info=@api_aoc.read("nodes/#{package_info['node_id']}")[:data]

              # tell Aspera what to expect in package: 1 transfer (can also be done after transfer)
              @api_aoc.update("packages/#{package_info['id']}",{'sent'=>true,'transfers_expected'=>1})[:data]

              # execute transfer
              node_file = {node_info: node_info, file_id: package_info['contents_file_id']}
              return Main.result_transfer(transfer_start(OnCloud::PACKAGES,'send',node_file,OnCloud.package_tags(package_info,'upload')))
            when :recv
              if !@url_token_data.nil?
                assert_public_link_types(['view_received_package'])
                self.options.set_option(:id,@url_token_data['data']['package_id'])
              end
              # scalar here
              ids_to_download=self.options.get_option(:id,:mandatory)
              skip_ids_data=[]
              skip_ids_persistency=nil
              if self.options.get_option(:once_only,:mandatory)
                skip_ids_persistency=PersistencyFile.new(
                data: skip_ids_data,
                ids:  ['aoc_recv',self.options.get_option(:url,:mandatory),@workspace_name].push(*@persist_ids))
              end
              if ids_to_download.eql?(VAL_ALL)
                # get list of packages in inbox
                package_info=@api_aoc.read('packages',{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>@workspace_id})[:data]
                # remove from list the ones already downloaded
                ids_to_download=package_info.map{|e|e['id']}
                # array here
                ids_to_download.select!{|id|!skip_ids_data.include?(id)}
              end # ALL
              # list here
              ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
              result_transfer=[]
              self.format.display_status("found #{ids_to_download.length} package(s).")
              ids_to_download.each do |package_id|
                package_info=@api_aoc.read("packages/#{package_id}")[:data]
                node_info=@api_aoc.read("nodes/#{package_info['node_id']}")[:data]
                self.format.display_status("downloading package: #{package_info['name']}")
                add_ts={'paths'=>[{'source'=>'.'}]}
                node_file = {node_info: node_info, file_id: package_info['contents_file_id']}
                statuses=transfer_start(OnCloud::PACKAGES,'receive',node_file,OnCloud.package_tags(package_info,'download').merge(add_ts))
                result_transfer.push({'package'=>package_id,'status'=>statuses.map{|i|i.to_s}.join(',')})
                # update skip list only if all transfer sessions completed
                if TransferAgent.session_status(statuses).eql?(:success)
                  skip_ids_data.push(package_id)
                  skip_ids_persistency.save unless skip_ids_persistency.nil?
                end
              end
              return {:type=>:object_list,:data=>result_transfer}
            when :show
              package_id=self.options.get_next_argument('package ID')
              package_info=@api_aoc.read("packages/#{package_id}")[:data]
              return { :type=>:single_object, :data =>package_info }
            when :list
              # list all packages ('page'=>1,'per_page'=>10,)'sort'=>'-sent_at',
              packages=@api_aoc.read("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>@workspace_id})[:data]
              return {:type=>:object_list,:data=>packages,:fields=>['id','name','bytes_transferred']}
            when :delete
              list_or_one=self.options.get_option(:id,:mandatory)
              return do_bulk_operation(list_or_one,'deleted')do|id|
                raise "expecting String identifier" unless id.is_a?(String) or id.is_a?(Integer)
                @api_aoc.delete("packages/#{id}")[:data]
              end
            end
          when :files
            # get workspace related information
            set_workspace_info
            set_home_node_file
            # set node secret in case it was provided
            @api_aoc.secrets[@home_node_file[:node_info]['id']]=@option_ak_secret
            command_repo=self.options.get_next_command(NODE4_COMMANDS.clone.concat([:short_link]))
            case command_repo
            when *NODE4_COMMANDS; return execute_node_gen4_command(command_repo,@home_node_file)
            when :short_link
              return self.entity_action(@api_aoc,'short_links',nil,:id,'self')
            end
            throw "Error"
          when :automation
            # automation api is not in the same place
            automation_rest_params=@api_aoc.params.clone
            automation_rest_params[:base_url].gsub!('/api/','/automation/')
            automation_api=Rest.new(automation_rest_params)
            command_automation=self.options.get_next_command([ :workflows, :instances ])
            case command_automation
            when :instances
              return self.entity_action(@api_aoc,'workflow_instances',nil,:id,nil)
            when :workflows
              wF_COMMANDS=Plugin::ALL_OPS.clone.push(:action,:launch)
              wf_command=self.options.get_next_command(wF_COMMANDS)
              case wf_command
              when *Plugin::ALL_OPS
                return self.entity_command(wf_command,automation_api,'workflows',nil,:id)
              when :launch
                wf_id=self.options.get_option(:id,:mandatory)
                data=automation_api.create("workflows/#{wf_id}/launch",{})[:data]
              when :action
                wf_command=self.options.get_next_command([:list,:create,:show])
                wf_id=self.options.get_option(:id,:mandatory)
                step=automation_api.create('steps',{'workflow_id'=>wf_id})[:data]
                automation_api.update("workflows/#{wf_id}",{'step_order'=>[step["id"]]})
                action=automation_api.create('actions',{'step_id'=>step["id"],'type'=>'manual'})[:data]
                automation_api.update("steps/#{step["id"]}",{'action_order'=>[action["id"]]})
                wf=automation_api.read("workflows/#{wf_id}")[:data]
                return {:type=>:single_object,:data=>wf}
              end
            end
          when :faspexgw
            set_workspace_info
            require 'asperalm/faspex_gw'
            FaspexGW.instance.start_server(@api_aoc,@workspace_id)
          when :admin
            self.options.set_option(:scope,OnCloud::SCOPE_FILES_ADMIN)
            update_aoc_api
            command_admin=self.options.get_next_command([ :ats, :resource, :usage_reports, :search_nodes, :events ])
            case command_admin
            when :ats
              ats_api = Rest.new(@api_aoc.params.deep_merge({
                :base_url => @api_aoc.params[:base_url]+'/admin/ats/pub/v1',
                :auth     => {:scope => OnCloud::SCOPE_FILES_ADMIN_USER}
              }))
              return @ats.execute_action_gen(ats_api)
            when :search_nodes
              query=self.options.get_option(:query,:optional) || '*'
              nodes=@api_aoc.read("search_nodes",{'q'=>query})[:data]
              # simplify output
              nodes=nodes.map do |i|
                item=i['_source']
                item['score']=i['_score']
                nodedata=item['access_key_recursive_counts'].first
                item.delete('access_key_recursive_counts')
                item['node']=nodedata
                item
              end
              return {:type=>:object_list,:data=>nodes,:fields=>['host_name','node_status.cluster_id','node_status.node_id']}
            when :events
              events=@api_aoc.read("admin/events",url_query({q: '*'}))[:data]
              events.map!{|i|i['_source']['_score']=i['_score'];i['_source']}
              return {:type=>:object_list,:data=>events,:fields=>['user.name','type','data.files_transfer_action','data.workspace_name','date']}
            when :resource
              resource_type=self.options.get_next_argument('resource',[:self,:user,:group,:client,:contact,:dropbox,:node,:operation,:package,:saml_configuration, :workspace, :dropbox_membership,:short_link,:workspace_membership,'admin/apps_new'.to_sym])
              resource_class_path=resource_type.to_s+case resource_type;when :dropbox;'es';when :self,'admin/apps_new'.to_sym;'';else; 's';end
              singleton_object=[:self].include?(resource_type)
              global_operations=[:create,:list]
              supported_operations=[:show]
              supported_operations.push(:modify,:delete,*global_operations) unless singleton_object
              supported_operations.push(:v4,:v3,:info) if resource_type.eql?(:node)
              supported_operations.push(:set_pub_key) if resource_type.eql?(:client)
              supported_operations.push(:shared_folders) if resource_type.eql?(:workspace)
              command=self.options.get_next_command(supported_operations)

              # require identifier for non global commands
              if !singleton_object and !global_operations.include?(command)
                res_id=self.options.get_option(:id)
                res_name=self.options.get_option(:name)
                if res_id.nil? and res_name.nil? and resource_type.eql?(:node)
                  set_workspace_info
                  set_home_node_file
                  res_id=@home_node_file[:node_info]['id']
                end
                if !res_name.nil?
                  Log.log.warn("name overrides id") unless res_id.nil?
                  matching=@api_aoc.read(resource_class_path,{:q=>res_name})[:data]
                  raise CliError,"no resource match name" if matching.empty?
                  raise CliError,"several resources match name (#{matching.join(',')})" unless matching.length.eql?(1)
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
                  @api_aoc.create(resource_class_path,params)[:data]
                end
              when :list
                default_fields=['id','name']
                list_query=nil
                case resource_type
                when :node; default_fields.push('host','access_key')
                when :operation; default_fields=nil
                when :contact; default_fields=["email","name","source_id","source_type"]
                when 'admin/apps_new'.to_sym; list_query={:organization_apps=>true}
                  default_fields=['app_type','available']
                end
                return {:type=>:object_list,:data=>@api_aoc.read(resource_class_path,url_query(list_query))[:data],:fields=>default_fields}
              when :show
                object=@api_aoc.read(resource_instance_path)[:data]
                fields=object.keys.select{|k|!k.eql?('certificate')}
                return { :type=>:single_object, :data =>object, :fields=>fields }
              when :modify
                changes=self.options.get_next_argument('modified parameters (hash)')
                @api_aoc.update(resource_instance_path,changes)
                return Main.result_status('modified')
              when :delete
                return do_bulk_operation(res_id,'deleted')do|one_id|
                  @api_aoc.delete("#{resource_class_path}/#{one_id.to_s}")
                  {'id'=>one_id}
                end
              when :set_pub_key
                # special : reads private and generate public
                the_private_key=self.options.get_next_argument('private_key')
                the_public_key=OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s
                @api_aoc.update(resource_instance_path,{:jwt_grant_enabled=>true, :public_key=>the_public_key})
                return Main.result_success
              when :v3,:v4
                res_data=@api_aoc.read(resource_instance_path)[:data]
                # mandatory secret : we have only AK
                self.options.get_option(:secret,:mandatory)
                @api_aoc.secrets[res_data['id']]=@option_ak_secret unless @option_ak_secret.nil?
                api_node=@api_aoc.get_node_api(res_data)
                return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node)).execute_action if command.eql?(:v3)
                ak_data=api_node.call({:operation=>'GET',:subpath=>"access_keys/#{res_data['access_key']}",:headers=>{'Accept'=>'application/json'}})[:data]
                return node_gen4_execute_action({node_info: res_data, file_id: ak_data['root_file_id']})
              when :info
                object=@api_aoc.read(resource_instance_path)[:data]
                access_key=object['access_key']
                match_list=@api_aoc.read('admin/search_nodes',{:q=>"access_key:\"#{access_key}\""})[:data]
                result=match_list.select{|i|i["_source"]["access_key_recursive_counts"].first["access_key"].eql?(access_key)}
                return Main.result_status('Private node') if result.empty?
                raise CliError,"more than one match" unless result.length.eql?(1)
                result=result.first["_source"]
                result.merge!(result['access_key_recursive_counts'].first)
                result.delete('access_key_recursive_counts')
                result.delete('token')
                return { :type=>:single_object, :data =>result}
              when :shared_folders
                res_data=@api_aoc.read("#{resource_class_path}/#{res_id}/permissions")[:data]
                return { :type=>:object_list, :data =>res_data , :fields=>['id','node_name','file_id']} #
              else raise :ERROR
              end
            when :usage_reports
              return {:type=>:object_list,:data=>@api_aoc.read("usage_reports",{:workspace_id=>@workspace_id})[:data]}
            end
          end # action
          raise RuntimeError, "internal error"
        end
      end # Aspera
    end # Plugins
  end # Cli
end # Asperalm
