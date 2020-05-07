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
        private_constant :VAL_ALL
        attr_reader :api_aoc
        attr_accessor :option_ak_secret,:option_secrets
        def initialize(env)
          super(env)
          @default_workspace_id=nil
          @workspace_name=nil
          @workspace_id=nil
          @persist_ids=nil
          @home_node_file=nil
          @api_aoc=nil
          @option_ak_secret=nil
          @option_secrets={}
          @url_token_data=nil
          @user_info=nil
          @ats=Ats.new(@agents.merge(skip_secret: true))
          self.options.set_obj_attr(:secret,self,:option_ak_secret)
          self.options.set_obj_attr(:secrets,self,:option_secrets)
          self.options.add_opt_list(:auth,Oauth.auth_types,"type of Oauth authentication")
          self.options.add_opt_list(:operation,[:push,:pull],"client operation for transfers")
          self.options.add_opt_simple(:client_id,"API client identifier in application")
          self.options.add_opt_simple(:client_secret,"API client passcode")
          self.options.add_opt_simple(:redirect_uri,"API client redirect URI")
          self.options.add_opt_simple(:private_key,"RSA private key PEM value for JWT (prefix file path with @val:@file:)")
          self.options.add_opt_simple(:workspace,"name of workspace")
          self.options.add_opt_simple(:secret,"access key secret for node")
          self.options.add_opt_simple(:secrets,"access key secret for node")
          self.options.add_opt_simple(:eid,"identifier") # used ?
          self.options.add_opt_simple(:name,"resource name")
          self.options.add_opt_simple(:link,"public link to shared resource")
          self.options.add_opt_simple(:new_user_option,"new user creation option")
          self.options.add_opt_simple(:from_folder,"share to share source folder")
          self.options.add_opt_simple(:scope,"scope for AoC API calls")
          self.options.add_opt_boolean(:bulk,"bulk operation")
          self.options.set_option(:bulk,:no)
          self.options.set_option(:new_user_option,{'package_contact'=>true})
          self.options.set_option(:operation,:push)
          self.options.set_option(:auth,:jwt)
          self.options.set_option(:scope,OnCloud::SCOPE_FILES_USER)
          self.options.set_option(:private_key,'@file:'+env[:private_key_path]) if env[:private_key_path].is_a?(String)
          self.options.parse_options!
          return if env[:man_only]
          raise CliBadArgument,"secrets shall be Hash" unless @option_secrets.is_a?(Hash)
          update_aoc_api
        end

        # call this to populate single AK secret in AoC API object, from options
        # make sure secret is available
        def find_ak_secret(ak,mandatory=true)
          # secret hash is already provisioned
          # optionally override with specific secret
          @api_aoc.add_secrets({ak=>@option_ak_secret}) unless @option_ak_secret.nil?
          # check that secret was provided as single value or dictionary
          raise CliBadArgument,"Please provide option secret or entry in option secrets for: #{ak}" unless @api_aoc.has_secret(ak) or !mandatory
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

        NODE4_COMMANDS=[ :browse, :find, :mkdir, :rename, :delete, :upload, :download, :transfer, :http_node_download, :v3, :file, :bearer_token_node, :permissions  ]

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
            # client side is agent
            # server side is protocol server
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
            client_node_file = @api_aoc.resolve_node_file(client_home_node_file,client_folder)
            server_node_file = @api_aoc.resolve_node_file(server_home_node_file,server_folder)
            # force node as agent
            self.options.set_option(:transfer,:node)
            # force node api in node agent
            Fasp::Node.instance.node_api=@api_aoc.get_node_api(client_node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            # additional node to node TS info
            add_ts={
              'remote_access_key'   => server_node_file[:node_info]['access_key'],
              'destination_root_id' => server_node_file[:file_id],
              'source_root_id'      => client_node_file[:file_id]
            }
            return Main.result_transfer(transfer_start(OnCloud::FILES_APP,client_tr_oper,server_node_file,add_ts))
          when :upload
            node_file = @api_aoc.resolve_node_file(top_node_file,self.transfer.destination_folder('send'))
            add_ts={'tags'=>{'aspera'=>{'files'=>{'parentCwd'=>"#{node_file[:node_info]['id']}:#{node_file[:file_id]}"}}}}
            return Main.result_transfer(transfer_start(OnCloud::FILES_APP,'send',node_file,add_ts))
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
            return Main.result_transfer(transfer_start(OnCloud::FILES_APP,'receive',node_file,add_ts))
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
          when :permissions
            fileid=self.options.get_next_argument('file id')
            node_file = @api_aoc.resolve_node_file(top_node_file)
            node_api=@api_aoc.get_node_api(node_file[:node_info],OnCloud::SCOPE_NODE_USER)
            command_perms=self.options.get_next_command([:show,:create])
            case command_perms
            when :show
              items=node_api.read('permissions',{'include'=>['[]','access_level','permission_count'],'file_id'=>fileid,'inherited'=>false})[:data]
              return {:type=>:object_list,:data=>items}
            when :create
              #value=self.options.get_next_argument('creation value')
              set_workspace_info
              access_id="ASPERA_ACCESS_KEY_ADMIN_WS_#{@workspace_id}"
              node_file[:node_info]
              params={
                "file_id"=>fileid,
                "access_type"=>"user",
                "access_id"=>access_id,
                "access_levels"=>["list","read","write","delete","mkdir","rename","preview"],
                "tags"=>{
                "aspera"=>{
                "files"=>{
                "workspace"=>{
                "id"=>@workspace_id,
                "workspace_name"=>@workspace_name,
                "user_name"=>user_info['name'],
                "shared_by_user_id"=>user_info['id'],
                "shared_by_name"=>user_info['name'],
                "shared_by_email"=>user_info['email'],
                "shared_with_name"=>access_id,
                "access_key"=>node_file[:node_info]['access_key'],
                "node"=>node_file[:node_info]['name']}}}}}
              item=node_api.create('permissions',params)[:data]
              return {:type=>:single_object,:data=>item}
            else raise "error"
            end
          end # command_repo
          throw "ERR"
        end # execute_node_gen4_command

        # build constructor option list for OnCloud based on options of CLI
        def aoc_rest_params(subpath)
          # copy command line options to args
          opt=[:link,:url,:auth,:client_id,:client_secret,:scope,:redirect_uri,:private_key,:username].inject({}){|m,i|m[i]=self.options.get_option(i,:optional);m}
          opt[:subpath]=subpath
          return opt
        end

        # Create a new AoC API REST object and set @api_aoc.
        # Parameters based on command line options
        # @return nil
        def update_aoc_api
          @api_aoc=OnCloud.new(aoc_rest_params('api/v1'))
          # add access key secrets
          @api_aoc.add_secrets(@option_secrets)
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

        def do_bulk_operation(params,success,id_result='id',&do_action)
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
          return {:type=>:object_list,:data=>result,:fields=>[id_result,'status']}
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

        def execute_admin_action
          self.options.set_option(:scope,OnCloud::SCOPE_FILES_ADMIN)
          update_aoc_api
          command_admin=self.options.get_next_command([ :ats, :resource, :usage_reports, :events, :subscription, :auth_providers ])
          case command_admin
          when :auth_providers
            command_auth_prov=self.options.get_next_command([ :list, :update ])
            case command_auth_prov
            when :list
              providers=@api_aoc.read('admin/auth_providers')[:data]
              return {:type=>:object_list,:data=>providers}
            when :update
            end
          when :subscription
            org=@api_aoc.read('organization')[:data]
            bss_api=Rest.new(aoc_rest_params('bss/platform'))
            graphql_query="
    query ($organization_id: ID!) {
      aoc (organization_id: $organization_id) {
        bssSubscription {
          endDate
          startDate
          termMonths
          plan
          trial
          termType
          instances {
            id
            entitlements {
              maxUsageMb
            }
          }
          additionalStorageVolumeGb
          additionalEgressVolumeGb
          additionalUsers
          term {
            startDate
            endDate
            transferVolumeGb
            egressVolumeGb
            storageVolumeGb
          }
          paygoRate {
            rate
            currency
          }
          aocPlanData {
            tier
            trial
            workspaces { max }
            users {
              planAmount
              max
            }
            samlIntegration
            activity
            sharedInboxes
            uniqueUrls
            support
          }
        }
      }
    }
  "
            result=bss_api.create('graphql',{'variables'=>{'organization_id'=>org['id']},'query'=>graphql_query})[:data]['data']
            return {:type=>:single_object,:data=>result['aoc']['bssSubscription']}
          when :ats
            ats_api = Rest.new(@api_aoc.params.deep_merge({
              :base_url => @api_aoc.params[:base_url]+'/admin/ats/pub/v1',
              :auth     => {:scope => OnCloud::SCOPE_FILES_ADMIN_USER}
            }))
            return @ats.execute_action_gen(ats_api)
            #          when :search_nodes
            #            query=self.options.get_option(:query,:optional) || '*'
            #            nodes=@api_aoc.read("search_nodes",{'q'=>query})[:data]
            #            # simplify output
            #            nodes=nodes.map do |i|
            #              item=i['_source']
            #              item['score']=i['_score']
            #              nodedata=item['access_key_recursive_counts'].first
            #              item.delete('access_key_recursive_counts')
            #              item['node']=nodedata
            #              item
            #            end
            #            return {:type=>:object_list,:data=>nodes,:fields=>['host_name','node_status.cluster_id','node_status.node_id']}
          when :events
            # begin: old
            #events=@api_aoc.read("admin/events",url_query({q: '*'}))[:data]
            #events.map!{|i|i['_source']['_score']=i['_score'];i['_source']}
            #return {:type=>:object_list,:data=>events,:fields=>['user.name','type','data.files_transfer_action','data.workspace_name','date']}
            # end: old
            events_api = Rest.new(@api_aoc.params.deep_merge({
              :base_url => @api_aoc.params[:base_url].gsub('/api/v1','')+'/analytics/v2/organizations/'+user_info['organization_id'],
              :auth     => {:scope => OnCloud::SCOPE_FILES_ADMIN_USER}
            }))
            events=events_api.read("application_events")[:data]['application_events']
            return {:type=>:object_list,:data=>events}
          when :resource
            resource_type=self.options.get_next_argument('resource',[:self,:user,:group,:client,:contact,:dropbox,:node,:operation,:package,:saml_configuration, :workspace, :dropbox_membership,:short_link,:workspace_membership,'admin/apps_new'.to_sym,'admin/client_registration_token'.to_sym])
            resource_class_path=resource_type.to_s+case resource_type;when :dropbox;'es';when :self,'admin/apps_new'.to_sym;'';else; 's';end
            singleton_object=[:self].include?(resource_type)
            global_operations=[:create,:list]
            supported_operations=[:show]
            supported_operations.push(:modify,:delete,*global_operations) unless singleton_object
            supported_operations.push(:v4,:v3) if resource_type.eql?(:node)
            supported_operations.push(:set_pub_key) if resource_type.eql?(:client)
            supported_operations.push(:shared_folders) if [:node,:workspace].include?(resource_type)
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
              id_result='id'
              id_result='token' if resource_class_path.eql?('admin/client_registration_tokens')
              # TODO: report inconsistency: creation url is !=, and does not return id.
              resource_class_path='admin/client_registration/token' if resource_class_path.eql?('admin/client_registration_tokens')
              list_or_one=self.options.get_next_argument("creation data (Hash)")
              return do_bulk_operation(list_or_one,'created',id_result)do|params|
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
              when 'admin/apps_new'.to_sym; list_query={:organization_apps=>true};default_fields=['app_type','available']
              when 'admin/client_registration_token'.to_sym; default_fields=['id','value','data.client_subject_scopes','created_at']
              end
              result=@api_aoc.read(resource_class_path,url_query(list_query))
              self.format.display_status("Items: #{result[:data].length}/#{result[:http]['X-Total-Count']}")
              return {:type=>:object_list,:data=>result[:data],:fields=>default_fields}
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
              find_ak_secret(res_data['access_key'])
              api_node=@api_aoc.get_node_api(res_data)
              return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node)).execute_action if command.eql?(:v3)
              ak_data=api_node.call({:operation=>'GET',:subpath=>"access_keys/#{res_data['access_key']}",:headers=>{'Accept'=>'application/json'}})[:data]
              return node_gen4_execute_action({node_info: res_data, file_id: ak_data['root_file_id']})
              #            when :info
              #              object=@api_aoc.read(resource_instance_path)[:data]
              #              access_key=object['access_key']
              #              match_list=@api_aoc.read('admin/search_nodes',{:q=>"access_key:\"#{access_key}\""})[:data]
              #              result=match_list.select{|i|i["_source"]["access_key_recursive_counts"].first["access_key"].eql?(access_key)}
              #              return Main.result_status('Private node') if result.empty?
              #              raise CliError,"more than one match" unless result.length.eql?(1)
              #              result=result.first["_source"]
              #              result.merge!(result['access_key_recursive_counts'].first)
              #              result.delete('access_key_recursive_counts')
              #              result.delete('token')
              #              return { :type=>:single_object, :data =>result}
            when :shared_folders
              read_params = case resource_type
              when :workspace;{'access_id'=>"ASPERA_ACCESS_KEY_ADMIN_WS_#{res_id}",'access_type'=>'user'}
              when :node;{'include'=>['[]','access_level','permission_count'],'created_by_id'=>"ASPERA_ACCESS_KEY_ADMIN"}
              else raise "error"
              end
              res_data=@api_aoc.read("#{resource_class_path}/#{res_id}/permissions",read_params)[:data]
              fields=case resource_type
              when :node;['id','file_id','file.path','access_type']
              when :workspace;['id','node_id','file_id','node_name','file.path','tags.aspera.files.workspace.share_as']
              else raise "error"
              end
              return { :type=>:object_list, :data =>res_data , :fields=>fields}
            else raise :ERROR
            end
          when :usage_reports
            return {:type=>:object_list,:data=>@api_aoc.read("usage_reports",{:workspace_id=>@workspace_id})[:data]}
          end
        end

        ACTIONS=[ :apiinfo, :bearer_token, :organization, :tier_restrictions, :user, :workspace, :packages, :files, :gateway, :admin, :automation, :servers]

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

              # list of files to include in package, optional
              #package_creation['file_names']=self.transfer.ts_source_paths.map{|i|File.basename(i['source'])}

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
              return Main.result_transfer(transfer_start(OnCloud::PACKAGES_APP,'send',node_file,OnCloud.package_tags(package_info,'upload')))
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
                statuses=transfer_start(OnCloud::PACKAGES_APP,'receive',node_file,OnCloud.package_tags(package_info,'download').merge(add_ts))
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
            find_ak_secret(@home_node_file[:node_info]['access_key'],false)
            command_repo=self.options.get_next_command(NODE4_COMMANDS.clone.concat([:short_link]))
            case command_repo
            when *NODE4_COMMANDS; return execute_node_gen4_command(command_repo,@home_node_file)
            when :short_link
              return self.entity_action(@api_aoc,'short_links',nil,:id,'self')
            end
            throw "Error"
          when :automation
            Log.log.warn("BETA: work under progress")
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
                return {:type=>:single_object,:data=>data}
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
          when :gateway
            set_workspace_info
            require 'asperalm/faspex_gw'
            FaspexGW.new(@api_aoc,@workspace_id).start_server
          when :admin
            return execute_admin_action
          when :servers
            self.format.display_status("Beta feature")
            server_api=Rest.new(base_url: 'https://eudemo.asperademo.com')
            require 'json'
            servers=JSON.parse(server_api.read('servers')[:data])
            return {:type=>:object_list,:data=>servers}
          else
            raise "internal error: #{command}"
          end # action
          raise RuntimeError, "internal error: command shall return"
        end
      end # Aspera
    end # Plugins
  end # Cli
end # Asperalm
