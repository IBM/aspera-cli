# frozen_string_literal: true

require 'aspera/cli/plugins/oauth'
require 'aspera/cli/plugins/node'
require 'aspera/cli/plugins/ats'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/special_values'
require 'aspera/cli/wizard'
require 'aspera/agent/node'
require 'aspera/transfer/spec'
require 'aspera/api/aoc'
require 'aspera/api/node'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/assert'
require 'securerandom'
require 'date'

module Aspera
  module Cli
    module Plugins
      class Aoc < Oauth
        # default redirect for AoC web auth
        REDIRECT_LOCALHOST = 'http://localhost:12345'
        # admin objects that can be manipulated
        ADMIN_OBJECTS = %i[
          self
          organization
          user
          group
          group_membership
          client
          contact
          dropbox
          node
          operation
          package
          saml_configuration
          workspace
          workspace_membership
          dropbox_membership
          short_link
          application
          client_registration_token
          client_access_key
          kms_profile
        ].freeze
        # query to list fully received packages
        PACKAGE_RECEIVED_BASE_QUERY = {
          'archived'    => false,
          'has_content' => true,
          'received'    => true,
          'completed'   => true
        }.freeze
        PACKAGE_LIST_DEFAULT_FIELDS = %w[id name created_at files_completed bytes_transferred].freeze
        # options and parameters for Api::AoC.new
        OPTIONS_NEW = %i[url auth client_id client_secret scope redirect_uri private_key passphrase username password workspace].freeze

        private_constant :REDIRECT_LOCALHOST, :ADMIN_OBJECTS, :PACKAGE_RECEIVED_BASE_QUERY, :OPTIONS_NEW, :PACKAGE_LIST_DEFAULT_FIELDS
        class << self
          def application_name
            'Aspera on Cloud'
          end

          # @return [Hash,NilClass]
          def detect(base_url)
            # no protocol ?
            base_url = "https://#{base_url}" unless base_url.match?(%r{^[a-z]{1,6}://})
            # only org provided ?
            base_url = "#{base_url}.#{Api::AoC::SAAS_DOMAIN_PROD}" unless base_url.include?('.')
            # AoC is only https
            return unless base_url.start_with?('https://')
            location = Rest.new(base_url: base_url, redirect_max: 0).call(operation: 'GET', subpath: 'auth/ping', exception: false, ret: :resp)['Location']
            return if location.nil?
            redirect_uri = URI.parse(location)
            od = Api::AoC.split_org_domain(URI.parse(base_url))
            return unless redirect_uri.path.end_with?("oauth2/#{od[:organization]}/login")
            # either in standard domain, or product name in page
            return {
              version: Api::AoC.saas_url?(base_url) ? 'SaaS' : 'Self-managed',
              url:     base_url
            }
          end

          # Get folder path that does not exist
          # @param base   [String]  Base folder path
          # @param always [Boolean] `true` always add number, `false` only if base folder already exists
          # @return [String] Folder path that does not exist, with possible .<number> extension
          def next_available_folder(base, always: false)
            counter = always ? 1 : 0
            loop do
              result = counter.zero? ? base : "#{base}.#{counter}"
              return result unless Dir.exist?(result)
              counter += 1
            end
          end

          # Get folder path that does not exist
          # If it exists, an extension is added
          # or a sequential number if extension == :seq
          # @param package_info       [Hash]   Package information
          # @param destination_folder [String] Base folder
          # @param fld.               [Array]  List of fields of package
          def unique_folder(package_info, destination_folder, fld: nil, seq: false, opt: false)
            Aspera.assert_array_all(fld, String, type: Cli::BadArgument){'fld'}
            Aspera.assert([1, 2].include?(fld.length)){'fld must have 1 or 2 elements'}
            folder = Environment.instance.sanitized_filename(package_info[fld[0]])
            if seq
              folder = next_available_folder(folder, always: !opt)
            elsif fld[1] && (Dir.exist?(folder) || !opt)
              # NOTE: it might already exist
              folder = "#{folder}.#{Environment.instance.sanitized_filename(fld[1])}"
            end
            puts("sub= #{folder}")
            File.join(destination_folder, folder)
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [String] Tested URL
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          pub_link_info = Api::AoC.link_info(app_url)
          # public link case
          if pub_link_info.key?(:token)
            pub_api = Rest.new(base_url: "https://#{URI.parse(pub_link_info[:url]).host}/api/v1")
            pub_info = pub_api.read('env/url_token_check', {token: pub_link_info[:token]})
            preset_value = {
              link: app_url
            }
            preset_value[:password] = options.get_option(:password, mandatory: true) if pub_info['password_protected']
            return {
              preset_value: preset_value,
              test_args:    'organization'
            }
          end
          options.declare(:use_generic_client, 'Wizard: AoC: use global or org specific jwt client id', allowed: Allowed::TYPES_BOOLEAN, default: Api::AoC.saas_url?(app_url))
          options.parse_options!
          # make username mandatory for jwt, this triggers interactive input
          wiz_username = options.get_option(:username, mandatory: true)
          wizard.check_email(wiz_username)
          # Set the pub key and jwt tag in the user's profile automatically
          auto_set_pub_key = false
          auto_set_jwt = false
          # use browser authentication to bootstrap
          use_browser_authentication = false
          private_key_path = wizard.ask_private_key(
            user: wiz_username,
            url: app_url,
            page: '👤 → Account Settings → Profile → Public Key'
          )
          client_id = options.get_option(:client_id)
          client_secret = options.get_option(:client_secret)
          if client_id.nil? || client_secret.nil?
            if options.get_option(:use_generic_client)
              client_id = client_secret = nil
              formatter.display_status('Using global client_id.')
            else
              formatter.display_status('Using organization specific client_id.')
              formatter.display_status('Please login to your Aspera on Cloud instance.'.red)
              formatter.display_status('Navigate to: 𓃑  → Admin → Integrations → API Clients')
              formatter.display_status('Check or create in integration:')
              formatter.display_status('- name: cli')
              formatter.display_status("- redirect uri: #{REDIRECT_LOCALHOST}")
              formatter.display_status('- origin: localhost')
              formatter.display_status('Use the generated client id and secret in the following prompts.'.red)
              Environment.instance.open_uri("#{app_url}/admin/integrations/api-clients")
              client_id = options.get_option(:client_id, mandatory: true)
              client_secret = options.get_option(:client_secret, mandatory: true)
              # use_browser_authentication = true
            end
          end
          if use_browser_authentication
            formatter.display_status('We will use web authentication to bootstrap.')
            auto_set_pub_key = true
            auto_set_jwt = true
            Aspera.error_not_implemented
            # aoc_api.oauth.grant_method = :web
            # aoc_api.oauth.scope = Api::AoC::Scope::ADMIN
            # aoc_api.oauth.specific_parameters[:redirect_uri] = REDIRECT_LOCALHOST
          end
          myself = aoc_api.read('self')
          if auto_set_pub_key
            Aspera.assert(myself['public_key'].empty?, type: Cli::Error){'Public key is already set in profile (use --override=yes)'} unless option_override
            formatter.display_status('Updating profile with the public key.')
            aoc_api.update("users/#{myself['id']}", {'public_key' => pub_key_pem})
          end
          if auto_set_jwt
            formatter.display_status('Enabling JWT for client')
            aoc_api.update("clients/#{options.get_option(:client_id)}", {'jwt_grant_enabled' => true, 'explicit_authorization_required' => false})
          end
          return {
            preset_value: {
              url:           app_url,
              username:      myself['email'],
              auth:          :jwt.to_s,
              private_key:   "@file:#{private_key_path}",
              client_id:     client_id,
              client_secret: client_secret
            }.compact,
            test_args:    'user profile show'
          }
        end

        def initialize(**_)
          super
          @cache_workspace_info = nil
          @cache_home_node_file = nil
          @cache_api_aoc = nil
          @scope = Api::AoC::Scope::USER
          options.declare(:workspace, 'Name of workspace', allowed: [String, NilClass], default: Api::AoC::DEFAULT_WORKSPACE)
          options.declare(:new_user_option, 'New user creation option for unknown package recipients', allowed: Hash)
          options.declare(:validate_metadata, 'Validate shared inbox metadata', allowed: Allowed::TYPES_BOOLEAN, default: true)
          options.declare(:package_folder, 'Handling of reception of packages in folders', allowed: Hash, default: {})
          options.parse_options!
          # add node plugin options (for manual)
          Node.declare_options(options)
        end

        # Change API scope for subsequent calls, re-instantiate API object
        # @param new_scope [String] New scope
        def change_api_scope(new_scope)
          @cache_api_aoc = nil
          @scope = new_scope
        end

        # create an API object with the same options, but with a different subpath
        # @param aoc_base_path [String] New subpath
        # @return [Api::AoC] API object for AoC (is Rest)
        def api_from_options(aoc_base_path)
          return new_with_options(
            Api::AoC,
            kwargs: {
              scope:         @scope,
              subpath:       aoc_base_path,
              secret_finder: config
            },
            option: {
              workspace: nil
            }
          )
        end

        # AoC Rest object
        # @return [Api::AoC] API object for AoC (is Rest)
        def aoc_api
          if @cache_api_aoc.nil?
            @cache_api_aoc = api_from_options(Api::AoC::API_V1)
            transfer.httpgw_url_cb = lambda do
              organization = @cache_api_aoc.read('organization')
              # @cache_api_aoc.current_user_info['connect_disabled']
              organization['http_gateway_server_url'] if organization['http_gateway_enabled'] && organization['http_gateway_server_url']
            end
          end
          return @cache_api_aoc
        end

        # Generate or update Hash with workspace id and name (option), if not already set
        # @param hash   [Hash,nil] Optional base hash (modified)
        # @param string [Boolean] true to set key as string, else as symbol
        # @param name   [Boolean] include name
        # @return [Hash] with key `workspace_[id,name]` (symbol or string) only if defined
        def workspace_id_hash(hash: nil, string: false, name: false)
          info = aoc_api.workspace
          hash = {} if hash.nil?
          fields = %i[id]
          fields.push(:name) if name
          fields.each do |i|
            k = "workspace_#{i}"
            k = k.to_sym unless string
            hash[k] = info[i] unless info[i].nil? || hash.key?(k)
          end
          return hash
        end

        # Get resource identifier from command line, either directly or from name.
        # @param resource_class_path url path for resource
        # @return identifier
        def get_resource_id_from_args(resource_class_path)
          return instance_identifier do |field, value|
            Aspera.assert(field.eql?('name'), type: Cli::BadArgument){'only selection by name is supported'}
            aoc_api.lookup_by_name(resource_class_path, value)['id']
          end
        end

        # Get resource path from command line
        def get_resource_path_from_args(resource_class_path)
          return "#{resource_class_path}/#{get_resource_id_from_args(resource_class_path)}"
        end

        # List all entities, given additional, default and user's queries
        # @param resource_class_path path to query on API
        # @param fields fields to display
        # @param base_query a query applied always
        # @param default_query default query unless overridden by user
        # @param &block (Optional) calls block with user's or default query
        def result_list(resource_class_path, fields: nil, base_query: {}, default_query: {})
          Aspera.assert_type(base_query, Hash)
          Aspera.assert_type(default_query, Hash)
          query = query_read_delete(default: default_query)
          # caller may add specific modifications or checks to query
          yield(query) if block_given?
          result = aoc_api.read_with_paging(resource_class_path, base_query.merge(query).compact, formatter: formatter)
          return Main.result_object_list(result[:items], fields: fields, total: result[:total])
        end

        # Translates `dropbox_name` to `dropbox_id` and fills current workspace_id
        def resolve_dropbox_name_default_ws_id(query)
          if query.key?('dropbox_name')
            # convenience: specify name instead of id
            raise BadArgument, 'Use field dropbox_name or dropbox_id, not both' if query.key?('dropbox_id')
            # TODO : craft a query that looks for dropbox only in current workspace
            query['dropbox_id'] = aoc_api.lookup_by_name('dropboxes', query.delete('dropbox_name'))['id']
          end
          workspace_id_hash(hash: query, string: true)
          # by default show dropbox packages only for dropboxes
          query['exclude_dropbox_packages'] = !query.key?('dropbox_id') unless query.key?('exclude_dropbox_packages')
        end

        # List all packages according to `query` option.
        # @param <none>
        # @return [Hash] {items,total} with all packages according to combination of user's query and default query
        def list_all_packages_with_query
          query = query_read_delete(default: {})
          Aspera.assert_type(query, Hash){'query'}
          PACKAGE_RECEIVED_BASE_QUERY.each{ |k, v| query[k] = v unless query.key?(k)}
          resolve_dropbox_name_default_ws_id(query)
          return aoc_api.read_with_paging('packages', query.compact, formatter: formatter)
        end

        NODE4_EXT_COMMANDS = %i[transfer].concat(Node::COMMANDS_GEN4).freeze
        private_constant :NODE4_EXT_COMMANDS

        # Execute a node gen4 command
        # @param command_repo [Symbol] command to execute
        # @param node_id [String] Node identifier
        # @param file_id [String] Root file id for the operation (can be AK root, or other, e.g. package, or link). If `nil` use AK root file id.
        # @param scope [String] node scope (Node::SCOPE_<USER|ADMIN>), or nil (requires secret)
        def execute_nodegen4_command(command_repo, node_id, file_id: nil, scope: nil)
          top_node_api = aoc_api.node_api_from(
            node_id:        node_id,
            scope:          scope,
            **workspace_id_hash(name: true)
          )
          file_id = top_node_api.read("access_keys/#{top_node_api.app_info[:node_info]['access_key']}")['root_file_id'] if file_id.nil?
          node_plugin = Node.new(context: context, api: top_node_api)
          case command_repo
          when *Node::COMMANDS_GEN4
            return node_plugin.execute_command_gen4(command_repo, file_id)
          when :transfer
            # client side is agent
            # server side is transfer server
            # in same workspace
            push_pull = options.get_next_argument('direction', accept_list: %i[push pull])
            source_folder = options.get_next_argument('folder or source files', validation: String)
            case push_pull
            when :push
              client_direction = Transfer::Spec::DIRECTION_SEND
              client_folder = source_folder
              server_folder = transfer.destination_folder(client_direction)
            when :pull
              client_direction = Transfer::Spec::DIRECTION_RECEIVE
              client_folder = transfer.destination_folder(client_direction)
              server_folder = source_folder
            else Aspera.error_unreachable_line
            end
            client_apfid = top_node_api.resolve_api_fid(file_id, client_folder)
            server_apfid = top_node_api.resolve_api_fid(file_id, server_folder)
            # force node as transfer agent
            transfer.agent_instance = Agent::Node.new(
              url:      client_apfid[:api].base_url,
              username: client_apfid[:api].app_info[:node_info]['access_key'],
              password: client_apfid[:api].oauth.authorization,
              root_id:  client_apfid[:file_id]
            )
            # additional node to node TS info
            add_ts = {
              'remote_access_key'   => server_apfid[:api].app_info[:node_info]['access_key'],
              'destination_root_id' => server_apfid[:file_id],
              'source_root_id'      => client_apfid[:file_id]
            }
            return Main.result_transfer(transfer.start(server_apfid[:api].transfer_spec_gen4(
              server_apfid[:file_id],
              client_direction,
              add_ts
            )))
          else Aspera.error_unexpected_value(command_repo){'command'}
          end
          Aspera.error_unreachable_line
        end

        # @param resource_type [Symbol] One of ADMIN_OBJECTS
        def execute_resource_action(resource_type)
          # get path on API, resource type is singular, but api is plural
          resource_class_path =
            case resource_type
            # special cases: singleton, in admin, with x
            when :self, :organization then resource_type
            when :client_registration_token, :client_access_key then "admin/#{resource_type}s"
            when :application then 'admin/apps_new'
            when :dropbox then "#{resource_type}es"
            when :kms_profile then "integrations/#{resource_type}s"
            else "#{resource_type}s"
            end
          # build list of supported operations
          singleton_object = %i[self organization].include?(resource_type)
          global_operations =  %i[create list]
          supported_operations = %i[show modify]
          supported_operations.push(:delete, *global_operations) unless singleton_object
          supported_operations.push(:do, :bearer_token) if resource_type.eql?(:node)
          supported_operations.push(:set_pub_key) if resource_type.eql?(:client)
          supported_operations.push(:shared_folder, :dropbox) if resource_type.eql?(:workspace)
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
            return do_bulk_operation(command: command, descr: 'creation data', id_result: id_result) do |params|
              aoc_api.create(resource_class_path, params)
            end
          when :list
            default_fields = ['id']
            default_query = {}
            case resource_type
            when :application
              default_query = {organization_apps: true}
              default_fields.push('app_type', 'app_name', 'available', 'direct_authorizations_allowed', 'workspace_authorizations_allowed')
            when :client, :client_access_key, :dropbox, :group, :package, :saml_configuration, :workspace then default_fields.push('name')
            when :client_registration_token then default_fields.push('value', 'data.client_subject_scopes', 'created_at')
            when :contact
              default_fields = %w[source_type source_id name email]
              default_query = {'include_only_user_personal_contacts' => true} if @scope == Api::AoC::Scope::USER
            when :node then default_fields.push('name', 'host', 'access_key')
            when :operation then default_fields = nil
            when :short_link then default_fields.push('short_url', 'data.url_token_data.purpose')
            when :user then default_fields.push('name', 'email')
            when :group_membership then default_fields.push('group_id', 'member_type', 'member_id')
            when :workspace_membership then default_fields.push('workspace_id', 'member_type', 'member_id')
            end
            return result_list(resource_class_path, fields: default_fields, default_query: default_query)
          when :show
            object = aoc_api.read(resource_instance_path)
            # default: show all, but certificate
            fields = object.keys.reject{ |k| k.eql?('certificate')}
            return Main.result_single_object(object, fields: fields)
          when :modify
            changes = options.get_next_argument('properties', validation: Hash)
            return do_bulk_operation(command: command, values: res_id) do |one_id|
              aoc_api.update("#{resource_class_path}/#{one_id}", changes)
              {'id' => one_id}
            end
          when :delete
            return do_bulk_operation(command: command, values: res_id) do |one_id|
              aoc_api.delete("#{resource_class_path}/#{one_id}")
              {'id' => one_id}
            end
          when :set_pub_key
            # special : reads private and generate public
            the_private_key = options.get_next_argument('private_key PEM value', validation: String)
            the_public_key = OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s
            aoc_api.update(resource_instance_path, {jwt_grant_enabled: true, public_key: the_public_key})
            return Main.result_success
          when :do
            command_repo = options.get_next_command(NODE4_EXT_COMMANDS)
            return execute_nodegen4_command(command_repo, res_id, scope: Api::Node::SCOPE_ADMIN)
          when :bearer_token
            node_api = aoc_api.node_api_from(
              node_id: res_id,
              scope:   options.get_next_argument('scope')
            )
            return Main.result_text(node_api.oauth.authorization)
          when :dropbox
            command_shared = options.get_next_command(%i[list])
            case command_shared
            when :list
              query = options.get_option(:query) || {}
              res_data = aoc_api.read('dropboxes', query.merge({'workspace_id'=>res_id}))
              return Main.result_object_list(res_data, fields: %w[id name description])
            end
          when :shared_folder
            query = options.get_option(:query) || Api::AoC.workspace_access(res_id).merge({'admin' => true})
            shared_folders = aoc_api.read_with_paging("#{resource_instance_path}/permissions", query)[:items]
            # inside a workspace
            command_shared = options.get_next_command(%i[list member])
            case command_shared
            when :list
              return Main.result_object_list(shared_folders, fields: %w[id node_name node_id file_id file.path tags.aspera.files.workspace.share_as])
            when :member
              shared_folder_id = instance_identifier
              shared_folder = shared_folders.find{ |i| i['id'].eql?(shared_folder_id)}
              Aspera.assert(shared_folder)
              command_shared_member = options.get_next_command(%i[list])
              case command_shared_member
              when :list
                node_api = aoc_api.node_api_from(
                  node_id: shared_folder['node_id'],
                  workspace_id: res_id,
                  workspace_name: nil,
                  scope: Api::Node::SCOPE_USER
                )
                result = node_api.read(
                  'permissions',
                  {'file_id' => shared_folder['file_id'], 'tag' => "aspera.files.workspace.id=#{res_id}"}
                )
                result.each do |item|
                  item['member'] = begin
                    if Api::AoC.workspace_access?(item)
                      {'name'=>'[Internal permission]'}
                    else
                      aoc_api.read("admin/#{item['access_type']}s/#{item['access_id']}") rescue {'name': 'not found'}
                    end
                  rescue => e
                    {'name'=>e.to_s}
                  end
                end
                # TODO : read users and group name and add, if query "include_members"
                return Main.result_object_list(result, fields: %w[access_type access_id access_level last_updated_at member.name member.email member.system_group_type member.system_group])
              end
            end
          else Aspera.error_unexpected_value(command)
          end
        end

        ADMIN_ACTIONS = %i[ats bearer_token resource usage_reports analytics subscription auth_providers].concat(ADMIN_OBJECTS).freeze

        def execute_admin_action
          # change scope to admin
          change_api_scope(Api::AoC::Scope::ADMIN)
          command_admin = options.get_next_command(ADMIN_ACTIONS)
          case command_admin
          when :bearer_token
            return Main.result_text(aoc_api.oauth.authorization)
          when :resource
            Log.log.warn('resource command is deprecated (4.18), directly use the specific command instead')
            return execute_resource_action(options.get_next_argument('resource', accept_list: ADMIN_OBJECTS))
          when *ADMIN_OBJECTS
            return execute_resource_action(command_admin)
          when :auth_providers
            command_auth_prov = options.get_next_command(%i[list update])
            case command_auth_prov
            when :list
              return result_list('admin/auth_providers')
            when :update
              Aspera.error_not_implemented
            end
          when :subscription
            org = aoc_api.read('organization')
            bss_graphql = api_from_options('bss/platform/graphql')
            command_subscription = options.get_next_command(%i[account usage])
            case command_subscription
            when :account
              # cspell:disable
              graphql_query = <<-GRAPHQL
              query ($organization_id: ID!) {
                aoc (organization_id: $organization_id) {
                  bssSubscription {
                    aocVersion
                    endDate
                    startDate
                    termMonths
                    plan
                    trial
                    termType
                    aocOrganizations {
                      id
                    }
                    additionalStorageVolumeGb
                    additionalEgressVolumeGb
                    term {
                      startDate
                      endDate
                      transferVolumeGb
                      egressVolumeGb
                      storageVolumeGb
                      transferVolumeOffsetGb
                    }
                    paygoRate {
                      transferRate
                      storageRate
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
                      watermarking
                      byok
                      automation { planAmount, max }
                    }
                  }
                }
              }
              GRAPHQL
              # cspell:enable
              result = bss_graphql.create(nil, {query: graphql_query, variables: {organization_id: org['id']}})['data']
              return Main.result_single_object(result['aoc']['bssSubscription'])
            when :usage
              # cspell:disable
              graphql_query = <<-GRAPHQL
              query ($organization_id: ID!, $startDate: Date!, $endDate: Date!, $aggregate: TransferUsageAggregateOption!) {
                aoc (organization_id: $organization_id) {
                  bssSubscription {
                    aocOrganizations { id }
                    additionalStorageVolumeGb
                    additionalEgressVolumeGb
                    aocPlanData {
                      tier
                      trial
                    }
                    term {
                      transferVolumeGb
                      egressVolumeGb
                      storageVolumeGb
                      startDate
                      endDate
                      transferVolumeOffsetGb
                    }
                    termMonths
                    transferUsages (startDate: $startDate, endDate: $endDate, aggregate: $aggregate) { mbTotal }
                    egressUsages (startDate: $startDate, endDate: $endDate, aggregate: $aggregate) { usageMb }
                  }
                  subscriptionEntitlements {
                    id
                    transferUsages (startDate: $startDate, endDate: $endDate, aggregate: $aggregate) { mbTotal }
                    egressUsages (startDate: $startDate, endDate: $endDate, aggregate: $aggregate) { usageMb }
                  }
                }
              }
              GRAPHQL
              aggregate = options.get_next_argument('aggregation', accept_list: %i[ALL MONTHLY], default: :ALL)
              today = Date.today
              start_date = options.get_next_argument('start date', mandatory: false, default: today.prev_year.strftime('%Y-%m-%d'))
              end_date = options.get_next_argument('end date', mandatory: false, default: today.strftime('%Y-%m-%d'))
              # cspell:enable
              result = bss_graphql.create(
                nil,
                {
                  query:     graphql_query,
                  variables: {
                    organization_id: org['id'],
                    aggregate:       aggregate,
                    startDate:       start_date,
                    endDate:         end_date
                  }
                }
              )['data']
              return Main.result_single_object(result['aoc'])
            end
          when :ats
            ats_api = Rest.new(**aoc_api.params.deep_merge({
              base_url: "#{aoc_api.base_url}/admin/ats/pub/v1",
              auth:     {params: {scope: Api::AoC::Scope::ADMIN_USER}}
            }))
            return Ats.new(context: context, api: ats_api).execute_action
          when :analytics
            analytics_api = Rest.new(**aoc_api.params.deep_merge({
              base_url: "#{aoc_api.base_url.gsub('/api/v1', '')}/analytics/v2",
              auth:     {params: {scope: Api::AoC::Scope::ADMIN_USER}}
            }))
            command_analytics = options.get_next_command(%i[application_events transfers files])
            case command_analytics
            when :application_events
              event_type = command_analytics.to_s
              events = analytics_api.read("organizations/#{aoc_api.current_user_info['organization_id']}/#{event_type}")[event_type]
              return Main.result_object_list(events)
            when :transfers
              event_type = command_analytics.to_s
              event_resource_type = options.get_next_argument('resource', accept_list: %i[organizations users nodes])
              event_resource_id = options.get_next_argument("#{event_resource_type} identifier", mandatory: false) ||
                case event_resource_type
                when :organizations then aoc_api.current_user_info['organization_id']
                when :users then aoc_api.current_user_info['id']
                when :nodes then aoc_api.current_user_info['read_only_home_node_id']
                else Aspera.error_unreachable_line
                end
              filter = query_read_delete(default: {})
              filter['limit'] ||= 100
              if options.get_option(:once_only, mandatory: true)
                saved_date = []
                start_date_persistency = PersistencyActionOnce.new(
                  manager: persistency,
                  data: saved_date,
                  id: IdGenerator.from_list(
                    'aoc_ana_date',
                    options.get_option(:url, mandatory: true),
                    aoc_api.workspace[:name],
                    event_resource_type.to_s,
                    event_resource_id
                  )
                )
                start_date_time = saved_date.first
                stop_date_time = Time.now.utc.strftime('%FT%T.%LZ')
                saved_date[0] = stop_date_time
                filter['start_time'] = start_date_time unless start_date_time.nil?
                filter['stop_time'] = stop_date_time
              end
              events = analytics_api.read("#{event_resource_type}/#{event_resource_id}/#{event_type}", filter)[event_type]
              start_date_persistency&.save
              if !options.get_option(:notify_to).nil?
                events.each do |tr_event|
                  config.send_email_template(values: {ev: tr_event})
                end
              end
              return Main.result_object_list(events)
            when :files
              event_type = command_analytics.to_s
              event_resource_type = options.get_next_argument('resource', accept_list: %i[organizations users nodes])
              event_resource_id = instance_identifier(description: "#{event_resource_type} identifier")
              event_resource_id =
                case event_resource_type
                when :organizations then aoc_api.current_user_info['organization_id']
                when :users then aoc_api.current_user_info['id']
                when :nodes then aoc_api.current_user_info['read_only_home_node_id']
                else Aspera.error_unreachable_line
                end if event_resource_id.empty?
              event_uuid = instance_identifier(description: 'event uuid')
              filter = query_read_delete(default: {})
              filter['limit'] ||= 100
              events = analytics_api.read("#{event_resource_type}/#{event_resource_id}/transfers/#{event_uuid}/#{event_type}", filter)[event_type]
              return Main.result_object_list(events)
            end
          when :usage_reports
            return result_list('usage_reports', base_query: workspace_id_hash)
          end
        end

        # Create a shared link for the given entity
        # @param purpose_public [Symbol]
        # @param shared_data    [Hash] information for shared data
        # @param block          [Proc] Optional: called on creation
        def short_link_command(purpose_public:, **shared_data)
          link_type = options.get_next_argument('link type', accept_list: %i[public private])
          purpose_local = case link_type
          when :public
            case purpose_public
            when /package/ then 'send_package_to_dropbox'
            when /shared/ then 'token_auth_redirection'
            else Aspera.error_unexpected_value(purpose_public){'public link purpose'}
            end
          when :private then 'shared_folder_auth_link'
          else Aspera.error_unreachable_line
          end
          command = options.get_next_command(%i[create delete list show modify])
          case command
          when :create
            entity_data = {
              purpose:            purpose_local,
              user_selected_name: nil
            }
            case link_type
            when :private
              entity_data[:data] = shared_data
            when :public
              entity_data[:expires_at]       = nil
              entity_data[:password_enabled] = false
              shared_data[:name] = ''
              entity_data[:data] = {
                aoc:            true,
                url_token_data: {
                  data:    shared_data,
                  purpose: purpose_public
                }
              }
            end
            custom_data = value_create_modify(command: command, default: {})
            if (pass = custom_data.delete('password'))
              entity_data[:data][:url_token_data][:password] = pass
              entity_data[:password_enabled] = true
            end
            entity_data.deep_merge!(custom_data)
            result_create_short_link = aoc_api.create('short_links', entity_data)
            # public: Creation: permission on node
            yield(result_create_short_link['resource_id']) if block_given? && link_type.eql?(:public)
            return Main.result_single_object(result_create_short_link)
          when :list, :show
            query = if link_type.eql?(:private)
              shared_data
            else
              {
                url_token_data: {
                  data:    shared_data,
                  purpose: purpose_public
                }
              }
            end
            list_params = {
              json_query:  query.to_json,
              purpose:     purpose_local,
              edit_access: true,
              # embed: 'updated_by_user',
              sort:        '-created_at'
            }
            return result_list('short_links', fields: Formatter.all_but('data'), base_query: list_params) if command.eql?(:list)
            one_id = instance_identifier
            found = aoc_api.read_with_paging('short_links', list_params, formatter: formatter)[:items].find{ |item| item['id'].eql?(one_id)}
            raise Cli::BadIdentifier.new('Short link', one_id) if found.nil?
            return Main.result_single_object(found, fields: Formatter.all_but('data'))
          when :modify
            raise Cli::BadArgument, 'Only public links can be modified' unless link_type.eql?(:public)
            node_file = shared_data.slice(:node_id, :file_id)
            entity_data = {
              data:       {
                url_token_data: {
                  data: node_file
                }
              },
              json_query: node_file
            }
            one_id = instance_identifier
            custom_data = value_create_modify(command: command, default: {})
            if (pass = custom_data.delete('password'))
              entity_data[:data][:url_token_data][:password] = pass
              entity_data[:password_enabled] = true
            end
            entity_data.deep_merge!(custom_data)
            aoc_api.update("short_links/#{one_id}", entity_data)
            return Main.result_status('modified')
          when :delete
            one_id = instance_identifier
            shared_data.delete(:workspace_id)
            delete_params = {
              edit_access: true,
              json_query:  shared_data.to_json
            }
            aoc_api.delete("short_links/#{one_id}", delete_params)
            if link_type.eql?(:public)
              # TODO: get permission id..
              # shared_apfid[:api].delete('permissions', {ids: })
            end
            return Main.result_status('deleted')
          end
        end

        # @return persistency object if option `once_only` is used.
        def package_persistency
          return unless options.get_option(:once_only, mandatory: true)
          # TODO: add query info to id
          PersistencyActionOnce.new(
            manager: persistency,
            data: [],
            id: IdGenerator.from_list(
              'aoc_recv',
              options.get_option(:url, mandatory: true),
              aoc_api.workspace[:id],
              aoc_api.additional_persistence_ids
            )
          )
        end

        def reject_packages_from_persistency(all_packages, skip_ids_persistency)
          return if skip_ids_persistency.nil?
          skip_package = skip_ids_persistency.data.each_with_object({}){ |i, m| m[i] = true}
          all_packages.reject!{ |pkg| skip_package[pkg['id']]}
        end

        # must be public
        ACTIONS = %i[reminder servers bearer_token organization tier_restrictions user packages files admin automation gateway].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          if %i[files packages].include?(command)
            default_flag = ' (default)' if options.get_option(:workspace).eql?(:default)
            formatter.display_status("Workspace: #{aoc_api.workspace[:name].to_s.red}#{default_flag}")
            if !aoc_api.private_link.nil?
              folder_name = aoc_api.node_api_from(node_id: aoc_api.home[:node_id]).read("files/#{aoc_api.home[:file_id]}")['name']
              formatter.display_status("Private Folder: #{folder_name}")
            end
          end
          case command
          when :reminder
            # send an email reminder with list of orgs
            user_email = options.get_option(:username, mandatory: true)
            Rest.new(base_url: "#{Api::AoC.api_base_url}/#{Api::AoC::API_V1}").create('organization_reminders', {email: user_email})
            return Main.result_status("List of organizations user is member of, has been sent by e-mail to #{user_email}")
          when :servers
            return Main.result_object_list(Rest.new(base_url: "#{Api::AoC.api_base_url}/#{Api::AoC::API_V1}").read('servers'))
          when :bearer_token
            return Main.result_text(aoc_api.oauth.authorization)
          when :organization
            return Main.result_single_object(aoc_api.read('organization'))
          when :tier_restrictions
            return Main.result_single_object(aoc_api.read('tier_restrictions'))
          when :user
            case options.get_next_command(%i[workspaces profile preferences contacts])
            when :contacts
              return execute_resource_action(:contact)
            # when :settings
            # return Main.result_object_list(aoc_api.read('client_settings/'))
            when :workspaces
              case options.get_next_command(%i[list current])
              when :list
                return result_list('workspaces', fields: %w[id name])
              when :current
                return Main.result_single_object(aoc_api.workspace)
              end
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return Main.result_single_object(aoc_api.current_user_info(exception: true))
              when :modify
                aoc_api.update("users/#{aoc_api.current_user_info(exception: true)['id']}", options.get_next_argument('properties', validation: Hash))
                return Main.result_status('modified')
              end
            when :preferences
              user_preferences_res = "users/#{aoc_api.current_user_info(exception: true)['id']}/user_interaction_preferences"
              case options.get_next_command(%i[show modify])
              when :show
                return Main.result_single_object(aoc_api.read(user_preferences_res))
              when :modify
                aoc_api.update(user_preferences_res, options.get_next_argument('properties', validation: Hash))
                return Main.result_status('modified')
              end
            end
          when :packages
            package_command = options.get_next_command(%i[shared_inboxes send receive list show delete modify].concat(Node::NODE4_READ_ACTIONS), aliases: {recv: :receive})
            case package_command
            when :shared_inboxes
              case options.get_next_command(%i[list show short_link])
              when :list
                default_query = {'embed[]' => 'dropbox', 'aggregate_permissions_by_dropbox' => true, 'sort' => 'dropbox_name'}
                workspace_id_hash(hash: default_query, string: true)
                return result_list('dropbox_memberships', fields: %w[dropbox_id dropbox.name], default_query: default_query)
              when :show
                return Main.result_single_object(aoc_api.read(get_resource_path_from_args('dropboxes')))
              when :short_link
                return short_link_command(
                  purpose_public: 'send_package_to_dropbox',
                  dropbox_id:     get_resource_id_from_args('dropboxes'),
                  name:           '',
                  **workspace_id_hash
                )
              end
            when :send
              package_data = value_create_modify(command: package_command)
              new_user_option = options.get_option(:new_user_option)
              option_validate = options.get_option(:validate_metadata)
              # Works for both normal user auth and link auth.
              workspace_id_hash(hash: package_data, string: true) unless package_data.key?('workspace_id')
              if !aoc_api.public_link.nil?
                aoc_api.assert_public_link_types(%w[send_package_to_user send_package_to_dropbox])
                box_type = aoc_api.public_link['purpose'].split('_').last
                package_data['recipients'] = [{'id' => aoc_api.public_link['data']["#{box_type}_id"], 'type' => box_type}]
                # enforce workspace id from link (should be already ok, but in case user wanted to override)
                package_data['workspace_id'] = aoc_api.public_link['data']['workspace_id']
              end
              package_data['encryption_at_rest'] = true if transfer.user_transfer_spec['content_protection'].eql?('encrypt')
              # transfer may raise an error
              created_package = aoc_api.create_package_simple(package_data, option_validate, new_user_option)
              Main.result_transfer(transfer.start(created_package[:spec], rest_token: created_package[:node]))
              # return all info on package (especially package id)
              return Main.result_single_object(created_package[:info])
            when :receive
              ids_to_download = nil
              if !aoc_api.public_link.nil?
                aoc_api.assert_public_link_types(['view_received_package'])
                # Set the package id from link
                ids_to_download = aoc_api.public_link['data']['package_id']
              end
              # Get from command line unless it was a public link
              ids_to_download ||= instance_identifier
              skip_ids_persistency = package_persistency
              case ids_to_download
              when SpecialValues::INIT
                all_packages = list_all_packages_with_query[:items]
                Aspera.assert(skip_ids_persistency){'INIT requires option once_only'}
                skip_ids_persistency.data.clear.concat(all_packages.map{ |e| e['id']})
                skip_ids_persistency.save
                return Main.result_status("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
              when SpecialValues::ALL
                all_packages = list_all_packages_with_query[:items]
                # remove from list the ones already downloaded
                reject_packages_from_persistency(all_packages, skip_ids_persistency)
                ids_to_download = all_packages.map{ |e| e['id']}
                formatter.display_status("Found #{ids_to_download.length} package(s).")
              else
                # single id to array
                ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
              end
              # download all files, or specified list only
              ts_paths = transfer.ts_source_paths(default: ['.'])
              per_package_def = options.get_option(:package_folder).symbolize_keys
              save_metadata = per_package_def.delete(:inf)
              # get value outside of loop
              destination_folder = transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE)
              result_transfer = []
              ids_to_download.each do |package_id|
                package_info = aoc_api.read("packages/#{package_id}")
                package_node_api = aoc_api.node_api_from(
                  node_id: package_info['node_id'],
                  package_info: package_info,
                  **workspace_id_hash(name: true)
                )
                transfer_spec = package_node_api.transfer_spec_gen4(
                  package_info['contents_file_id'],
                  Transfer::Spec::DIRECTION_RECEIVE,
                  {'paths'=> ts_paths}
                )
                transfer.user_transfer_spec['destination_root'] = self.class.unique_folder(package_info, destination_folder, **per_package_def) unless per_package_def.empty?
                dest_folder = transfer.user_transfer_spec['destination_root'] || destination_folder
                formatter.display_status(%Q{Downloading package: [#{package_info['id']}] "#{package_info['name']}" to [#{dest_folder}]})
                statuses = transfer.start(
                  transfer_spec,
                  rest_token: package_node_api
                )
                File.write(File.join(dest_folder, "#{package_id}.info.json"), package_info.to_json) if save_metadata
                result_transfer.push({'package' => package_id, Main::STATUS_FIELD => statuses})
                # update skip list only if all transfer sessions completed
                if skip_ids_persistency && TransferAgent.session_status(statuses).eql?(:success)
                  skip_ids_persistency.data.push(package_id)
                  skip_ids_persistency.save
                end
              end
              return Main.result_transfer_multiple(result_transfer)
            when :show
              package_id = instance_identifier
              package_info = aoc_api.read("packages/#{package_id}")
              return Main.result_single_object(package_info)
            when :list
              result = list_all_packages_with_query
              skip_ids_persistency = package_persistency
              reject_packages_from_persistency(result[:items], skip_ids_persistency)
              display_fields = PACKAGE_LIST_DEFAULT_FIELDS
              display_fields += ['workspace_id'] if aoc_api.workspace[:id].nil?
              return Main.result_object_list(result[:items], fields: display_fields, total: result[:total])
            when :delete
              return do_bulk_operation(command: package_command, values: instance_identifier) do |id|
                Aspera.assert_values(id.class, [String, Integer]){'identifier'}
                aoc_api.delete("packages/#{id}")
              end
            when :modify
              id = instance_identifier
              package_data = value_create_modify(command: package_command)
              aoc_api.update("packages/#{id}", package_data)
              return Main.result_status('modified')
            when *Node::NODE4_READ_ACTIONS
              package_id = instance_identifier
              package_info = aoc_api.read("packages/#{package_id}")
              return execute_nodegen4_command(package_command, package_info['node_id'], file_id: package_info['contents_file_id'], scope: Api::Node::SCOPE_USER)
            end
          when :files
            command_repo = options.get_next_command([:short_link].concat(NODE4_EXT_COMMANDS))
            case command_repo
            when *NODE4_EXT_COMMANDS
              return execute_nodegen4_command(command_repo, aoc_api.home[:node_id], file_id: aoc_api.home[:file_id], scope: Api::Node::SCOPE_USER)
            when :short_link
              folder_dest = options.get_next_argument('path', validation: String)
              home_node_api = aoc_api.node_api_from(
                node_id: aoc_api.home[:node_id],
                **workspace_id_hash(name: true)
              )
              shared_apfid = home_node_api.resolve_api_fid(aoc_api.home[:file_id], folder_dest)
              return short_link_command(
                purpose_public: 'view_shared_file',
                node_id:        shared_apfid[:api].app_info[:node_info]['id'],
                file_id:        shared_apfid[:file_id],
                **workspace_id_hash
              ) do |resource_id|
                       # TODO: merge with node permissions ?
                       # TODO: access level as arg
                       access_levels = Api::Node::ACCESS_LEVELS # ['delete','list','mkdir','preview','read','rename','write']
                       perm_data = {
                         'file_id'       => shared_apfid[:file_id],
                         'access_id'     => resource_id,
                         'access_type'   => 'user',
                         'access_levels' => access_levels,
                         'tags'          => {
                           # TODO: really just here ? not in tags.aspera.files.workspace ?
                           'url_token'        => true,
                           'folder_name'      => File.basename(folder_dest),
                           'created_by_name'  => aoc_api.current_user_info['name'],
                           'created_by_email' => aoc_api.current_user_info['email'],
                           'access_key'       => shared_apfid[:api].app_info[:node_info]['access_key'],
                           'node'             => shared_apfid[:api].app_info[:node_info]['host'],
                           **workspace_id_hash(string: true, name: true)
                         }
                       }
                       created_data = shared_apfid[:api].create('permissions', perm_data)
                       aoc_api.permissions_send_event(event_data: created_data, app_info: shared_apfid[:api].app_info)
                     end
            end
          when :automation
            change_api_scope(Api::AoC::Scope::ADMIN_USER)
            Log.log.warn('BETA: work under progress')
            # automation api is not in the same place
            automation_api = Rest.new(**aoc_api.params, base_url: aoc_api.base_url.gsub('/api/', '/automation/'))
            command_automation = options.get_next_command(%i[workflows instances])
            case command_automation
            when :instances
              return entity_execute(api: aoc_api, entity: 'workflow_instances')
            when :workflows
              wf_command = options.get_next_command(%i[action launch].concat(ALL_OPS))
              case wf_command
              when *ALL_OPS
                return entity_execute(
                  api: automation_api,
                  entity: 'workflows',
                  command: wf_command
                )
              when :launch
                wf_id = instance_identifier
                data = automation_api.create("workflows/#{wf_id}/launch", {})
                return Main.result_single_object(data)
              when :action
                # TODO: not complete
                wf_id = instance_identifier
                wf_action_cmd = options.get_next_command(%i[list create show])
                Log.log.warn{"Not implemented: #{wf_action_cmd}"}
                step = automation_api.create('steps', {'workflow_id' => wf_id})
                automation_api.update("workflows/#{wf_id}", {'step_order' => [step['id']]})
                action = automation_api.create('actions', {'step_id' => step['id'], 'type' => 'manual'})
                automation_api.update("steps/#{step['id']}", {'action_order' => [action['id']]})
                wf = automation_api.read("workflows/#{wf_id}")
                return Main.result_single_object(wf)
              end
            end
          when :admin
            return execute_admin_action
          when :gateway
            require 'aspera/faspex_gw'
            parameters = value_create_modify(command: command, default: {}).symbolize_keys
            uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
            server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
            Aspera.assert(parameters.except(*WebServerSimple::PARAMS).empty?)
            server.mount(uri.path, Faspex4GWServlet, aoc_api, aoc_api.workspace[:id])
            server.start
            return Main.result_status('Gateway terminated')
          else Aspera.error_unreachable_line
          end
          Aspera.error_unreachable_line
        end

        private :execute_admin_action
      end
    end
  end
end
