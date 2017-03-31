require 'asperalm/cli/plugin'
require 'asperalm/browser_interaction'
require 'asperalm/oauth'
require 'asperalm/files_api'
require 'SecureRandom'

# get end points here:

module Asperalm
  module Cli
    module Plugins
      class Files < Plugin
        def opt_names; [:private_key,:username,:url,:auth,:code_getter,:client_id,:client_secret,:redirect_uri,:subject]; end

        def get_auths; Oauth.auth_types; end

        def get_code_getters; BrowserInteraction.getter_types; end

        attr_accessor :faspmanager

        def get_node_api(node_info,scope)
          return Rest.new(node_info['url'],{:oauth=>@api_files_oauth,:scope=>FilesApi.node_scope(node_info['access_key'],scope),:headers=>{'X-Aspera-AccessKey'=>node_info['access_key']}})
        end

        # returns node information (returned by API) and file id, from a "/" based path
        # supports links to secondary nodes
        # input keys:file_id
        # output keys: file_id and node_info
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
            current_node_api=get_node_api(node_info,FilesApi::SCOPE_NODE_USER) if current_node_api.nil?

            # get folder content
            folder_contents = current_node_api.list("files/#{file_id}/files")
            Log.log.debug "folder_contents: #{folder_contents}"
            matching_folders = folder_contents[:data].select { |i| i['name'].eql?(this_folder_name)}
            Log.log.debug "matching_folders: #{matching_folders}"
            # there shall be one folder , or none that match the name
            case matching_folders.length
            when 0
              raise OptionParser::InvalidArgument, "no such folder: #{this_folder_name} in #{folder_contents[:data].map { |i| i['name']}}"
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
                raise OptionParser::InvalidArgument, "#{this_folder_name} is a file, expecting folder to find: #{path_array}"
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

        def info_to_tspec(direction,node_info,file_id,files_tags)
          return {
            'direction'        => direction,
            'remote_user'      => 'xfer',
            'remote_host'      => node_info['host'],
            "fasp_port"        => 33001,
            "ssh_port"         => 33001,
            #"target_rate_kbps" => 10000,
            'token'            => @api_files_oauth.get_authorization(FilesApi.node_scope(node_info['access_key'],FilesApi::SCOPE_NODE_USER)),
            'tags'             => { "aspera" => { "files" => files_tags, "node" => { "access_key" => node_info['access_key'], "file_id" => file_id }, "xfer_id" => SecureRandom.uuid, "xfer_retry" => 3600 } } }
        end

        def command_list; [ :browse, :send, :recv, :packages, :upload, :download, :events, :set_client_key, :faspexgw, :admin,:usage_reports ];end

        def set_options
          @code_getter=:tty
          self.add_opt_list(:auth,"type of authentication",'-tTYPE','--auth=TYPE')
          self.add_opt_list(:code_getter,"method to start browser",'-gTYPE','--code-get=TYPE')
          self.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          self.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          self.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
          self.add_opt_simple(:private_key,"-kSTRING", "--private-key=STRING","RSA private key (@ for ext. file)")
          self.add_opt_simple(:workspace,"--workspace=STRING","name of workspace")
          self.add_opt_simple(:loop,"--loop=true","keep processing")
        end

        def dojob(command,argv)

          # get parameters
          instance_fqdn=URI.parse(self.get_option_mandatory(:url)).host
          organization,instance_domain=instance_fqdn.split('.',2)

          Log.log.debug("instance_fqdn=#{instance_fqdn}")
          Log.log.debug("instance_domain=#{instance_domain}")
          Log.log.debug("organization=#{organization}")

          auth_data={:type=>self.get_option_mandatory(:auth)}
          case auth_data[:type]
          when :basic
            auth_data[:username]=self.get_option_mandatory(:username)
            auth_data[:password]=self.get_option_mandatory(:password)
          when :web
            Log.log.info("redirect_uri=#{self.get_option_mandatory(:redirect_uri)}")
            auth_data[:bi]=BrowserInteraction.new(self.get_option_mandatory(:redirect_uri),self.get_option_mandatory(:code_getter))
            if !@username.nil? and !@password.nil? then
              auth_data[:bi].set_creds(self.get_option_mandatory(:username),self.get_option_mandatory(:password))
            end
          when :jwt
            auth_data[:private_key]=OpenSSL::PKey::RSA.new(self.get_option_mandatory(:private_key))
            auth_data[:subject]=self.get_option_mandatory(:subject)
            Log.log.info("private_key=#{auth_data[:private_key]}")
            Log.log.info("subject=#{auth_data[:subject]}")
          else
            raise "unknown auth type: #{auth_data[:type]}"
          end

          files_api_base_url=FilesApi.baseurl(instance_domain)

          # auth API
          @api_files_oauth=Oauth.new(files_api_base_url,organization,self.get_option_mandatory(:client_id),self.get_option_mandatory(:client_secret),auth_data)

          # create object for REST calls to Files with scope "user:all"
          @api_files_user=Rest.new(files_api_base_url,{:oauth=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_USER})

          # get our user's default information
          self_data=@api_files_user.read("self")[:data]

          ws_name=self.get_option_optional(:workspace)
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
              raise OptionParser::InvalidArgument,"no such workspace: #{ws_name}"
            when 1
              workspace_data=wss[0]
              workspace_id=workspace_data['id']
            else
              raise "unexpected case"
            end
          end

          # display name of default workspace
          Log.log.info("current workspace is "+workspace_data['name'].red)

          # NOTE: important: transfer id must be unique: generate random id (using a non unique id results in discard of tags, and package is not finalized)
          xfer_id=SecureRandom.uuid

          case command
          when :browse
            default_fields=['name','type','recursive_size','size','modified_time','access_level']
            thepath=self.class.get_next_arg_value(argv,"path")
            node_info,file_id = find_nodeinfo_and_fileid(workspace_data['home_node_id'],workspace_data['home_file_id'],thepath.split('/'))
            node_api=get_node_api(node_info,FilesApi::SCOPE_NODE_USER)
            items=node_api.list("files/#{file_id}/files")[:data]
            return {:fields=>default_fields,:values=>items}
          when :upload
            filelist = self.class.get_remaining_arguments(argv,"file list,destination")
            Log.log.debug("file list=#{filelist}")
            raise OptionParser::InvalidArgument,"Missing source(s) and destination" if filelist.length < 2
            destination_folder=filelist.pop
            node_info,file_id = find_nodeinfo_and_fileid(workspace_data['home_node_id'],workspace_data['home_file_id'],destination_folder.split('/'))
            tspec=info_to_tspec("send",node_info,file_id,{})
            tspec['paths']=filelist.map { |i| {'source'=>i} }
            tspec['destination_root']="/"
            @faspmanager.transfer_with_spec(tspec)
          when :download
            source_file=self.class.get_next_arg_value(argv,'source')
            destination_folder=self.class.get_next_arg_value(argv,'destination')
            file_path = source_file.split('/')
            file_name = file_path.pop
            node_info,file_id = find_nodeinfo_and_fileid(workspace_data['home_node_id'],workspace_data['home_file_id'],file_path)
            tspec=info_to_tspec('receive',node_info,file_id,{})
            tspec['paths']=[{'source'=>file_name}]
            tspec['destination_root']=destination_folder
            @faspmanager.transfer_with_spec(tspec)
          when :send

            # list of files to include in package
            filelist = self.class.get_remaining_arguments(argv,"file list")

            # lookup a user: myself, I could directly use self_data['id'], but that's to show lookup
            # TODO: add param
            recipient=self_data['email']

            # lookup exactly one user
            user_lookup=@api_files_user.list("contacts",{'current_workspace_id'=>workspace_id,'q'=>recipient})[:data]
            raise "no such unique user: #{recipient}" unless !user_lookup.nil? and user_lookup.length == 1
            recipient_user_id=user_lookup.first

            #TODO: allow to set title, and add other users

            #  create a new package with one file
            the_package=@api_files_user.create("packages",{"workspace_id"=>workspace_id,"name"=>"sent from script","file_names"=>filelist,"note"=>"trid=#{xfer_id}","recipients"=>[{"id"=>recipient_user_id['source_id'],"type"=>recipient_user_id['source_type']}]})[:data]

            #  get node information for the node on which package must be created
            node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]

            # tell Files what to expect in package: 1 transfer (can also be done after transfer)
            resp=@api_files_user.update("packages/#{the_package['id']}",{"sent"=>true,"transfers_expected"=>1})[:data]

            tspec=info_to_tspec("send",node_info,the_package['contents_file_id'],{"package_id" => the_package['id'], "package_operation" => "upload"})
            tspec['paths']=filelist.map { |i| {'source'=>i} }
            tspec['destination_root']="/"
            @faspmanager.transfer_with_spec(tspec)
            # simulate call later, to check status (this is just demo api call, not needed)
            sleep 2
            # (sample) get package status
            allpkg=@api_files_user.read("packages/#{the_package['id']}")[:data]
          when :recv
            package_id=self.class.get_next_arg_value(argv,'package ID')
            the_package=@api_files_user.read("packages/#{package_id}")[:data]
            #packages=@api_files_user.list("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>workspace_id})[:data]
            # take the last one
            #the_package=packages.first
            #  get node info
            node_info=@api_files_user.read("nodes/#{the_package['node_id']}")[:data]
            tspec=info_to_tspec("receive",node_info,the_package['contents_file_id'],{"package_id" => the_package['id'], "package_operation" => "download"})
            tspec['paths']=[{'source'=>'.'}]
            tspec['destination_root']='.' # TODO:param?
            @faspmanager.transfer_with_spec(tspec)
          when :packages
            default_fields=['id','name','bytes_transferred']
            # list all packages ('page'=>1,'per_page'=>10,)'sort'=>'-sent_at',
            packages=@api_files_user.list("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>workspace_id})[:data]
            return {:fields=>default_fields,:values=>packages}
          when :events
            api_files_admin=Rest.new(files_api_base_url,{:oauth=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_ADMIN})
            # page=1&per_page=10&q=type:(file_upload+OR+file_delete+OR+file_download+OR+file_rename+OR+folder_create+OR+folder_delete+OR+folder_share+OR+folder_share_via_public_link)&sort=-date
            events=api_files_admin.list('events',{'q'=>'type:(file_upload OR file_download)'})[:data]
            #Log.log.info "events=#{JSON.generate(events)}"
            node_info=@api_files_user.read("nodes/#{workspace_data['home_node_id']}")[:data]
            # get access to node API, note the additional header
            api_node_admin=get_node_api(node_info,FilesApi::SCOPE_NODE_ADMIN)
            # can add filters: tag=aspera.files.package_id%3DLA8OU3p8w
            #'tag'=>'aspera.files.package_id%3DJvbl0w-5A'
            # filter= 'id', 'short_summary', or 'summary'
            # count=nnn
            # tag=x.y.z%3Dvalue
            # iteration_token=nnn
            # active_only=true|false
            events=api_node_admin.list("ops/transfers",{'count'=>100,'filter'=>'summary','active_only'=>'true'})[:data]
            return {:fields=>['id','status'],:values=>events}
            #transfers=api_node_admin.make_request_ex({:operation=>'GET',:subpath=>'ops/transfers',:args=>{'count'=>25,'filter'=>'id'}})
            #transfers=api_node_admin.list("events") # after_time=2016-05-01T23:53:09Z
          when :set_client_key
            the_client_id=self.class.get_next_arg_value(argv,'client_id')
            the_private_key=self.class.get_next_arg_value(argv,'private_key')
            api_files_admin=Rest.new(files_api_base_url,{:oauth=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_ADMIN})
            api_files_admin.update("clients/#{the_client_id}",{:jwt_grant_enabled=>true, :public_key=>OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s})
            return nil
          when :faspexgw
            require 'asperalm/faspex_gw'
            FaspexGW.set_vars(@api_files_user,@api_files_oauth)
            FaspexGW.go()
          when :admin
            api_files_admin=Rest.new(files_api_base_url,{:oauth=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_ADMIN})
            resource=self.class.get_next_arg_from_list(argv,'resource',[:clients,:contacts,:dropboxes,:nodes,:operations,:packages,:saml_configurations])
            #:messages:organizations:url_tokens,:usage_reports:workspaces
            operation=self.class.get_next_arg_from_list(argv,'operation',[:list])
            case operation
            when :list
              default_fields=['id','name']
              case resource
              when :nodes; default_fields.push('host','access_key')
              end
              res=api_files_admin.list(resource.to_s)[:data]
              return {:fields=>default_fields,:values=>res }
            else
              raise RuntimeError, "unexpected value: #{resource}"
            end#operation
          when :usage_reports
            api_files_admin=Rest.new(files_api_base_url,{:oauth=>@api_files_oauth,:scope=>FilesApi::SCOPE_FILES_ADMIN})
            res=api_files_admin.list("usage_reports",{:workspace_id=>workspace_id})[:data]
            return {:fields=>default_fields,:values=>res }
          else
            raise RuntimeError, "unexpected value: #{command}"
          end # action
        end
      end
    end
  end # Cli
end # Asperalm
