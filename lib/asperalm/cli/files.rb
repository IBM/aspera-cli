require 'SecureRandom'
require 'optparse'
require 'pp'
require 'asperalm/browser_interaction'
require 'asperalm/oauth'
require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/opt_parser'

module Asperalm
  module Cli
    class Files
      def opt_names; [:private_key,:username,:url,:auth,:code_getter,:client_id,:client_secret,:redirect_uri,:subject]; end

      def get_auths; Oauth.auth_types; end

      def get_code_getters; BrowserInteraction.getter_types; end

      # get API base URL based on instance domain
      def self.baseurl(instance_domain)
        return 'https://api.'+instance_domain+'/api/v1'
      end

      # node API scopes
      def self.node_scope(access_key,scope)
        return 'node.'+access_key+':'+scope
      end

      # various API scopes supported
      @@SCOPE_FILES_SELF='self'
      @@SCOPE_FILES_USER='user:all'
      @@SCOPE_FILES_ADMIN='admin:all'
      @@SCOPE_NODE_USER='user:all'
      @@SCOPE_NODE_ADMIN='admin:all'

      attr_accessor :logger
      attr_accessor :faspmanager

      def initialize(logger)
        @logger=logger
        @code_getter=:tty
      end

      def go(argv,defaults)
        begin
          opt_parser = OptParser.new(self)
          opt_parser.set_defaults(defaults)
          opt_parser.banner = "NAME\n\t#{$0} -- a command line tool for Aspera Applications\n\n"
          opt_parser.separator "SYNOPSIS"
          opt_parser.separator "\t#{$0} ... files [OPTIONS] COMMAND [ARGS]..."
          opt_parser.separator ""
          opt_parser.separator "OPTIONS"
          opt_parser.add_opt_list(:auth,"type of authentication",'-tTYPE','--auth=TYPE')
          opt_parser.add_opt_list(:code_getter,"method to start browser",'-gTYPE','--code-get=TYPE')
          opt_parser.add_opt_simple(:url,"-wURI", "--url=URI","URL of application, e.g. http://org.asperafiles.com")
          opt_parser.add_opt_simple(:username,"-uSTRING", "--username=STRING","username to log in")
          opt_parser.add_opt_simple(:password,"-pSTRING", "--password=STRING","password")
          opt_parser.add_opt_simple(:private_key,"-kSTRING", "--private-key=STRING","RSA private key (@ for ext. file)")
          opt_parser.add_opt_simple(:workspace,"--workspace=STRING","name of workspace")
          opt_parser.add_opt_simple(:loop,"--loop=true","keep processing")
          opt_parser.on_tail("-h", "--help", "Show this message") { opt_parser.exit_with_usage }
          opt_parser.parse_ex!(argv)

          # get parameters
          instance_fqdn=URI.parse(opt_parser.get_option_mandatory(:url)).host
          organization,instance_domain=instance_fqdn.split('.',2)

          @logger.debug("instance_fqdn=#{instance_fqdn}")
          @logger.debug("instance_domain=#{instance_domain}")
          @logger.debug("organization=#{organization}")

          auth_data={:type=>opt_parser.get_option_mandatory(:auth)}
          case auth_data[:type]
          when :basic
            auth_data[:username]=opt_parser.get_option_mandatory(:username)
            auth_data[:password]=opt_parser.get_option_mandatory(:password)
          when :web
            @logger.info("redirect_uri=#{opt_parser.get_option_mandatory(:redirect_uri)}")
            auth_data[:bi]=BrowserInteraction.new(@logger,opt_parser.get_option_mandatory(:redirect_uri),opt_parser.get_option_mandatory(:code_getter))
            if !@username.nil? and !@password.nil? then
              auth_data[:bi].set_creds(opt_parser.get_option_mandatory(:username),opt_parser.get_option_mandatory(:password))
            end
          when :jwt
            auth_data[:private_key]=OpenSSL::PKey::RSA.new(opt_parser.get_option_mandatory(:private_key))
            auth_data[:subject]=opt_parser.get_option_mandatory(:subject)
            @logger.info("private_key=#{auth_data[:private_key]}")
            @logger.info("subject=#{auth_data[:subject]}")
          else
            raise "unknown auth type: #{auth_data[:type]}"
          end

          files_api_base_url=self.class.baseurl(instance_domain)

          # auth API
          api_files_oauth=Oauth.new(@logger,files_api_base_url,organization,opt_parser.get_option_mandatory(:client_id),opt_parser.get_option_mandatory(:client_secret),auth_data)

          # create object for REST calls to Files with scope "user:all"
          api_files_user=Rest.new(@logger,files_api_base_url,{:oauth=>api_files_oauth,:scope=>@@SCOPE_FILES_USER})

          # get our user's default information
          self_data=api_files_user.read("self")[:data]

          ws_name=opt_parser.get_option_optional(:workspace)
          if ws_name.nil?
            # get default workspace
            workspace_id=self_data['default_workspace_id']
            workspace_data=api_files_user.read("workspaces",workspace_id)[:data]
          else
            # lookup another workspace
            wss=api_files_user.list("workspaces",{'q'=>ws_name})[:data]
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
          @logger.info("default workspace is "+workspace_data['name'].red)

          command=OptParser.get_next_arg_from_list(argv,'command',[ :send, :recv, :events, :jwt, :set_client_key, :faspexgw, :files_res, :admin ])

          results=''

          case command
          when :send

            # list of files to include in package
            filelist = argv
            @logger.info("file list=#{filelist}")
            if filelist.empty? then
              raise OptionParser::InvalidArgument,"missing file list"
            end

            # lookup a user: myself, I could directly use self_data['id'], but that's to show lookup
            # TODO: add param
            recipient=self_data['email']

            # lookup exactly one user
            user_lookup=api_files_user.list("contacts",{'current_workspace_id'=>workspace_id,'q'=>recipient})[:data]
            raise "no such unique user: #{recipient}" unless !user_lookup.nil? and user_lookup.length == 1
            recipient_user_id=user_lookup.first

            # NOTE: important: transfer id must be unique: generate random id (using a non unique id results in discard of tags, and package is not finalized)
            xfer_id=SecureRandom.uuid

            #TODO: allow to set title, and add other users

            #  create a new package with one file
            the_package=api_files_user.create("packages",{"workspace_id"=>workspace_id,"name"=>"sent from script","file_names"=>filelist,"note"=>"trid=#{xfer_id}","recipients"=>[{"id"=>recipient_user_id['source_id'],"type"=>recipient_user_id['source_type']}]})[:data]

            #  get node information for the node on which package must be created
            node_info=api_files_user.read("nodes",the_package['node_id'])[:data]

            # tell Files what to expect in package: 1 transfer (can also be done after transfer)
            resp=api_files_user.update("packages",the_package['id'],{"sent"=>true,"transfers_expected"=>1})[:data]

            #  get transfer token (for node)
            node_bearer_token_xfer=api_files_oauth.get_authorization(self.class.node_scope(node_info['access_key'],@@SCOPE_NODE_USER))

            # transfer files
            @logger.info "starting transfer"
            @faspmanager.do_transfer(
            :retries   => 10,
            :mode      => :send,
            :user      => 'xfer',
            :host      => node_info['host'],
            :token     => node_bearer_token_xfer,
            :tags      => { "aspera" => { "files" => { "package_id" => the_package['id'], "package_operation" => "upload" }, "node" => { "access_key" => node_info['access_key'], "file_id" => the_package['contents_file_id'] }, "xfer_id" => xfer_id, "xfer_retry" => 3600 } },
            :srcList   => filelist,
            :dest      => '/',
            :rawArgs => [ '-P', '33001', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
            :use_aspera_key => true)
            # simulate call later, to check status
            sleep 2
            # (sample) get package status
            allpkg=api_files_user.read("packages",the_package['id'])[:data]
          when :recv
            loop do
              # list all packages ('page'=>1,'per_page'=>10,)'sort'=>'-sent_at',
              packages=api_files_user.list("packages",{'archived'=>false,'exclude_dropbox_packages'=>true,'has_content'=>true,'received'=>true,'workspace_id'=>workspace_id})[:data]
              # take the last one
              the_package=packages.first
              #  get node info
              node_info=api_files_user.read("nodes",the_package['node_id'])[:data]
              # get transfer auth
              node_bearer_token_xfer=api_files_oauth.get_authorization(self.class.node_scope(node_info['access_key'],@@SCOPE_NODE_USER))
              # download files
              @logger.info "starting transfer"
              @faspmanager.do_transfer(
              :retries   => 10,
              :mode      => :recv,
              :user      => 'xfer',
              :host      => node_info['host'],
              :token     => node_bearer_token_xfer,
              :tags      => { "aspera" => { "files" => { "package_id" => the_package['id'], "package_operation" => "download" }, "node" => { "access_key" => node_info['access_key'], "file_id" => the_package['contents_file_id'] }, "xfer_id" => xfer_id, "xfer_retry" => 3600 } },
              :srcList   => ['.'],
              :dest      => '.',#TODO:param?
              :rawArgs => [ '-P', '33001', '-q', '--ignore-host-key', '-k', '2', '--save-before-overwrite','--partial-file-suffix=.partial' ],
              :use_aspera_key => true)
              break if @loop.nil?
            end
          when :events
            api_files_admin=Rest.new(@logger,files_api_base_url,{:oauth=>api_files_oauth,:scope=>@@SCOPE_FILES_ADMIN})
            # page=1&per_page=10&q=type:(file_upload+OR+file_delete+OR+file_download+OR+file_rename+OR+folder_create+OR+folder_delete+OR+folder_share+OR+folder_share_via_public_link)&sort=-date
            events=api_files_admin.list('events',{'q'=>'type:(file_upload OR file_download)'})[:data]
            #@logger.info "events=#{JSON.generate(events)}"
            node_info=api_files_user.read("nodes",workspace_data['home_node_id'])[:data]
            # get access to node API, note the additional header
            api_node_admin=Rest.new(@logger,node_info['url'],{:oauth=>api_files_oauth,:scope=>self.class.node_scope(node_info['access_key'],@@SCOPE_NODE_ADMIN),:headers=>{'X-Aspera-AccessKey'=>node_info['access_key']}})
            # can add filters: tag=aspera.files.package_id%3DLA8OU3p8w
            #'tag'=>'aspera.files.package_id%3DJvbl0w-5A'
            # filter= 'id', 'short_summary', or 'summary'
            # count=nnn
            # tag=x.y.z%3Dvalue
            # iteration_token=nnn
            # active_only=true|false
            results=api_node_admin.list("ops/transfers",{'count'=>100,'filter'=>'summary','active_only'=>'true'}) #
            #transfers=api_node_admin.make_request_ex({:operation=>'GET',:subpath=>'ops/transfers',:args=>{'count'=>25,'filter'=>'id'}})
            #transfers=api_node_admin.list("events") # after_time=2016-05-01T23:53:09Z
          when :set_client_key
            the_client_id=OptParser.get_next_arg_value(argv,'client_id')
            the_private_key=OptParser.get_next_arg_value(argv,'private_key')
            api_files_admin=Rest.new(@logger,files_api_base_url,{:oauth=>api_files_oauth,:scope=>@@SCOPE_FILES_ADMIN})
            api_files_admin.update('clients',the_client_id,{:jwt_grant_enabled=>true, :public_key=>OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s})
          when :faspexgw
            require 'asperalm/faspex_gw'
            FaspexGW.set_vars(@logger,api_files_user,api_files_oauth)
            FaspexGW.go()
          when :admin
            api_files_admin=Rest.new(@logger,files_api_base_url,{:oauth=>api_files_oauth,:scope=>@@SCOPE_FILES_ADMIN})
            resource=OptParser.get_next_arg_from_list(argv,'resource',[:clients,:contacts,:dropboxes,:nodes,:operations,:packages,:saml_configurations])
            #:messages:organizations:url_tokens,:usage_reports:workspaces
            operation=OptParser.get_next_arg_from_list(argv,'operation',[:list])
            case operation
            when :list
              results=api_files_admin.list(resource.to_s)[:data]
            else
              raise RuntimeError, "unexpected value: #{resource}"
            end
          else
            raise RuntimeError, "unexpected value: #{command}"
          end # action

          if ! results.nil? then
            puts PP.pp(results,'')
          end

          auth_data[:bi].terminate if auth_data.has_key?(:bi)
        rescue OptionParser::InvalidArgument => e
          STDERR.puts "ERROR:".bg_red().gray()+" #{e}\n\n"
          opt_parser.exit_with_usage
        end
        return
      end
    end
  end # Cli
end # Asperalm
