require 'asperalm/cli/plugins/node'
require 'asperalm/cli/plugin'
require 'asperalm/oauth'
require 'asperalm/files_api'
require 'SecureRandom'

module Asperalm
  module Cli
    module Plugins
      class Files < Plugin
        attr_accessor :faspmanager
        # returns a node API for access key
        # no scope: requires secret
        # if secret present: use it
        def get_ak_node_api(node_info,node_scope=nil)
          # if no scope, or secret provided on command line ...
          if node_scope.nil? or !self.options.get_option(:secret).nil?
            return Rest.new(node_info['url'],{:basic_auth=>{:user=>node_info['access_key'], :password=>self.options.get_option_mandatory(:secret)},:headers=>{'X-Aspera-AccessKey'=>node_info['access_key']}})
          end
          Log.log.warn("ignoring secret, using bearer token") if !self.options.get_option(:secret).nil?
          return Rest.new(node_info['url'],{:oauth=>@api_files_oauth,:scope=>FilesApi.node_scope(node_info['access_key'],node_scope),:headers=>{'X-Aspera-AccessKey'=>node_info['access_key']}})
        end

        # returns node information (returned by API) and file id, from a "/" based path
        # supports links to secondary nodes
        # input: root node and file id, and array for path
        # output: file_id and node_info  for the given path
        def find_nodeinfo_and_fileid ( init_node_id, file_id, path_array )
          Log.log.debug "find_nodeinfo_and_fileid: nodeid=#{init_node_id}, #{file_id}, array=#{path_array}"
          # at least retrieve node info
          node_info=@api_files_user.read("nodes/#{init_node_id}")[:data]
          # first element is empty if path was starting with /
          path_array.shift if !path_array.empty? and path_array.first.eql?("")

          while !path_array.empty? do
            this_folder_name = path_array.shift
            Log.log.debug "searching #{this_folder_name}"

            # get API if changed
            current_node_api=get_ak_node_api(node_info,FilesApi::SCOPE_NODE_USER) if current_node_api.nil?

            # get folder content
            folder_contents = current_node_api.list("files/#{file_id}/files")
            Log.log.debug "folder_contents: #{folder_contents}"
            matching_folders = folder_contents[:data].select { |i| i['name'].eql?(this_folder_name)}
            Log.log.debug "matching_folders: #{matching_folders}"
            # there shall be one folder , or none that match the name
            case matching_folders.length
            when 0
              raise CliBadArgument, "no such folder: #{this_folder_name} in #{folder_contents[:data].map { |i| i['name']}}"
            when 1
              file_info = matching_folders[0]
            else
              raise "fund more than one folder matching a name, should not happen"
            end
            # process type of file
            case file_info['type']
            when 'file'
              # a file shall be terminal
              if !path_array.empty? then
                raise CliBadArgument, "#{this_folder_name} is a file, expecting folder to find: #{path_array}"
              end
            when 'link'
              node_info=@api_files_user.read("nodes/#{file_info['target_node_id']}")[:data]
              file_id=file_info["target_id"]
              current_node_api=nil
            when 'folder'
              file_id=file_info["id"]
            else
              Log.log.warn "unknown element type: #{file_info['type']}"
            end
          end
          Log.log.info("node_info,file_id=#{node_info},#{file_id}")
          return node_info,file_id
        end

        # generate a transfer spec from node information and file id
        # NOTE: important: transfer id must be unique: generate random id (using a non unique id results in discard of tags, and package is not finalized)
        def info_to_tspec(direction,node_info,file_id)
          return {
            'direction'        => direction,
            'remote_user'      => 'xfer',
            'remote_host'      => node_info['host'],
            "fasp_port"        => 33001,
            "ssh_port"         => 33001,
            'token'            => @api_files_oauth.get_authorization(FilesApi.node_scope(node_info['access_key'],FilesApi::SCOPE_NODE_USER)),
            'tags'             => { "aspera" => { "node" => { "access_key" => node_info['access_key'], "file_id" => file_id }, "xfer_id" => SecureRandom.uuid, "xfer_retry" => 3600 } } }
        end

        def set_options
          self.options.add_opt_list(:auth,Oauth.auth_types,"type of authentication",'-tTYPE','--auth=TYPE')
          self.options.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.options.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.options.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
          self.options.add_opt_simple(:private_key,"-kSTRING", "--private-key=STRING","RSA private key for JWT (@ for ext. file)")
          self.options.add_opt_simple(:workspace,"--workspace=STRING","name of workspace")
          self.options.add_opt_simple(:recipient,"--recipient=STRING","package recipient")
          self.options.add_opt_simple(:title,"--title=STRING","package title")
          self.options.add_opt_simple(:note,"--note=STRING","package note")
          self.options.add_opt_simple(:secret,"--secret=STRING","access key secret for node")
        end

        def execute_node_action(home_node_id,home_file_id)
          command_repo=self.options.get_next_arg_from_list('command',[ :browse, :upload, :download, :info ])
          case command_repo
          when :info
            node_info=@api_files_user.read("nodes/#{home_node_id}")[:data]
            node_api=get_ak_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            return Node.execute_common(command_repo,node_api,self.options,@faspmanager)
          when :browse
            thepath=self.options.get_next_arg_value("path")
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,thepath.split('/'))
            node_api=get_ak_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            items=node_api.list("files/#{file_id}/files")[:data]
            return {:values=>items,:fields=>['name','type','recursive_size','size','modified_time','access_level']}
          when :upload
            filelist = self.options.get_remaining_arguments("file list,destination")
            Log.log.debug("file list=#{filelist}")
            raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
            destination_folder=filelist.pop
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,destination_folder.split('/'))
            tspec=info_to_tspec("send",node_info,file_id)
            tspec['tags']["aspera"]["files"]={}
            tspec['paths']=filelist.map { |i| {'source'=>i} }
            tspec['destination_root']="/"
            @faspmanager.transfer_with_spec(tspec)
          when :download
            source_file=self.options.get_next_arg_value('source')
            destination_folder=self.options.get_next_arg_value('destination')
            file_path = source_file.split('/')
            file_name = file_path.pop
            node_info,file_id = find_nodeinfo_and_fileid(home_node_id,home_file_id,file_path)
            tspec=info_to_tspec('receive',node_info,file_id)
            tspec['tags']["aspera"]["files"]={}
            tspec['paths']=[{'source'=>file_name}]
            tspec['destination_root']=destination_folder
            @faspmanager.transfer_with_spec(tspec)
          end
        end

        def execute_action
          command=self.options.get_next_arg_from_list('command',[ :package, :repo, :faspexgw, :admin])

          # get parameters
          instance_fqdn=URI.parse(self.options.get_option_mandatory(:url)).host
          organization,instance_domain=instance_fqdn.split('.',2)
          files_api_base_url=FilesApi.baseurl(instance_domain)

          Log.log.debug("instance_fqdn=#{instance_fqdn}")
          Log.log.debug("instance_domain=#{instance_domain}")
          Log.log.debug("organization=#{organization}")

          auth_data={
            :type=>self.options.get_option_mandatory(:auth),
            :client_id =>self.options.get_option_mandatory(:client_id),
            :client_secret=>self.options.get_option_mandatory(:client_secret)
          }

          case auth_data[:type]
          when :basic
            auth_data[:username]=self.options.get_option_mandatory(:username)
            auth_data[:password]=self.options.get_option_mandatory(:password)
          when :web
            auth_data[:redirect_uri]=self.options.get_option_mandatory(:redirect_uri)
            Log.log.info("redirect_uri=#{auth_data[:redirect_uri]}")
          when :jwt
            auth_data[:private_key]=OpenSSL::PKey::RSA.new(self.options.get_option_mandatory(:private_key))
            auth_data[:subject]=self.options.get_option_mandatory(:username)
            Log.log.info("private_key=#{auth_data[:private_key]}")
            Log.log.info("subject=#{auth_data[:subject]}")
          else
            raise "unknown auth type: #{auth_data[:type]}"
          end

          # auth API
          @api_files_oauth=Oauth.new(files_api_base_url,organization,auth_data)

          # create object for REST calls to Files with scope "user:all"
          @api_files_user=Rest.new(files_api_base_url,{:oauth=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_USER})

          # get our user's default information
          self_data=@api_files_user.read("self")[:data]

          ws_name=self.options.get_option(:workspace)
          if ws_name.nil?
            # get default workspace
            workspace_id=self_data['default_workspace_id']
            workspace_data=@api_files_user.read("workspaces/#{workspace_id}")[:data]
          else
            # lookup another workspace
            wss=@api_files_user.list("workspaces",{'q'=>ws_name})[:data]
            wss=wss.select { |i| i['name'].eql?(ws_name) }
            case wss.length
            when 0
              raise CliBadArgument,"no such workspace: #{ws_name}"
            when 1
              workspace_data=wss[0]
              workspace_id=workspace_data['id']
            else
              raise "unexpected case"
            end
          end

          if self.options.get_option(:format).eql?(:text_table) and !command.eql?(:admin)
            deflt=""
            deflt=" (default)" if (workspace_id == self_data['default_workspace_id'])
            puts "Current Workspace: #{workspace_data['name'].red}#{deflt}"
          end

          # display name of default workspace
          Log.log.info("current workspace is "+workspace_data['name'].red)

          case command
          when :package
            command_pkg=self.options.get_next_arg_from_list('command',[ :send, :recv, :list ])
            case command_pkg
            when :send
              # list of files to include in package
              filelist = self.options.get_remaining_arguments("file list")

              # lookup users
              recipient_data=self.options.get_option_mandatory(:recipient).split(',').map { |recipient|
                user_lookup=@api_files_user.list("contacts",{'current_workspace_id'=>workspace_id,'q'=>recipient})[:data]
                raise CliBadArgument,"no such user: #{recipient}" unless !user_lookup.nil? and user_lookup.length == 1
                recipient_user_id=user_lookup.first
                {"id"=>recipient_user_id['source_id'],"type"=>recipient_user_id['source_type']}
              }

              #  create a new package with one file
              the_package=@api_files_user.create("packages",{"workspace_id"=>workspace_id,"name"=>self.options.get_option_mandatory(:title),"file_names"=>filelist,"note"=>self.options.get_option_mandatory(:note),"recipients"=>recipient_data})[:data]

              #  get node information for the node on which package must be created
              node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]

              # tell Files what to expect in package: 1 transfer (can also be done after transfer)
              resp=@api_files_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})[:data]

              tspec=info_to_tspec("send",node_info,the_package['contents_file_id'])
              tspec['tags']["aspera"]["files"]={"package_id" => the_package['id'], "package_operation" => "upload"}
              tspec['paths']=filelist.map { |i| {'source'=>i} }
              tspec['destination_root']="/"
              @faspmanager.transfer_with_spec(tspec)
              return nil
              # simulate call later, to check status (this is just demo api call, not needed)
              #sleep 2
              # (sample) get package status
              #allpkg=@api_files_user.read("packages/#{the_package['id']}")[:data]
            when :recv
              package_id=self.options.get_next_arg_value('package ID')
              the_package=@api_files_user.read("packages/#{package_id}")[:data]
              #packages=@api_files_user.list("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>workspace_id})[:data]
              # take the last one
              #the_package=packages.first
              #  get node info
              node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]
              tspec=info_to_tspec("receive",node_info,the_package['contents_file_id'])
              tspec['tags']["aspera"]["files"]={"package_id" => the_package['id'], "package_operation" => "download"}
              tspec['paths']=[{'source'=>'.'}]
              tspec['destination_root']='.' # TODO:param?
              @faspmanager.transfer_with_spec(tspec)
            when :list
              # list all packages ('page'=>1,'per_page'=>10,)'sort'=>'-sent_at',
              packages=@api_files_user.list("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>workspace_id})[:data]
              return {:values=>packages,:fields=>['id','name','bytes_transferred']}
            end
          when :repo
            home_node_id=workspace_data['home_node_id']
            home_file_id=workspace_data['home_file_id']
            return execute_node_action(home_node_id,home_file_id)
          when :faspexgw
            require 'asperalm/faspex_gw'
            FaspexGW.set_vars(@api_files_user,@api_files_oauth)
            FaspexGW.go()
          when :admin
            api_files_admin=Rest.new(files_api_base_url,{:oauth=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_ADMIN})
            command_admin=self.options.get_next_arg_from_list('command',[ :resource, :events, :set_client_key, :usage_reports  ])
            case command_admin
            when :events
              # page=1&per_page=10&q=type:(file_upload+OR+file_delete+OR+file_download+OR+file_rename+OR+folder_create+OR+folder_delete+OR+folder_share+OR+folder_share_via_public_link)&sort=-date
              #events=api_files_admin.list('events',{'q'=>'type:(file_upload OR file_download)'})[:data]
              #Log.log.info "events=#{JSON.generate(events)}"
              node_info=@api_files_user.read("nodes/#{workspace_data['home_node_id']}")[:data]
              # get access to node API, note the additional header
              api_node=get_ak_node_api(node_info,FilesApi::SCOPE_NODE_USER)
              # can add filters: tag=aspera.files.package_id%3DLA8OU3p8w
              #'tag'=>'aspera.files.package_id%3DJvbl0w-5A'
              # filter= 'id', 'short_summary', or 'summary'
              # count=nnn
              # tag=x.y.z%3Dvalue
              # iteration_token=nnn
              # active_only=true|false
              events=api_node.list("ops/transfers",{'count'=>100,'filter'=>'summary','active_only'=>'true'})[:data]
              return {:values=>events,:fields=>['id','status']}
              #transfers=api_node.make_request_ex({:operation=>'GET',:subpath=>'ops/transfers',:args=>{'count'=>25,'filter'=>'id'}})
              #transfers=api_node.list("events") # after_time=2016-05-01T23:53:09Z
            when :set_client_key
              the_client_id=self.options.get_next_arg_value('client_id')
              the_private_key=self.options.get_next_arg_value('private_key')
              res=api_files_admin.update("clients/#{the_client_id}",{:jwt_grant_enabled=>true, :public_key=>OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s})
              return nil
            when :resource
              resource=self.options.get_next_arg_from_list('resource',[:user,:group,:client,:contact,:dropbox,:node,:operation,:package,:saml_configuration, :workspace])
              resources=resource.to_s+(resource.eql?(:dropbox) ? 'es' : 's')
              #:messages:organizations:url_tokens,:usage_reports:workspaces
              operations=[:list,:id]
              #command=self.options.get_next_arg_value('op_or_id')
              command=self.options.get_next_arg_from_list('command',operations)
              case command
              when :list
                default_fields=['id','name']
                case resource
                when :node; default_fields.push('host','access_key')
                when :operation; default_fields=nil
                when :contact; default_fields=["email","name","source_id","source_type"]
                end
                return {:values=>api_files_admin.list(resources)[:data],:fields=>default_fields}
              when :id
                #raise RuntimeError, "unexpected resource type: #{resource}, only 'node' for actions" if !resource.eql?(:node)
                res_id=self.options.get_next_arg_value('node id')
                res_data=@api_files_user.read("#{resources}/#{res_id}")[:data]
                case resource
                when :node
                  api_node=get_ak_node_api(res_data)
                  ak_data=api_node.call({:operation=>'GET',:subpath=>"access_keys/#{res_data['access_key']}",:headers=>{'Accept'=>'application/json'}})[:data]
                  return execute_node_action(res_id,ak_data['root_file_id'])
                else
                  return { :format=>:hash_table, :values => res_data }# TODO
                end
              end #op_or_id
            when :usage_reports
              return {:values=>api_files_admin.list("usage_reports",{:workspace_id=>workspace_id})[:data]}
            end
          else
            raise RuntimeError, "unexpected value: #{command}"
          end # action
        end
      end # Files
    end # Plugins
  end # Cli
end # Asperalm
