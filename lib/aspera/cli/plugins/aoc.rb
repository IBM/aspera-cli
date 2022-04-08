# frozen_string_literal: true

require 'aspera/cli/plugins/node'
require 'aspera/cli/plugins/ats'
require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/transfer_agent'
require 'aspera/fasp/agent_node'
require 'aspera/fasp/transfer_spec'
require 'aspera/aoc'
require 'aspera/node'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'securerandom'
require 'date'

module Aspera
  module Cli
    module Plugins
      class Aoc < BasicAuthPlugin
        class << self
          def detect(base_url)
            api = Rest.new({base_url: base_url})
            # either in standard domain, or product name in page
            if URI.parse(base_url).host.end_with?(Aspera::AoC::PROD_DOMAIN) ||
                api.call({operation: 'GET', redirect_max: 1, headers: {'Accept' => 'text/html'}})[:http].body.include?(Aspera::AoC::PRODUCT_NAME)
              return {product: :aoc,version: 'SaaS' }
            end
            return nil
          end
        end
        # special value for package id
        VAL_ALL = 'ALL'
        ID_AK_ADMIN = 'ASPERA_ACCESS_KEY_ADMIN'

        def initialize(env)
          super(env)
          @default_workspace_id = nil
          @workspace_name = nil
          @workspace_id = nil
          @persist_ids = nil
          @home_node_file = nil
          @api_aoc = nil
          @url_token_data = nil
          @api_aoc = nil
          options.add_opt_list(:auth,Oauth::STD_AUTH_TYPES,'OAuth type of authentication')
          options.add_opt_list(:operation, %i[push pull],'client operation for transfers')
          options.add_opt_simple(:client_id,'OAuth API client identifier in application')
          options.add_opt_simple(:client_secret,'OAuth API client passcode')
          options.add_opt_simple(:redirect_uri,'OAuth API client redirect URI')
          options.add_opt_simple(:private_key,'OAuth JWT RSA private key PEM value (prefix file path with @val:@file:)')
          options.add_opt_simple(:workspace,'name of workspace')
          options.add_opt_simple(:name,'resource name')
          options.add_opt_simple(:path,'file or folder path')
          options.add_opt_simple(:link,'public link to shared resource')
          options.add_opt_simple(:new_user_option,'new user creation option')
          options.add_opt_simple(:from_folder,'share to share source folder')
          options.add_opt_simple(:scope,'OAuth scope for AoC API calls')
          options.add_opt_boolean(:bulk,'bulk operation')
          options.add_opt_boolean(:default_ports,'use standard FASP ports or get from node api')
          options.set_option(:bulk,:no)
          options.set_option(:default_ports,:yes)
          options.set_option(:new_user_option,{'package_contact' => true})
          options.set_option(:operation,:push)
          options.set_option(:auth,:jwt)
          options.set_option(:scope,AoC::SCOPE_FILES_USER)
          options.set_option(:private_key,'@file:' + env[:private_key_path]) if env[:private_key_path].is_a?(String)
          options.parse_options!
          AoC.use_standard_ports = options.get_option(:default_ports)
          return if env[:man_only]
        end

        def aoc_api
          if @api_aoc.nil?
            @api_aoc = AoC.new(aoc_params(AoC::API_V1))
            # add keychain for access key secrets
            @api_aoc.key_chain = @agents[:config]
          end
          return @api_aoc
        end

        # starts transfer using transfer agent
        def transfer_start(app,direction,node_file,ts_add)
          ts_add.deep_merge!(AoC.analytics_ts(app,direction,@workspace_id,@workspace_name))
          ts_add.deep_merge!(aoc_api.console_ts(app))
          return transfer.start(*aoc_api.tr_spec(app,direction,node_file,ts_add))
        end

        NODE4_COMMANDS = %i[browse find mkdir rename delete upload download transfer http_node_download v3 file bearer_token_node node_info].freeze

        def execute_node_gen4_command(command_repo,top_node_file)
          case command_repo
          when :bearer_token_node
            thepath = options.get_next_argument('path')
            node_file = aoc_api.resolve_node_file(top_node_file,thepath)
            node_api = aoc_api.get_node_api(node_file[:node_info], use_secret: false)
            return Main.result_status(node_api.oauth_token)
          when :node_info
            thepath = options.get_next_argument('path')
            node_file = aoc_api.resolve_node_file(top_node_file,thepath)
            node_api = aoc_api.get_node_api(node_file[:node_info], use_secret: false)
            return {type: :single_object,data: {
              url:      node_file[:node_info]['url'],
              username: node_file[:node_info]['access_key'],
              password: node_api.oauth_token,
              root_id:  node_file[:file_id]
            }}
          when :browse
            thepath = options.get_next_argument('path')
            node_file = aoc_api.resolve_node_file(top_node_file,thepath)
            node_api = aoc_api.get_node_api(node_file[:node_info])
            file_info = node_api.read("files/#{node_file[:file_id]}")[:data]
            if file_info['type'].eql?('folder')
              result = node_api.read("files/#{node_file[:file_id]}/files",options.get_option(:value,:optional))
              items = result[:data]
              self.format.display_status("Items: #{result[:data].length}/#{result[:http]['X-Total-Count']}")
            else
              items = [file_info]
            end
            return {type: :object_list,data: items,fields: %w[name type recursive_size size modified_time access_level]}
          when :find
            thepath = options.get_next_argument('path')
            node_file = aoc_api.resolve_node_file(top_node_file,thepath)
            test_block = Aspera::Node.file_matcher(options.get_option(:value,:optional))
            return {type: :object_list,data: aoc_api.find_files(node_file,test_block),fields: ['path']}
          when :mkdir
            thepath = options.get_next_argument('path')
            containing_folder_path = thepath.split(AoC::PATH_SEPARATOR)
            new_folder = containing_folder_path.pop
            node_file = aoc_api.resolve_node_file(top_node_file,containing_folder_path.join(AoC::PATH_SEPARATOR))
            node_api = aoc_api.get_node_api(node_file[:node_info])
            result = node_api.create("files/#{node_file[:file_id]}/files",{name: new_folder,type: :folder})[:data]
            return Main.result_status("created: #{result['name']} (id=#{result['id']})")
          when :rename
            thepath = options.get_next_argument('source path')
            newname = options.get_next_argument('new name')
            node_file = aoc_api.resolve_node_file(top_node_file,thepath)
            node_api = aoc_api.get_node_api(node_file[:node_info])
            result = node_api.update("files/#{node_file[:file_id]}",{name: newname})[:data]
            return Main.result_status("renamed #{thepath} to #{newname}")
          when :delete
            thepath = options.get_next_argument('path')
            return do_bulk_operation(thepath,'deleted','path') do |l_path|
              raise "expecting String (path), got #{l_path.class.name} (#{l_path})" unless l_path.is_a?(String)
              node_file = aoc_api.resolve_node_file(top_node_file,l_path)
              node_api = aoc_api.get_node_api(node_file[:node_info])
              result = node_api.delete("files/#{node_file[:file_id]}")[:data]
              {'path' => l_path}
            end
          when :transfer
            # client side is agent
            # server side is protocol server
            # in same workspace
            server_home_node_file = client_home_node_file = top_node_file
            # default is push
            case options.get_option(:operation,:mandatory)
            when :push
              client_tr_oper = Fasp::TransferSpec::DIRECTION_SEND
              client_folder = options.get_option(:from_folder,:mandatory)
              server_folder = transfer.destination_folder(client_tr_oper)
            when :pull
              client_tr_oper = Fasp::TransferSpec::DIRECTION_RECEIVE
              client_folder = transfer.destination_folder(client_tr_oper)
              server_folder = options.get_option(:from_folder,:mandatory)
            end
            client_node_file = aoc_api.resolve_node_file(client_home_node_file,client_folder)
            server_node_file = aoc_api.resolve_node_file(server_home_node_file,server_folder)
            # force node as transfer agent
            client_node_api = aoc_api.get_node_api(client_node_file[:node_info], use_secret: false)
            @agents[:transfer].agent_instance = Fasp::AgentNode.new({
              url:      client_node_api.params[:base_url],
              username: client_node_file[:node_info]['access_key'],
              password: client_node_api.oauth_token,
              root_id:  client_node_file[:file_id]
            })
            # additional node to node TS info
            add_ts = {
              'remote_access_key'   => server_node_file[:node_info]['access_key'],
              'destination_root_id' => server_node_file[:file_id],
              'source_root_id'      => client_node_file[:file_id]
            }
            return Main.result_transfer(transfer_start(AoC::FILES_APP,client_tr_oper,server_node_file,add_ts))
          when :upload
            node_file = aoc_api.resolve_node_file(top_node_file,transfer.destination_folder(Fasp::TransferSpec::DIRECTION_SEND))
            add_ts = {'tags' => {'aspera' => {'files' => {'parentCwd' => "#{node_file[:node_info]['id']}:#{node_file[:file_id]}"}}}}
            return Main.result_transfer(transfer_start(AoC::FILES_APP,Fasp::TransferSpec::DIRECTION_SEND,node_file,add_ts))
          when :download
            source_paths = transfer.ts_source_paths
            # special case for AoC : all files must be in same folder
            source_folder = source_paths.shift['source']
            # if a single file: split into folder and path
            if source_paths.empty?
              source_folder = source_folder.split(AoC::PATH_SEPARATOR)
              source_paths = [{'source' => source_folder.pop}]
              source_folder = source_folder.join(AoC::PATH_SEPARATOR)
            end
            node_file = aoc_api.resolve_node_file(top_node_file,source_folder)
            # override paths with just filename
            add_ts = {'tags' => {'aspera' => {'files' => {'parentCwd' => "#{node_file[:node_info]['id']}:#{node_file[:file_id]}"}}}}
            add_ts['paths'] = source_paths
            return Main.result_transfer(transfer_start(AoC::FILES_APP,Fasp::TransferSpec::DIRECTION_RECEIVE,node_file,add_ts))
          when :http_node_download
            source_paths = transfer.ts_source_paths
            source_folder = source_paths.shift['source']
            if source_paths.empty?
              source_folder = source_folder.split(AoC::PATH_SEPARATOR)
              source_paths = [{'source' => source_folder.pop}]
              source_folder = source_folder.join(AoC::PATH_SEPARATOR)
            end
            raise CliBadArgument,'one file at a time only in HTTP mode' if source_paths.length > 1
            file_name = source_paths.first['source']
            node_file = aoc_api.resolve_node_file(top_node_file,File.join(source_folder,file_name))
            node_api = aoc_api.get_node_api(node_file[:node_info])
            node_api.call(
              operation: 'GET',
              subpath: "files/#{node_file[:file_id]}/content",
              save_to_file: File.join(transfer.destination_folder(Fasp::TransferSpec::DIRECTION_RECEIVE),file_name))
            return Main.result_status("downloaded: #{file_name}")
          when :v3
            # Note: other common actions are unauthorized with user scope
            command_legacy = options.get_next_command(Node::SIMPLE_ACTIONS)
            # TODO: shall we support all methods here ? what if there is a link ?
            node_api = aoc_api.get_node_api(top_node_file[:node_info])
            return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: node_api)).execute_action(command_legacy)
          when :file
            command_node_file = options.get_next_command(%i[show permission modify])
            file_path = options.get_option(:path,:optional)
            node_file =
              if !file_path.nil?
                aoc_api.resolve_node_file(top_node_file,file_path) # TODO: allow follow link ?
              else
                {node_info: top_node_file[:node_info],file_id: instance_identifier}
              end
            node_api = aoc_api.get_node_api(node_file[:node_info])
            case command_node_file
            when :show
              items = node_api.read("files/#{node_file[:file_id]}")[:data]
              return {type: :single_object,data: items}
            when :modify
              update_param = options.get_next_argument('update data (Hash)')
              res = node_api.update("files/#{node_file[:file_id]}",update_param)[:data]
              return {type: :single_object,data: res}
            when :permission
              command_perm = options.get_next_command(%i[list create])
              case command_perm
              when :list
                # generic options : TODO: as arg ? option_url_query
                list_options ||= {'include' => ['[]','access_level','permission_count']}
                # special value: ALL will show all permissions
                if !VAL_ALL.eql?(node_file[:file_id])
                  # add which one to get
                  list_options['file_id'] = node_file[:file_id]
                  list_options['inherited'] ||= false
                end
                items = node_api.read('permissions',list_options)[:data]
                return {type: :object_list,data: items}
              when :create
                #create_param=self.options.get_next_argument('creation data (Hash)')
                set_workspace_info
                access_id = "#{ID_AK_ADMIN}_WS_#{@workspace_id}"
                node_file[:node_info]
                params = {
                  'file_id'       => node_file[:file_id], # mandatory
                  'access_type'   => 'user', # mandatory: user or group
                  'access_id'     => access_id, # id of user or group
                  'access_levels' => Aspera::Node::ACCESS_LEVELS,
                  'tags'          => {'aspera' => {'files' => {'workspace' => {
                    'id'                => @workspace_id,
                    'workspace_name'    => @workspace_name,
                    'user_name'         => aoc_api.user_info['name'],
                    'shared_by_user_id' => aoc_api.user_info['id'],
                    'shared_by_name'    => aoc_api.user_info['name'],
                    'shared_by_email'   => aoc_api.user_info['email'],
                    'shared_with_name'  => access_id,
                    'access_key'        => node_file[:node_info]['access_key'],
                    'node'              => node_file[:node_info]['name']}}}}}
                item = node_api.create('permissions',params)[:data]
                return {type: :single_object,data: item}
              else raise "internal error:shall not reach here (#{command_perm})"
              end
            else raise "internal error:shall not reach here (#{command_node_file})"
            end
          end # command_repo
          raise 'ERR'
        end # execute_node_gen4_command
        AOC_PARAMS_COPY=%i[link url auth client_id client_secret scope redirect_uri private_key username password].freeze
        # build constructor option list for AoC based on options of CLI
        def aoc_params(subpath)
          # copy command line options to args
          opt = AOC_PARAMS_COPY.each_with_object({}){|i,m|m[i] = options.get_option(i,:optional);}
          opt[:subpath] = subpath
          return opt
        end

        # initialize apis and authentication
        # set:
        # @default_workspace_id
        # @workspace_name
        # @workspace_id
        # @persist_ids
        # returns nil
        def set_workspace_info
          @url_token_data = aoc_api.url_token_data
          if @url_token_data.nil?
            @default_workspace_id = aoc_api.user_info['default_workspace_id']
            @persist_ids = [aoc_api.user_info['id']]
          else
            @default_workspace_id = @url_token_data['data']['workspace_id']
            @persist_ids = [] # TODO : @url_token_data['id'] ?
          end

          ws_name = options.get_option(:workspace,:optional)
          if ws_name.nil?
            Log.log.debug('using default workspace'.green)
            if @default_workspace_id.eql?(nil)
              raise CliError,'no default workspace defined for user, please specify workspace'
            end
            # get default workspace
            @workspace_id = @default_workspace_id
          else
            # lookup another workspace
            wss = aoc_api.read('workspaces',{'q' => ws_name})[:data]
            wss = wss.select { |i| i['name'].eql?(ws_name) }
            case wss.length
            when 0
              raise CliBadArgument,"no such workspace: #{ws_name}"
            when 1
              @workspace_id = wss.first['id']
            else
              raise 'multiple match for workspace'
            end
          end
          @workspace_data = aoc_api.read("workspaces/#{@workspace_id}")[:data]
          Log.log.debug("workspace_id=#{@workspace_id},@workspace_data=#{@workspace_data}".red)

          @workspace_name ||= @workspace_data['name']
          Log.log.info('current workspace is ' + @workspace_name.red)

          # display workspace
          self.format.display_status("Current Workspace: #{@workspace_name.red}#{@workspace_id == @default_workspace_id ? ' (default)' : ''}")
          return nil
        end

        # @home_node_file (hash with :node_info and :file_id)
        def set_home_node_file
          if !@url_token_data.nil?
            assert_public_link_types(['view_shared_file'])
            home_node_id = @url_token_data['data']['node_id']
            home_file_id = @url_token_data['data']['file_id']
          end
          home_node_id ||= @workspace_data['home_node_id'] || @workspace_data['node_id']
          home_file_id ||= @workspace_data['home_file_id']
          raise 'Cannot get users home node id' if home_node_id.to_s.empty?
          @home_node_file = {
            node_info: aoc_api.read("nodes/#{home_node_id}")[:data],
            file_id:   home_file_id
          }
          aoc_api.check_get_node_file(@home_node_file)

          return nil
        end

        def do_bulk_operation(ids_or_one,success_msg,id_result='id')
          raise 'missing block' unless block_given?
          ids_or_one = [ids_or_one] unless options.get_option(:bulk)
          raise 'expecting Array' unless ids_or_one.is_a?(Array)
          result_list = []
          ids_or_one.each do |id|
            one = {id_result => id}
            begin
              res = yield(id)
              one = res if id.is_a?(Hash) # if block returns a has, let's use this
              one['status'] = success_msg
            rescue StandardError => e
              one['status'] = e.to_s
            end
            result_list.push(one)
          end
          return {type: :object_list,data: result_list,fields: [id_result,'status']}
        end

        # get identifier or name from command line
        # @return identifier
        def get_resource_id_from_args(resource_class_path)
          l_res_id = options.get_option(:id)
          l_res_name = options.get_option(:name)
          raise 'Provide either option id or name, not both' unless l_res_id.nil? || l_res_name.nil?
          # try to find item by name (single partial match or exact match)
          l_res_id = aoc_api.lookup_entity_by_name(resource_class_path,l_res_name)['id'] unless l_res_name.nil?
          # if no name or id option, taken on command line (after command)
          if l_res_id.nil?
            l_res_id = options.get_next_argument('identifier')
            l_res_id = aoc_api.lookup_entity_by_name(resource_class_path,options.get_next_argument('identifier'))['id'] if l_res_id.eql?('name')
          end
          return l_res_id
        end

        def get_resource_path_from_args(resource_class_path)
          return "#{resource_class_path}/#{get_resource_id_from_args(resource_class_path)}"
        end

        # package creation params can give just email, and full hash is created
        def resolve_package_recipients(package_data,recipient_list_field)
          return unless package_data.has_key?(recipient_list_field)
          raise CliBadArgument,"#{recipient_list_field} must be an Array" unless package_data[recipient_list_field].is_a?(Array)
          new_user_option = options.get_option(:new_user_option,:mandatory)
          # list with resolved elements
          resolved_list = []
          package_data[recipient_list_field].each do |short_recipient_info|
            case short_recipient_info
            when Hash # native api information, check keys
              raise "#{recipient_list_field} element shall have fields: id and type" unless short_recipient_info.keys.sort.eql?(%w[id type])
            when String # need to resolve name to type/id
              # email: user, else dropbox
              entity_type = short_recipient_info.include?('@') ? 'contacts' : 'dropboxes'
              begin
                full_recipient_info = aoc_api.lookup_entity_by_name(entity_type,short_recipient_info,{'current_workspace_id' => @workspace_id})
              rescue RuntimeError => e
                raise e unless e.message.eql?('not found')
                raise "no such shared inbox in workspace #{@workspace_name}" unless entity_type.eql?('contacts')
                full_recipient_info = aoc_api.create('contacts',{'current_workspace_id' => @workspace_id,'email' => short_recipient_info}.merge(new_user_option))[:data]
              end
              short_recipient_info = if entity_type.eql?('dropboxes')
                {'id' => full_recipient_info['id'],'type' => 'dropbox'}
              else
                {'id' => full_recipient_info['source_id'],'type' => full_recipient_info['source_type']}
              end
            else # unexpected extended value, must be String or Hash
              raise "#{recipient_list_field} item must be a String (email, shared inbox) or Hash (id,type)"
            end # type of recipient info
            # add original or resolved recipient info
            resolved_list.push(short_recipient_info)
          end
          # replace with resolved elements
          package_data[recipient_list_field] = resolved_list
        end

        def normalize_metadata(pkg_data)
          case pkg_data['metadata']
          when Array,NilClass then return
          when Hash
            api_meta = []
            pkg_data['metadata'].each do |k,v|
              api_meta.push({
                #'input_type' => 'single-dropdown',
                'name'   => k,
                'values' => v.is_a?(Array) ? v : [v]
              })
            end
            pkg_data['metadata'] = api_meta
          else raise "metadata field if not of expected type: #{pkg_meta.class}"
          end
          nil
        end

        # private
        def option_url_query(default)
          query = options.get_option(:query,:optional)
          query = default if query.nil?
          Log.log.debug("Query=#{query}".bg_red)
          begin
            # check it is suitable
            URI.encode_www_form(query) unless query.nil?
          rescue StandardError => e
            raise CliBadArgument,"query must be an extended value which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
          end
          return query
        end

        def assert_public_link_types(expected)
          raise CliBadArgument,"public link type is #{@url_token_data['purpose']} but action requires one of #{expected.join(',')}" \
          unless expected.include?(@url_token_data['purpose'])
        end
        KNOWN_AOC_RES=%i[self organization user group client contact dropbox node operation package saml_configuration
                         workspace dropbox_membership short_link workspace_membership application client_registration_token client_access_key kms_profile].freeze

        # Call aoc_api.read with same parameters.
        # Use paging if necessary to get all results
        def read_with_paging(resource_class_path,base_query)
          raise 'Query must be Hash' unless base_query.is_a?(Hash)
          # set default large page if user does not specify own parameters. AoC Caps to 1000 anyway
          base_query['per_page'] = 1000 unless base_query.has_key?('per_page')
          max_items = base_query[MAX_ITEMS]
          base_query.delete(MAX_ITEMS)
          max_pages = base_query[MAX_PAGES]
          base_query.delete(MAX_PAGES)
          item_list = []
          total_count = nil
          current_page = base_query['page']
          current_page = 1 if current_page.nil?
          page_count = 0
          loop do
            query = base_query.clone
            query['page'] = current_page
            result = aoc_api.read(resource_class_path,query)
            total_count = result[:http]['X-Total-Count']
            page_count += 1
            current_page += 1
            add_items = result[:data]
            break if add_items.empty?
            # append new items to full list
            item_list += add_items
            break if !max_pages.nil? && page_count > max_pages
            break if !max_items.nil? && item_list.count > max_items
          end
          return item_list,total_count
        end

        def execute_admin_action
          # upgrade scope to admin
          aoc_api.oauth.params[:scope] = AoC::SCOPE_FILES_ADMIN
          command_admin = options.get_next_command(%i[ats resource usage_reports analytics subscription auth_providers])
          case command_admin
          when :auth_providers
            command_auth_prov = options.get_next_command(%i[list update])
            case command_auth_prov
            when :list
              providers = aoc_api.read('admin/auth_providers')[:data]
              return {type: :object_list,data: providers}
            when :update
              raise 'not implemented'
            end
          when :subscription
            org = aoc_api.read('organization')[:data]
            bss_api = AoC.new(aoc_params('bss/platform'))
            graphql_query = "
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
            result = bss_api.create('graphql',{'variables' => {'organization_id' => org['id']},'query' => graphql_query})[:data]['data']
            return {type: :single_object,data: result['aoc']['bssSubscription']}
          when :ats
            ats_api = Rest.new(aoc_api.params.deep_merge({
              base_url: aoc_api.params[:base_url] + '/admin/ats/pub/v1',
              auth:     {scope: AoC::SCOPE_FILES_ADMIN_USER}
            }))
            return Ats.new(@agents).execute_action_gen(ats_api)
          when :analytics
            analytics_api = Rest.new(aoc_api.params.deep_merge({
              base_url: aoc_api.params[:base_url].gsub('/api/v1','') + '/analytics/v2',
              auth:     {scope: AoC::SCOPE_FILES_ADMIN_USER}
            }))
            command_analytics = options.get_next_command(%i[application_events transfers])
            case command_analytics
            when :application_events
              event_type = command_analytics.to_s
              events = analytics_api.read("organizations/#{aoc_api.user_info['organization_id']}/#{event_type}")[:data][event_type]
              return {type: :object_list,data: events}
            when :transfers
              event_type = command_analytics.to_s
              filter_resource = options.get_option(:name,:optional) || 'organizations'
              filter_id = options.get_option(:id,:optional) ||
              case filter_resource
              when 'organizations' then aoc_api.user_info['organization_id']
              when 'users' then aoc_api.user_info['id']
              when 'nodes' then aoc_api.user_info['id'] # TODO: consistent ? # rubocop:disable Lint/DuplicateBranch
              else raise 'organizations or users for option --name'
              end
              filter = options.get_option(:query,:optional) || {}
              raise 'query must be Hash' unless filter.is_a?(Hash)
              filter['limit'] ||= 100
              if options.get_option(:once_only,:mandatory)
                saved_date = []
                startdate_persistency = PersistencyActionOnce.new(
                  manager: @agents[:persistency],
                  data: saved_date,
                  ids: IdGenerator.from_list(['aoc_ana_date',options.get_option(:url,:mandatory),@workspace_name].push(filter_resource,filter_id)))
                start_datetime = saved_date.first
                stop_datetime = Time.now.utc.strftime('%FT%T.%LZ')
                #Log.log().error("start: #{start_datetime}")
                #Log.log().error("end:   #{stop_datetime}")
                saved_date[0] = stop_datetime
                filter['start_time'] = start_datetime unless start_datetime.nil?
                filter['stop_time'] = stop_datetime
              end
              events = analytics_api.read("#{filter_resource}/#{filter_id}/#{event_type}",option_url_query(filter))[:data][event_type]
              startdate_persistency&.save
              if !options.get_option(:notif_to,:optional).nil?
                events.each do |tr_event|
                  config.send_email_template({ev: tr_event})
                end
              end
              return {type: :object_list,data: events}
            end
          when :resource
            resource_type = options.get_next_argument('resource',expected: KNOWN_AOC_RES)
            # get path on API, resource type is singular, but api is plural
            resource_class_path =
              case resource_type
              # special cases: singleton, in admin, with x
              when :self,:organization then resource_type
              when :client_registration_token,:client_access_key then "admin/#{resource_type}s"
              when :application then 'admin/apps_new'
              when :dropbox then resource_type.to_s + 'es'
              when :kms_profile then "integrations/#{resource_type}s"
              else "#{resource_type}s"
              end
            # build list of supported operations
            singleton_object = %i[self organization].include?(resource_type)
            global_operations =  %i[create list]
            supported_operations = %i[show modify]
            supported_operations.push(:delete,*global_operations) unless singleton_object
            supported_operations.push(:v4,:v3) if resource_type.eql?(:node)
            supported_operations.push(:set_pub_key) if resource_type.eql?(:client)
            supported_operations.push(:shared_folder) if resource_type.eql?(:workspace)
            command = options.get_next_command(supported_operations)
            # require identifier for non global commands
            if !singleton_object && !global_operations.include?(command)
              res_id = get_resource_id_from_args(resource_class_path)
              resource_instance_path = "#{resource_class_path}/#{res_id}"
            end
            resource_instance_path = resource_class_path if singleton_object
            case command
            when :create
              id_result = 'id'
              id_result = 'token' if resource_class_path.eql?('admin/client_registration_tokens')
              # TODO: report inconsistency: creation url is !=, and does not return id.
              resource_class_path = 'admin/client_registration/token' if resource_class_path.eql?('admin/client_registration_tokens')
              list_or_one = options.get_next_argument('creation data (Hash)')
              return do_bulk_operation(list_or_one,'created',id_result) do |params|
                raise 'expecting Hash' unless params.is_a?(Hash)
                aoc_api.create(resource_class_path,params)[:data]
              end
            when :list
              default_fields = ['id']
              default_query = {}
              case resource_type
              when :application then default_query = {organization_apps: true};
                                     default_fields.push('app_type','app_name','available','direct_authorizations_allowed','workspace_authorizations_allowed')
              when :client,:client_access_key,:dropbox,:group,:package,:saml_configuration,:workspace then default_fields.push('name')
              when :client_registration_token then default_fields.push('value','data.client_subject_scopes','created_at')
              when :contact then default_fields = %w[email name source_id source_type]
              when :node then default_fields.push('name','host','access_key')
              when :operation then default_fields = nil
              when :short_link then default_fields.push('short_url','data.url_token_data.purpose')
              when :user then default_fields.push('name','email')
              end
              item_list,total_count = read_with_paging(resource_class_path,option_url_query(default_query))
              count_msg = "Items: #{item_list.length}/#{total_count}"
              count_msg = count_msg.bg_red unless item_list.length.eql?(total_count.to_i)
              self.format.display_status(count_msg)
              return {type: :object_list,data: item_list,fields: default_fields}
            when :show
              object = aoc_api.read(resource_instance_path)[:data]
              fields = object.keys.reject{|k|k.eql?('certificate')}
              return { type: :single_object, data: object, fields: fields }
            when :modify
              changes = options.get_next_argument('modified parameters (hash)')
              aoc_api.update(resource_instance_path,changes)
              return Main.result_status('modified')
            when :delete
              return do_bulk_operation(res_id,'deleted') do |one_id|
                aoc_api.delete("#{resource_class_path}/#{one_id}")
                {'id' => one_id}
              end
            when :set_pub_key
              # special : reads private and generate public
              the_private_key = options.get_next_argument('private_key')
              the_public_key = OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s
              aoc_api.update(resource_instance_path,{jwt_grant_enabled: true, public_key: the_public_key})
              return Main.result_success
            when :v3,:v4
              res_data = aoc_api.read(resource_instance_path)[:data]
              api_node = aoc_api.get_node_api(res_data)
              return Node.new(@agents.merge(skip_basic_auth_options: true, node_api: api_node)).execute_action if command.eql?(:v3)
              ak_data = api_node.call({operation: 'GET',subpath: "access_keys/#{res_data['access_key']}",headers: {'Accept' => 'application/json'}})[:data]
              command_repo = options.get_next_command(NODE4_COMMANDS)
              return execute_node_gen4_command(command_repo,{node_info: res_data, file_id: ak_data['root_file_id']})
            when :shared_folder
              command_shared = options.get_next_command(%i[list create member delete])
              # generic permission created for each shared folder
              access_id = "#{ID_AK_ADMIN}_WS_#{res_id}"
              case command_shared
              when :list
                query=options.get_option(:query,:optional)
                query={'admin' => true, 'access_id' => access_id, 'access_type' => 'user'} if query.nil?
                res_data = aoc_api.read("#{resource_instance_path}/permissions",query)[:data]
                return { type: :object_list, data: res_data, fields: %w[id node_id file_id node_name file.path tags.aspera.files.workspace.share_as access_id]}
              when :member
                #https://sedemo.ibmaspera.com/api/v1/node/8669/permissions_and_members/3270?inherited=false&aspera-node-basic=8669&admin=true&page=1&per_page=25
              when :delete
                aoc_api.delete("#{resource_class_path}/#{one_id}")
              when :create
                # workspace information
                ws_info = aoc_api.read(resource_instance_path)[:data]
                shared_create_data = options.get_next_argument('creation data',type: Hash)
                # node is either provided by user, or by default the one of workspace
                node_id = shared_create_data.has_key?('node_id') ? shared_create_data['node_id'] : ws_info['node_id']
                # remove from creation data if present, as it is not a standard argument
                shared_create_data.delete('node_id')
                raise 'missing node information: path' unless shared_create_data.has_key?('path')
                folder_path=shared_create_data['path']
                shared_create_data.delete('path')
                node_file={node_info: aoc_api.read("nodes/#{node_id}")[:data], file_id: 1}
                node_file = aoc_api.resolve_node_file(node_file,folder_path)
                access_id = "#{ID_AK_ADMIN}_WS_#{ws_info['id']}"
                # use can specify: tags.aspera.files.workspace.share_as  to  File.basename(folder_path)
                default_create_data = {
                  'file_id'       => node_file[:file_id],
                  'access_type'   => 'user',
                  'access_id'     => access_id,
                  'access_levels' => %w[list read write delete mkdir rename preview],
                  'tags'          => {'aspera' => {'files' => {'workspace' => {
                    'id'                => ws_info['id'],
                    'workspace_name'    => ws_info['name'],
                    'user_name'         => aoc_api.user_info['name'],
                    'shared_by_user_id' => aoc_api.user_info['id'],
                    'shared_by_name'    => aoc_api.user_info['name'],
                    'shared_by_email'   => aoc_api.user_info['email'],
                    'shared_with_name'  => access_id,
                    'access_key'        => node_file[:node_info]['access_key'],
                    'node'              => node_file[:node_info]['name']}
                }}}}
                shared_create_data = default_create_data.deep_merge(default_create_data) # ?aspera-node-basic=#{node_id}&aspera-node-prefer-basic=#{node_id}
                return { type: :single_object, data: aoc_api.create("node/#{node_id}/permissions",shared_create_data)}
              end
            else raise 'unknown command'
            end
          when :usage_reports
            return {type: :object_list,data: aoc_api.read('usage_reports',{workspace_id: @workspace_id})[:data]}
          end
        end

        # must be public
        ACTIONS = %i[reminder servers bearer_token organization tier_restrictions user packages files admin automation gateway].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :reminder
            # send an email reminder with list of orgs
            user_email = options.get_option(:username,:mandatory)
            Rest.new(base_url: "#{AoC.api_base_url}/#{AoC::API_V1}").create('organization_reminders',{email: user_email})[:data]
            return Main.result_status("List of organizations user is member of, has been sent by e-mail to #{user_email}")
          when :servers
            return {type: :object_list,data: Rest.new(base_url: "#{AoC.api_base_url}/#{AoC::API_V1}").read('servers')[:data]}
          when :bearer_token
            return {type: :text,data: aoc_api.oauth_token}
          when :organization
            return { type: :single_object, data: aoc_api.read('organization')[:data] }
          when :tier_restrictions
            return { type: :single_object, data: aoc_api.read('tier_restrictions')[:data] }
          when :user
            case options.get_next_command(%i[workspaces profile])
            # when :settings
            # return {type: :object_list,data: aoc_api.read('client_settings/')[:data]}
            when :workspaces
              case options.get_next_command(%i[list current])
              when :list
                return {type: :object_list,data: aoc_api.read('workspaces')[:data],fields: %w[id name]}
              when :current
                set_workspace_info
                return { type: :single_object, data: @workspace_data }
              end
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: aoc_api.user_info }
              when :modify
                aoc_api.update("users/#{aoc_api.user_info['id']}",options.get_next_argument('modified parameters (hash)'))
                return Main.result_status('modified')
              end
            end
          when :packages
            set_workspace_info if @url_token_data.nil?
            case options.get_next_command(%i[shared_inboxes send recv list show delete])
            when :shared_inboxes
              case options.get_next_command(%i[list show])
              when :list
                query = option_url_query(nil)
                if query.nil?
                  query = {'embed[]' => 'dropbox','workspace_id' => @workspace_id,'aggregate_permissions_by_dropbox' => true,'sort' => 'dropbox_name'}
                end
                return {type: :object_list,data: aoc_api.read('dropbox_memberships',query)[:data],fields: ['dropbox_id','dropbox.name']}
              when :show
                return {type: :single_object,data: aoc_api.read(get_resource_path_from_args('dropboxes'),query)[:data]}
              end
            when :send
              package_data = options.get_option(:value,:mandatory)
              raise CliBadArgument,'value must be hash, refer to doc' unless package_data.is_a?(Hash)

              if !@url_token_data.nil?
                assert_public_link_types(%w[send_package_to_user send_package_to_dropbox])
                box_type = @url_token_data['purpose'].split('_').last
                package_data['recipients'] = [{'id' => @url_token_data['data']["#{box_type}_id"],'type' => box_type}]
                @workspace_id = @url_token_data['data']['workspace_id']
              end

              package_data['workspace_id'] = @workspace_id

              # list of files to include in package, optional
              #package_data['file_names']=self.transfer.ts_source_paths.map{|i|File.basename(i['source'])}

              # lookup users
              resolve_package_recipients(package_data,'recipients')
              resolve_package_recipients(package_data,'bcc_recipients')
              normalize_metadata(package_data)

              #  create a new package container
              package_info = aoc_api.create('packages',package_data)[:data]

              #  get node information for the node on which package must be created
              node_info = aoc_api.read("nodes/#{package_info['node_id']}")[:data]

              # tell AoC what to expect in package: 1 transfer (can also be done after transfer)
              # TODO: if multisession was used we should probably tell
              # also, currently no "multi-source" , i.e. only from client-side files, unless "node" agent is used
              aoc_api.update("packages/#{package_info['id']}",{'sent' => true,'transfers_expected' => 1})[:data]

              # get destination: package folder
              node_file = {node_info: node_info, file_id: package_info['contents_file_id']}
              # execute transfer, raise exception if at least one error
              Main.result_transfer(transfer_start(AoC::PACKAGES_APP,Fasp::TransferSpec::DIRECTION_SEND,node_file,AoC.package_tags(package_info,'upload')))
              # return all info on package
              return { type: :single_object, data: package_info}
            when :recv
              if !@url_token_data.nil?
                assert_public_link_types(['view_received_package'])
                options.set_option(:id,@url_token_data['data']['package_id'])
              end
              # scalar here
              ids_to_download = instance_identifier
              skip_ids_data = []
              skip_ids_persistency = nil
              if options.get_option(:once_only,:mandatory)
                skip_ids_persistency = PersistencyActionOnce.new(
                  manager: @agents[:persistency],
                  data: skip_ids_data,
                  id: IdGenerator.from_list(['aoc_recv',options.get_option(:url,:mandatory),@workspace_id].push(*@persist_ids)))
              end
              if ids_to_download.eql?(VAL_ALL)
                # get list of packages in inbox
                package_info = aoc_api.read('packages',{
                  'archived'                 => false,
                  'exclude_dropbox_packages' => true,
                  'has_content'              => true,
                  'received'                 => true,
                  'workspace_id'             => @workspace_id})[:data]
                # remove from list the ones already downloaded
                ids_to_download = package_info.map{|e|e['id']}
                # array here
                ids_to_download.reject!{|id|skip_ids_data.include?(id)}
              end # ALL
              # list here
              ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
              result_transfer = []
              self.format.display_status("found #{ids_to_download.length} package(s).")
              ids_to_download.each do |package_id|
                package_info = aoc_api.read("packages/#{package_id}")[:data]
                node_info = aoc_api.read("nodes/#{package_info['node_id']}")[:data]
                self.format.display_status("downloading package: #{package_info['name']}")
                add_ts = {'paths' => [{'source' => '.'}]}
                node_file = {node_info: node_info, file_id: package_info['contents_file_id']}
                statuses = transfer_start(AoC::PACKAGES_APP,Fasp::TransferSpec::DIRECTION_RECEIVE,node_file,AoC.package_tags(package_info,'download').merge(add_ts))
                result_transfer.push({'package' => package_id,Main::STATUS_FIELD => statuses})
                # update skip list only if all transfer sessions completed
                if TransferAgent.session_status(statuses).eql?(:success)
                  skip_ids_data.push(package_id)
                  skip_ids_persistency&.save
                end
              end
              return Main.result_transfer_multiple(result_transfer)
            when :show
              package_id = options.get_next_argument('package ID')
              package_info = aoc_api.read("packages/#{package_id}")[:data]
              return { type: :single_object, data: package_info }
            when :list
              query = option_url_query({'archived' => false,'exclude_dropbox_packages' => true,'has_content' => true,'received' => true})
              if query.has_key?('dropbox_name')
                # convenience: specify name instead of id
                raise 'not both dropbox_name and dropbox_id' if query.has_key?('dropbox_id')
                query['dropbox_id'] = aoc_api.lookup_entity_by_name('dropboxes',query['dropbox_name'])['id']
                query.delete('dropbox_name')
              end
              raise 'option must be Hash' unless query.is_a?(Hash)
              query['workspace_id'] ||= @workspace_id
              packages = aoc_api.read('packages',query)[:data]
              return {type: :object_list,data: packages,fields: %w[id name bytes_transferred]}
            when :delete
              list_or_one = instance_identifier
              return do_bulk_operation(list_or_one,'deleted') do |id|
                raise 'expecting String identifier' unless id.is_a?(String) || id.is_a?(Integer)
                aoc_api.delete("packages/#{id}")[:data]
              end
            end
          when :files
            # get workspace related information
            set_workspace_info
            set_home_node_file
            command_repo = options.get_next_command([NODE4_COMMANDS,:short_link].flatten)
            case command_repo
            when *NODE4_COMMANDS then return execute_node_gen4_command(command_repo,@home_node_file)
            when :short_link
              folder_dest = options.get_option(:to_folder,:optional)
              value_option = options.get_option(:value,:optional)
              case value_option
              when 'public'  then value_option = {'purpose' => 'token_auth_redirection'}
              when 'private' then value_option = {'purpose' => 'shared_folder_auth_link'}
              when NilClass,Hash then nil # keep value
              else raise 'value must be either: public, private, Hash or nil'
              end
              create_params = nil
              node_file = nil
              if !folder_dest.nil?
                node_file = aoc_api.resolve_node_file(@home_node_file,folder_dest)
                create_params = {
                  file_id:      node_file[:file_id],
                  node_id:      node_file[:node_info]['id'],
                  workspace_id: @workspace_id
                }
              end
              if !value_option.nil? && !create_params.nil?
                case value_option['purpose']
                when 'shared_folder_auth_link'
                  value_option['data'] = create_params
                  value_option['user_selected_name'] = nil
                when 'token_auth_redirection'
                  create_params['name'] = ''
                  value_option['data'] = {
                    aoc:            true,
                    url_token_data: {
                      data:    create_params,
                      purpose: 'view_shared_file'
                    }
                  }
                  value_option['user_selected_name'] = nil
                else
                  raise 'purpose must be one of: token_auth_redirection or shared_folder_auth_link'
                end
                options.set_option(:value,value_option)
              end
              result = entity_action(@api_aoc,'short_links',id_default: 'self')
              if result[:data].is_a?(Hash) && result[:data].has_key?('created_at') && result[:data]['resource_type'].eql?('UrlToken')
                node_api = aoc_api.get_node_api(node_file[:node_info])
                # TODO: access level as arg
                access_levels = Aspera::Node::ACCESS_LEVELS #['delete','list','mkdir','preview','read','rename','write']
                perm_data = {
                  'file_id'       => node_file[:file_id],
                  'access_type'   => 'user',
                  'access_id'     => result[:data]['resource_id'],
                  'access_levels' => access_levels,
                  'tags'          => {
                    'url_token'        => true,
                    'workspace_id'     => @workspace_id,
                    'workspace_name'   => @workspace_name,
                    'folder_name'      => 'my folder',
                    'created_by_name'  => aoc_api.user_info['name'],
                    'created_by_email' => aoc_api.user_info['email'],
                    'access_key'       => node_file[:node_info]['access_key'],
                    'node'             => node_file[:node_info]['host']
                  }
                }
                node_api.create("permissions?file_id=#{node_file[:file_id]}",perm_data)
                # TODO: event ?
              end
              return result
            end # files command
            throw('Error: shall not reach this line')
          when :automation
            Log.log.warn('BETA: work under progress')
            # automation api is not in the same place
            automation_rest_params = aoc_api.params.clone
            automation_rest_params[:base_url].gsub!('/api/','/automation/')
            automation_api = Rest.new(automation_rest_params)
            command_automation = options.get_next_command(%i[workflows instances])
            case command_automation
            when :instances
              return entity_action(@api_aoc,'workflow_instances')
            when :workflows
              wf_command = options.get_next_command([Plugin::ALL_OPS,:action,:launch].flatten)
              case wf_command
              when *Plugin::ALL_OPS
                return entity_command(wf_command,automation_api,'workflows',id_default: :id)
              when :launch
                wf_id = instance_identifier
                data = automation_api.create("workflows/#{wf_id}/launch",{})[:data]
                return {type: :single_object,data: data}
              when :action
                #TODO: not complete
                wf_id = instance_identifier
                wf_action_cmd = options.get_next_command(%i[list create show])
                Log.log.warn("Not implemented: #{wf_action_cmd}")
                step = automation_api.create('steps',{'workflow_id' => wf_id})[:data]
                automation_api.update("workflows/#{wf_id}",{'step_order' => [step['id']]})
                action = automation_api.create('actions',{'step_id' => step['id'],'type' => 'manual'})[:data]
                automation_api.update("steps/#{step['id']}",{'action_order' => [action['id']]})
                wf = automation_api.read("workflows/#{wf_id}")[:data]
                return {type: :single_object,data: wf}
              end
            end
          when :admin
            return execute_admin_action
          when :gateway
            set_workspace_info
            require 'aspera/faspex_gw'
            FaspexGW.new(@api_aoc,@workspace_id).start_server
          else
            raise "internal error: #{command}"
          end # action
          raise 'internal error: command shall return'
        end

        private :aoc_params,:set_workspace_info,:set_home_node_file,:do_bulk_operation,:resolve_package_recipients,:option_url_query,:assert_public_link_types,
          :execute_admin_action
        private_constant :VAL_ALL,:NODE4_COMMANDS, :ID_AK_ADMIN
      end # AoC
    end # Plugins
  end # Cli
end # Aspera
