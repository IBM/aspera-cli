# frozen_string_literal: true

require 'aspera/schema/registry'
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
require 'aspera/graphql'
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
          client
          client_access_key
          client_registration_token
          configuration_policy
          contact
          dropbox
          dropbox_membership
          group
          group_membership
          kms_profile
          network_policy
          node
          operation
          organization
          package
          saml_configuration
          self
          short_link
          user
          workspace
          workspace_membership
        ].freeze
        # query to list fully received packages
        PACKAGE_RECEIVED_BASE_QUERY = {
          'archived'    => false,
          'has_content' => true,
          'received'    => true,
          'completed'   => true
        }.freeze
        PACKAGE_LIST_DEFAULT_FIELDS = %w[id name created_at files_completed bytes_transferred].freeze

        private_constant :REDIRECT_LOCALHOST, :ADMIN_OBJECTS, :PACKAGE_RECEIVED_BASE_QUERY, :PACKAGE_LIST_DEFAULT_FIELDS
        application_name 'Aspera on Cloud'

        class << self
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
          # @param fld                [Array]  List of fields of package
          def unique_folder(package_info, destination_folder, fld: nil, seq: false, opt: false)
            Aspera.assert_array_all(fld, String, type: BadArgument){'fld'}
            Aspera.assert_values(fld.length, [1, 2]){'fld length'}
            folder = Environment.instance.sanitized_filename(package_info[fld[0]])
            if seq
              folder = next_available_folder(folder, always: !opt)
            elsif fld[1] && (Dir.exist?(folder) || !opt)
              # NOTE: it might already exist
              folder = "#{folder}.#{Environment.instance.sanitized_filename(fld[1])}"
            end
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
          options.declare(:use_generic_client, description: 'Wizard: AoC: use global or org specific jwt client id', allowed: Allowed::TYPES_BOOLEAN, default: Api::AoC.saas_url?(app_url))
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
            Aspera.assert(myself['public_key'].empty?, 'Public key is already set in profile (use --override=yes)', type: Error) unless option_override
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

        option :workspace,         description: 'Name of workspace', allowed: [String, NilClass], default: Api::AoC::DEFAULT_WORKSPACE
        option :new_user_option,   description: 'New user creation option for unknown package recipients', allowed: [Hash, NilClass]
        option :validate_metadata, description: 'Validate shared inbox metadata', allowed: Allowed::TYPES_BOOLEAN, default: true
        option :package_folder,    schema: Schema::Registry::PACKAGE_FOLDER_OPTIONS

        def initialize(**_)
          super
          @cache_workspace_info = nil
          @cache_home_node_file = nil
          @cache_api_aoc = nil
          @scope = Api::AoC::Scope::USER
          options.parse_options!
          # add node plugin options (for manual)
          Node.declare_options(options)
        end

        # Change API scope for subsequent calls, re-instantiate API object
        # @param new_scope [String] New scope
        def change_api_scope(new_scope)
          # Discard cache
          @cache_api_aoc = nil
          @scope = new_scope
          nil
        end

        # Create an API object with the options from CLI, but with a different subpath
        # @param base_path [String] Base path for APIs.
        # @return [Api::AoC] API object for AoC (is Rest)
        def api_from_options(base_path)
          # Get all existing OAuth kwargs from `options`.
          api = Api::AoC.new(
            scope:         @scope,
            subpath:       base_path,
            secret_finder: context.secret_finder,
            **Oauth.kwargs_from_options(options)
          )
          # User set a workspace ?
          # @type [String, nil]
          workspace = options.get_option(:workspace)
          if !workspace.nil? && (m = Options.percent_selector(workspace))
            case m[:field]
            when 'name' then api.ws_ids[:name] = m[:value]
            when 'id' then api.ws_ids[:id] = m[:value]
            else Aspera.error_unexpected_value(m[:field]){'workspace selector: only `name` or `id`'}
            end
          else
            api.ws_ids[:name] = workspace
          end
          api
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
        # @param hash   [Hash,nil] Optional base `Hash` (modified)
        # @param string [Boolean] `true` to set key as `String`, else as `Symbol`
        # @param name   [Boolean] Include name
        # @return [Hash{Symbol, String => String}] the modified hash containing:
        #   * `workspace_id` [String] the unique identifier.
        #   * `workspace_name` [String] (optional) the name, included if +name+ is true.
        # @note The key type (String or Symbol) depends on the +string+ parameter.
        def workspace_id_hash(hash = nil, string: false, name: false)
          info = aoc_api.workspace_info
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

        # Get resource identifier from command line, either directly specifying the `id` or from `name` (percent selector).
        # @param resource_class_path [String] url path for resource
        # @return [String] identifier
        def get_resource_id_from_args(resource_class_path)
          return options.instance_identifier do |field, value|
            Aspera.assert_values(field, ['name'], type: BadArgument){'selector field'}
            aoc_api.lookup_with_q(resource_class_path, value: value)['id']
          end
        end

        # Get resource path from command line
        def get_resource_path_from_args(resource_class_path)
          return "#{resource_class_path}/#{get_resource_id_from_args(resource_class_path)}"
        end

        # List all entities, given additional, default and user's queries
        # @param resource_class_path [String]     path to query on API
        # @param fields              [Array, nil] fields to display
        # @param base_query          [Hash]       a query applied always
        # @param default_query       [Hash]       default query unless overridden by user
        # @yieldparam query [Hash] The user's or default query for modification
        def result_list(resource_class_path, fields: nil, base_query: {}, default_query: {})
          Aspera.assert_type(base_query, Hash)
          Aspera.assert_type(default_query, Hash)
          query = query_read_delete(default: default_query)
          # caller may add specific modifications or checks to query
          yield(query) if block_given?
          result = aoc_api.read_with_paging(resource_class_path, base_query.merge(query).compact)
          return Result::ObjectList.new(result[:items], fields: fields, total: result[:total])
        end

        # Translates `dropbox_name` to `dropbox_id` and fills current workspace_id
        def resolve_dropbox_name_default_ws_id(query)
          if query.key?('dropbox_name')
            # convenience: specify name instead of id
            raise BadArgument, 'Use field dropbox_name or dropbox_id, not both' if query.key?('dropbox_id')
            # TODO : craft a query that looks for dropbox only in current workspace
            query['dropbox_id'] = aoc_api.lookup_with_q('dropboxes', value: query.delete('dropbox_name'))['id']
          end
          workspace_id_hash(query, string: true)
          # by default show dropbox packages only for dropboxes
          query['exclude_dropbox_packages'] = !query.key?('dropbox_id') unless query.key?('exclude_dropbox_packages')
        end

        # List all packages according to `query` option.
        # @return [Hash] {items,total} with all packages according to combination of user's query and default query
        def list_all_packages_with_query
          query = query_read_delete(default: {})
          Aspera.assert_type(query, Hash){'query'}
          PACKAGE_RECEIVED_BASE_QUERY.each{ |k, v| query[k] = v unless query.key?(k)}
          resolve_dropbox_name_default_ws_id(query)
          return aoc_api.read_with_paging('packages', query.compact)
        end

        FILES_COMMANDS = (Node::COMMANDS_GEN4 + %i[transfer]).freeze

        # Execute a node gen4 command starting at given node and file IDs
        # @param command_repo [Symbol] Command to execute
        # @param node_id [String] Node identifier
        # @param file_id [String] Root file id for the operation (can be AK root, or other, e.g. package, or link). If `nil` use AK root file id.
        # @param scope [String] node scope (Node::SCOPE_<USER|ADMIN>), or nil (requires secret)
        def execute_nodegen4_command(command_repo, node_id, file_id: nil, scope: nil)
          top_node_api = aoc_api.node_api_from(
            node_id:        node_id,
            scope:          scope,
            **workspace_id_hash(name: true)
          )
          file_id = top_node_api.read("access_keys/#{top_node_api.app_info.node_info['access_key']}")['root_file_id'] if file_id.nil?
          node_plugin = Node.new(context: context, api: top_node_api)
          case command_repo
          when *Node::COMMANDS_GEN4
            # For permission: the handler consumes the path first then re-dispatches to sub-commands.
            # Calling dispatch_from_registry with skip_setup would bypass path consumption and fail.
            return node_plugin.send(:"action_access_keys_do_#{command_repo}", do_root_file_id: file_id) if command_repo.eql?(:permission)
            return node_plugin.dispatch_from_registry([:access_keys, :do, command_repo], {do_root_file_id: file_id}, skip_setup: true)
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
            client_apifid = top_node_api.resolve_api_fid(file_id, client_folder)
            server_apifid = top_node_api.resolve_api_fid(file_id, server_folder)
            # force node as transfer agent
            transfer.agent_instance = Agent::Node.new(
              url:      client_apifid.node_api.base_url,
              username: client_apifid.node_api.app_info.node_info['access_key'],
              password: client_apifid.node_api.oauth.authorization,
              root_id:  client_apifid.file_id
            )
            # additional node to node TS info
            add_ts = {
              'remote_access_key'   => server_apifid.node_api.app_info.node_info['access_key'],
              'destination_root_id' => server_apifid.file_id,
              'source_root_id'      => client_apifid.file_id
            }
            return Runner.result_transfer(transfer.start(server_apifid.node_api.transfer_spec_gen4(
              server_apifid.file_id,
              client_direction,
              add_ts
            )))
          else Aspera.error_unexpected_value(command_repo){'command'}
          end
          Aspera.error_unreachable_line
        end

        # Execute an action on admin resources
        # @param resource_type [Symbol] One of ADMIN_OBJECTS
        # Per-resource configuration for admin CRUD resources.
        # Keys: path, list_fields, id_result, require_ws_id, create_schema, extra_ops, singleton, op_setup
        # op_setup: Hash of op => setup method name, used for ops that require consuming an instance identifier.
        #   For Operations::INSTANCE ops (show/modify/delete), use the auto-generated :setup_admin_<res>_instance.
        #   For extra_ops that are instance ops, specify explicitly (or rely on the auto-generated one).
        ADMIN_OBJECT_CONFIG = {
          client:                    {extra_ops: %i[set_pub_key]},
          client_access_key:         {path: 'admin/client_access_keys'},
          client_registration_token: {path: 'admin/client_registration_tokens', list_fields: %w[id value data.client_subject_scopes data.name created_at], id_result: 'token'},
          configuration_policy:      {list_fields: nil},
          contact:                   {list_fields: %w[source_type source_id name email]},
          dropbox:                   {path: 'dropboxes', require_ws_id: true},
          dropbox_membership:        {},
          group:                     {create_schema: false},
          group_membership:          {list_fields: %w[id group_id member_type member_id], create_schema: false},
          kms_profile:               {path: 'integrations/kms_profiles', create_schema: false},
          network_policy:            {list_fields: nil},
          node:                      {list_fields: %w[id name host access_key], extra_ops: %i[do bearer_token]},
          operation:                 {list_fields: %w[id type status created_at updated_at workspace_id user_id workspace_membership_id group_membership_id], ops: %i[list show modify]},
          organization:              {singleton: true},
          package:                   {},
          saml_configuration:        {create_schema: false},
          self:                      {singleton: true},
          short_link:                {list_fields: %w[id short_url data.url_token_data.purpose password_enabled password_protected updated_by_user_id updated_at]},
          user:                      {list_fields: %w[id name email], extra_ops: %i[preferences notifications], op_setup: {preferences: :setup_admin_user_instance, notifications: :setup_admin_user_instance}},
          workspace:                 {extra_ops: %i[shared_folder dropbox], op_setup: {shared_folder: :setup_admin_workspace_shared_folder, dropbox: :setup_admin_workspace_dropbox}},
          workspace_membership:      {list_fields: %w[id workspace_id member_type member_id]}
        }.freeze
        private_constant :ADMIN_OBJECT_CONFIG

        # @return [String] AoC REST path for an admin resource type
        def aoc_res_path(res)
          cfg = ADMIN_OBJECT_CONFIG.fetch(res, {})
          return cfg[:path] if cfg[:path]
          base = "#{res}s".gsub(/ys$/, 'ies')
          base
        end

        # @return [Hash] {path:, ops:, id_result:, require_ws_id:, list_fields:, schema:}
        def aoc_res_cfg(res)
          cfg  = ADMIN_OBJECT_CONFIG.fetch(res, {})
          path = aoc_res_path(res)
          ops  = cfg[:ops] || (Operations::ALL + (cfg[:extra_ops] || []))
          schema = cfg[:create_schema] == false ? nil : Schema::Registry.req_body(Schema::Registry::AOC, "#{path}.post")
          {
            path:          path,
            ops:           ops,
            id_result:     cfg[:id_result] || 'id',
            require_ws_id: cfg[:require_ws_id] || false,
            list_fields:   cfg.key?(:list_fields) ? cfg[:list_fields] : %w[id name],
            schema:        schema
          }
        end

        # Known fixed set of AoC application types (verified against API: activity, automation, files, packages)
        APP_TYPES = %i[activity automation files packages].freeze

        ADMIN_ACTIONS = %i[bearer_token application ats usage_reports analytics subscription auth_providers].concat(ADMIN_OBJECTS).freeze

        # Build analytics REST API (shared by action_admin_analytics_*)
        def build_analytics_api
          Rest.new(**aoc_api.params.deep_merge({
            base_url: "#{aoc_api.base_url.gsub('/api/v1', '')}/analytics/v2",
            auth:     {params: {scope: Api::AoC::Scope::ADMIN_USER}}
          }))
        end

        # Compute short-link purposes from shared_data keys and link_type.
        # @param shared_data [Hash] :dropbox_id+:name or :file_id+:node_id
        # @param link_type [Symbol] :public or :private
        # @return [Array(String,String)] [token_purpose, short_link_purpose]
        def short_link_purposes(shared_data, link_type)
          if shared_data.keys.sort == %i[dropbox_id name]
            token_purpose = 'send_package_to_dropbox'
            short_link_purpose = link_type.eql?(:public) ? 'send_package_to_dropbox' : 'shared_folder_auth_link'
          elsif shared_data.keys.sort == %i[file_id node_id]
            token_purpose = 'view_shared_file'
            short_link_purpose = link_type.eql?(:public) ? 'token_auth_redirection' : 'shared_folder_auth_link'
          else
            Aspera.error_unexpected_value(shared_data.keys)
          end
          [token_purpose, short_link_purpose]
        end

        # Build the list_params hash used by delete/list/show/modify short link operations.
        # @return [Hash]
        def short_link_list_params(shared_data:, link_type:, token_purpose:, short_link_purpose:, **)
          query = if link_type.eql?(:private)
            shared_data
          else
            {url_token_data: {data: shared_data, purpose: token_purpose}}
          end
          {
            json_query:  query.to_json,
            purpose:     short_link_purpose,
            edit_access: true,
            sort:        '-created_at'
          }
        end

        # @return [PersistencyActionOnce, nil] persistency object if option `once_only` is used.
        def package_persistency
          return unless options.get_option(:once_only, mandatory: true)
          # TODO: add query info to id
          PersistencyActionOnce.new(
            manager: persistency,
            data: [],
            id: IdGenerator.from_list(
              'aoc_recv',
              options.get_option(:url, mandatory: true),
              aoc_api.workspace_info[:id],
              aoc_api.additional_persistence_ids
            )
          )
        end

        def reject_packages_from_persistency(all_packages, skip_ids_persistency)
          return if skip_ids_persistency.nil?
          skip_package = skip_ids_persistency.data.to_h{ |i| [i, true]}
          all_packages.reject!{ |pkg| skip_package[pkg['id']]}
        end

        # --- DSL command declarations ---

        # Root-level commands
        command :reminder, description: 'Send reminder email with list of orgs'
        command(
          :servers, description: 'List AoC servers (no auth)',
          action: lambda do
            no_auth_api = Api::AoC.new(url: options.get_option(:url), auth: :none)
            Result::ObjectList.new(no_auth_api.read('servers'))
          end
        )
        command :bearer_token,      description: 'Display bearer token',
          action: ->{Result::Text.new(aoc_api.oauth.authorization)}
        command :organization,      description: 'Show organization info',
          action: ->{Result::SingleObject.new(aoc_api.read('organization'))}
        command :tier_restrictions, description: 'Show tier restrictions',
          action: ->{Result::SingleObject.new(aoc_api.read('tier_restrictions'))}
        command :user,              description: 'User commands'
        command :packages,          description: 'Package commands', setup: :setup_workspace_display
        command :files,             description: 'Files commands (workspace-aware)', setup: :setup_workspace_display
        command :admin, description: 'Administration commands', setup: :setup_admin_scope
        commands_under(:admin) do
          command :bearer_token,   description: 'Show admin bearer token',
            action: ->{Result::Text.new(aoc_api.oauth.authorization)}
          command :application,    description: 'Manage applications'
          command(
            :ats, description: 'Manage ATS (Aspera Transfer Service)',
            action: lambda do
              ats_api = Rest.new(**aoc_api.params.deep_merge({
                base_url: "#{aoc_api.base_url}/admin/ats/pub/v1",
                auth:     {params: {scope: Api::AoC::Scope::ADMIN_USER}}
              }))
              Ats.new(context: context, api: ats_api).execute_action
            end
          )
          command :usage_reports,  description: 'List usage reports',
            action: ->{result_list('usage_reports', base_query: workspace_id_hash)}
          command :auth_providers, description: 'Manage auth providers'
          command :subscription,   description: 'Show subscription info'
          command :analytics,      description: 'Query analytics'
          ADMIN_OBJECTS.each do |res|
            cfg            = ADMIN_OBJECT_CONFIG.fetch(res, {})
            op_setup       = cfg[:op_setup] || {}
            is_singleton   = cfg[:singleton]
            instance_attrs = is_singleton ? {} : {instance_arg: :res_id, lookup: :"lookup_aoc_#{res}_id"}
            ops            = if cfg[:ops]
              cfg[:ops]
            elsif is_singleton
              %i[show]
            else
              Operations::ALL + (cfg[:extra_ops] || [])
            end
            command(res, description: "Manage #{res.to_s.tr('_', ' ')}")
            commands_under([:admin, res]) do
              ops.each do |op|
                extra_setup = op_setup[op]
                attrs = if Operations::GLOBAL.include?(op)
                  extra_setup ? {setup: extra_setup} : {}
                else
                  instance_attrs.merge(extra_setup ? {setup: extra_setup} : {})
                end
                command(op, description: op.to_s.tr('_', ' ').capitalize, **attrs)
              end
            end
          end
        end
        # admin > workspace > shared_folder sub-tree
        commands_under(%i[admin workspace shared_folder]) do
          command :list,   description: 'List shared folders'
          command :node,   description: 'Execute node command on shared folder',   instance_arg: :sf_id, setup: :setup_admin_workspace_shared_folder_node
          command :member, description: 'Show folder members',                     instance_arg: :sf_id, setup: :setup_admin_workspace_shared_folder_member
        end
        commands_under(%i[admin workspace shared_folder member]) do
          command :list, description: 'List members of a shared folder'
        end
        # admin > workspace > dropbox sub-tree
        commands_under(%i[admin workspace dropbox]) do
          command :list, description: 'List dropboxes in workspace'
        end
        # admin > node > do sub-tree (FILES_COMMANDS)
        commands_under(%i[admin node do]) do
          FILES_COMMANDS.each{ |c| command(c, description: c.to_s.tr('_', ' ').capitalize)}
        end
        # admin > user > preferences|notifications sub-trees
        %i[preferences notifications].each do |pref|
          commands_under([:admin, :user, pref]) do
            command :show,   description: "Show #{pref}"
            command :modify, description: "Modify #{pref}"
          end
        end
        commands_under(%i[admin auth_providers]) do
          command :list, description: 'List auth providers',
            action: ->{result_list('admin/auth_providers')}
          command :update, description: 'Update auth provider', action: ->{Aspera.error_not_implemented}
        end
        commands_under(%i[admin subscription]) do
          command :account, description: 'Show subscription account'
          command :usage,   description: 'Show subscription usage'
        end
        commands_under(%i[admin analytics]) do
          command :application_events, description: 'List application events'
          command :transfers,          description: 'List transfer events'
          command :files,              description: 'List file events'
        end
        # application sub-commands
        commands_under(%i[admin application]) do
          command :types,      description: 'List application types',
            action: ->{Result::ObjectList.new(aoc_api.read('admin/apps'))}
          command :settings,   description: 'Manage per-app-type settings'
          command :instance,   description: 'Manage app instances'
          command :membership, description: 'Manage app memberships'
        end
        APP_SETTINGS_PATH = %i[admin application settings].freeze
        APP_INSTANCE_PATH = %i[admin application instance].freeze
        private_constant :APP_SETTINGS_PATH, :APP_INSTANCE_PATH
        commands_under(APP_SETTINGS_PATH) do
          APP_TYPES.each do |app_type|
            command(app_type, description: "Settings for #{app_type} app")
            commands_under(APP_SETTINGS_PATH + [app_type]) do
              command :show,   description: "Show #{app_type} settings",
                action: ->{Result::SingleObject.new(aoc_api.read("/apps/#{app_type}/settings"))}
              command(:modify, description: "Modify #{app_type} settings", action: lambda do
                aoc_api.update("/apps/#{app_type}/settings", options.get_next_argument('properties', validation: Hash))
                Result::Status.new('modified')
              end)
            end
          end
        end
        commands_under(APP_INSTANCE_PATH) do
          command(:list, description: 'List app instances', action: lambda do
            result_list(
              'admin/apps_new',
              fields:        %w[id app_type available workspace_id],
              default_query: {workspace_id: aoc_api.workspace_info[:id]}
            )
          end)
          APP_TYPES.each do |app_type|
            command(app_type, description: "Show or modify a #{app_type} instance")
            commands_under(APP_INSTANCE_PATH + [app_type]) do
              command :show,   description: "Show a #{app_type} instance",   instance_arg: :res_id
              command :modify, description: "Modify a #{app_type} instance", instance_arg: :res_id
            end
          end
        end
        commands_under(%i[admin application membership]) do
          command :list, description: 'List app memberships',
            action: ->{result_list('apps/app_memberships')}
          command :show,   description: 'Show an app membership',   instance_arg: :res_id
          command :delete, description: 'Delete an app membership', instance_arg: :res_id
          command :create, description: 'Create an app membership'
        end
        command :automation,        description: 'Automation commands (BETA)', setup: :setup_automation_api
        command :gateway,           description: 'Start AoC Faspex4 gateway'

        # user sub-commands
        commands_under(:user) do
          command :workspaces,    description: 'Workspace commands'
          command :profile,       description: 'User profile commands'
          command :preferences,   description: 'User interaction preferences'
          command :notifications, description: 'Notification preferences'
          command :contacts,      description: 'Manage contacts'
          entity_command :settings, api: :aoc_api, entity: 'client_settings', description: 'Manage client settings'
        end
        # user > contacts sub-commands (same CRUD as admin > contact)
        commands_under(%i[user contacts]) do
          Operations::ALL.each{ |op| command(op, description: op.to_s.capitalize)}
        end

        commands_under(%i[user workspaces]) do
          command :list,    description: 'List workspaces',
            action: ->{result_list('workspaces', fields: %w[id name])}
          command :current, description: 'Show current workspace',
            action: ->{Result::SingleObject.new(aoc_api.workspace_info)}
        end

        commands_under(%i[user profile]) do
          command :show, description: 'Show user profile',
            action: ->{Result::SingleObject.new(aoc_api.current_user_info(exception: true))}
          command(
            :modify, description: 'Modify user profile',
            action: lambda do
              aoc_api.update("users/#{aoc_api.current_user_info(exception: true)['id']}", options.get_next_argument('properties', validation: Hash))
              Result::Status.new('modified')
            end
          )
        end

        commands_under(%i[user preferences]) do
          command(
            :show, description: 'Show user preferences',
            action: lambda do
              user_id = aoc_api.current_user_info(exception: true)['id']
              Result::SingleObject.new(aoc_api.read("users/#{user_id}/user_interaction_preferences"))
            end
          )
          command(
            :modify, description: 'Modify user preferences',
            action: lambda do
              user_id = aoc_api.current_user_info(exception: true)['id']
              aoc_api.update("users/#{user_id}/user_interaction_preferences", options.get_next_argument('properties', validation: Hash))
              Result::Status.new('modified')
            end
          )
        end

        commands_under(%i[user notifications]) do
          command(
            :show, description: 'Show notification preferences',
            action: lambda do
              user_id = aoc_api.current_user_info(exception: true)['id']
              Result::SingleObject.new(aoc_api.read("users/#{user_id}/notification_preferences"))
            end
          )
          command(
            :modify, description: 'Modify notification preferences',
            action: lambda do
              user_id = aoc_api.current_user_info(exception: true)['id']
              aoc_api.update("users/#{user_id}/notification_preferences", options.get_next_argument('properties', validation: Hash))
              Result::Status.new('modified')
            end
          )
        end

        # packages sub-commands — instance commands consume package_id
        commands_under(:packages) do
          command :shared_inboxes,    description: 'Shared inbox commands'
          command :send,              description: 'Send a package'
          command :receive,           description: 'Receive package(s)', aliases: [:recv], instance_arg: :package_id
          command :list,              description: 'List packages'
          command :show,              description: 'Show a package',              instance_arg: :package_id
          command :delete,            description: 'Delete package(s)',           instance_arg: :package_id
          command :modify,            description: 'Modify a package',            instance_arg: :package_id
          # Node Gen4 read-only actions on packages
          command :bearer_token_node, description: 'Show bearer token for package node', instance_arg: :package_id
          command :node_info,         description: 'Show node info for package',         instance_arg: :package_id
          command :browse,            description: 'Browse package contents',            instance_arg: :package_id
          command :find,              description: 'Find files in package',              instance_arg: :package_id
        end

        commands_under(%i[packages shared_inboxes]) do
          command :list,       description: 'List shared inboxes',
            action: (lambda do
              result_list(
                'dropbox_memberships',
                fields: %w[dropbox_id dropbox.name],
                default_query: workspace_id_hash({'embed[]' => 'dropbox', 'aggregate_permissions_by_dropbox' => true, 'sort' => 'dropbox_name'}, string: true)
              )
            end)
          command :show,       description: 'Show a shared inbox', instance_arg: :dropbox_id,
            action: ->(dropbox_id:, **){Result::SingleObject.new(aoc_api.read("dropboxes/#{dropbox_id}"))}
          command :short_link, description: 'Manage shared inbox short links',
            setup: :setup_packages_short_link
        end
        # packages > shared_inboxes > short_link sub-commands
        commands_under(%i[packages shared_inboxes short_link]) do
          %i[create delete list show modify].each{ |op| command(op, description: op.to_s.capitalize)}
        end

        # files sub-commands: all FILES_COMMANDS + :short_link
        # Declared dynamically after FILES_COMMANDS is available (class body evaluated after constants)
        commands_under(:files) do
          command :short_link, description: 'Manage file short link', setup: :setup_files_short_link
          command :transfer,         description: 'Transfer files (node-to-node)'
          command :mkdir,            description: 'Create folder'
          command :mklink,           description: 'Create symbolic link'
          command :mkfile,           description: 'Create file'
          command :rename,           description: 'Rename entry'
          command :delete,           description: 'Delete entry'
          command :upload,           description: 'Upload files'
          command :download,         description: 'Download files'
          command :sync,             description: 'Synchronize folders'
          command :cat,              description: 'Show file contents'
          command :show,             description: 'Show file info'
          command :modify,           description: 'Modify file'
          command :permission,       description: 'Manage permissions'
          command :thumbnail,        description: 'Show file thumbnail'
          command :v3,               description: 'Legacy v3 commands on files'
          command :bearer_token_node, description: 'Show bearer token for file node'
          command :node_info,         description: 'Show node info for file'
          command :browse,            description: 'Browse files'
          command :find,              description: 'Find files'
        end
        # files > short_link sub-commands
        commands_under(%i[files short_link]) do
          %i[create delete list show modify].each{ |op| command(op, description: op.to_s.capitalize)}
        end

        # automation sub-commands
        commands_under(:automation) do
          entity_command :instances, description: 'Manage workflow instances', api: :aoc_api, entity: 'workflow_instances'
          command :workflows, description: 'Manage workflows'
        end

        commands_under(%i[automation workflows]) do
          command :create,  description: 'Create a workflow'
          command :list,    description: 'List workflows'
          command :show,    description: 'Show a workflow'
          command :modify,  description: 'Modify a workflow'
          command :delete,  description: 'Delete a workflow'
          command :launch, description: 'Launch a workflow', instance_arg: :wf_id,
            action: ->(wf_id:, **){Result::SingleObject.new(@automation_api.create("workflows/#{wf_id}/launch", {}))}
          command :action, description: 'Add action to workflow (TODO)'
        end

        commands_under(%i[automation workflows action]) do
          command :list,   description: 'List actions (TODO)'
          command :create, description: 'Create an action (TODO)'
          command :show,   description: 'Show an action (TODO)'
        end

        # --- setup methods ---

        # Display workspace info before dispatching files/packages sub-commands.
        # Returns {} so it does not inject anything into ctx.
        def setup_workspace_display(**)
          formatter.display_status("Workspace: #{aoc_api.workspace_info[:name].to_s.red}#{' (default)' if aoc_api.default_workspace?}")
          if !aoc_api.private_link.nil?
            folder_name = aoc_api.node_api_from(node_id: aoc_api.home[:node_id]).read("files/#{aoc_api.home[:file_id]}")['name']
            formatter.display_status("Private Folder: #{folder_name}")
          end
          {}
        end

        # Build automation API and store in @automation_api ivar.
        def setup_automation_api(**)
          change_api_scope(Api::AoC::Scope::ADMIN_USER)
          Log.log.warn('BETA: work under progress')
          @automation_api = Rest.new(**aoc_api.params, base_url: aoc_api.base_url.gsub('/api/', '/automation/'))
          {}
        end

        # --- handler methods ---

        def action_reminder
          user_email = options.get_option(:username, mandatory: true)
          no_auth_api = Api::AoC.new(url: options.get_option(:url), auth: :none)
          no_auth_api.create('organization_reminders', {email: user_email})
          return Result::Status.new("List of organizations user is member of, has been sent by e-mail to #{user_email}")
        end

        # packages > send
        def action_packages_send
          package_data = value_create_modify(command: :send, schema: Schema::Registry.req_body(Schema::Registry::AOC, 'packages.post'))
          new_user_option = options.get_option(:new_user_option)
          option_validate = options.get_option(:validate_metadata)
          workspace_id_hash(package_data, string: true) unless package_data.key?('workspace_id')
          if !aoc_api.public_link.nil?
            aoc_api.assert_public_link_types(%w[send_package_to_user send_package_to_dropbox])
            box_type = aoc_api.public_link['purpose'].split('_').last
            package_data['recipients'] = [{'id' => aoc_api.public_link['data']["#{box_type}_id"], 'type' => box_type}]
            package_data['workspace_id'] = aoc_api.public_link['data']['workspace_id']
          end
          package_data['encryption_at_rest'] = true if transfer.user_transfer_spec['content_protection'].eql?('encrypt')
          created_package = aoc_api.create_package_simple(package_data, option_validate, new_user_option)
          Runner.result_transfer(transfer.start(created_package[:spec], rest_token: created_package[:node]))
          return Result::SingleObject.new(created_package[:info])
        end

        # packages > receive — package_id: from instance_arg: (or overridden by public_link)
        def action_packages_receive(package_id:, **)
          ids_to_download = if aoc_api.public_link.nil?
            package_id
          else
            aoc_api.assert_public_link_types(['view_received_package'])
            aoc_api.public_link['data']['package_id']
          end
          skip_ids_persistency = package_persistency
          case ids_to_download
          when SpecialValues::INIT
            all_packages = list_all_packages_with_query[:items]
            Aspera.assert(skip_ids_persistency, 'INIT requires option once_only')
            skip_ids_persistency.data.clear.concat(all_packages.map{ |e| e['id']})
            skip_ids_persistency.save
            return Result::Status.new("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
          when SpecialValues::ALL
            all_packages = list_all_packages_with_query[:items]
            reject_packages_from_persistency(all_packages, skip_ids_persistency)
            ids_to_download = all_packages.map{ |e| e['id']}
            formatter.display_status("Found #{ids_to_download.length} package(s).")
          else
            ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
          end
          ts_paths = transfer.ts_source_paths(default: ['.'])
          per_package_def = options.get_option(:package_folder).symbolize_keys
          save_metadata = per_package_def.delete(:inf)
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
            statuses = transfer.start(transfer_spec, rest_token: package_node_api)
            File.write(File.join(dest_folder, "#{package_id}.info.json"), package_info.to_json) if save_metadata
            result_transfer.push({'package' => package_id, Runner::STATUS_FIELD => statuses})
            if skip_ids_persistency && TransferAgent.session_status(statuses).eql?(:success)
              skip_ids_persistency.data.push(package_id)
              skip_ids_persistency.save
            end
          end
          return Runner.result_transfer_multiple(result_transfer)
        end

        # packages > list
        def action_packages_list
          result = list_all_packages_with_query
          skip_ids_persistency = package_persistency
          reject_packages_from_persistency(result[:items], skip_ids_persistency)
          display_fields = PACKAGE_LIST_DEFAULT_FIELDS
          display_fields += ['workspace_id'] if aoc_api.workspace_info[:id].nil?
          Result::ObjectList.new(result[:items], fields: display_fields, total: result[:total])
        end

        # packages > show
        def action_packages_show(package_id:, **)
          Result::SingleObject.new(aoc_api.read("packages/#{package_id}"))
        end

        # packages > delete
        def action_packages_delete(package_id:, **)
          do_bulk_operation(command: :delete, values: package_id) do |one_id|
            Aspera.assert_type(one_id, String, Integer){'identifier'}
            aoc_api.delete("packages/#{one_id}")
          end
        end

        # packages > modify
        def action_packages_modify(package_id:, **)
          aoc_api.update("packages/#{package_id}", value_create_modify(command: :modify))
          Result::Status.new('modified')
        end

        # packages > bearer_token_node / node_info / browse / find
        # (NODE4_READ_ACTIONS dispatched by full path: action_packages_bearer_token_node, etc.)
        Node::NODE4_READ_ACTIONS.each do |action|
          define_action_method([:packages, action]) do |package_id:, **|
            package_info = aoc_api.read("packages/#{package_id}")
            execute_nodegen4_command(action, package_info['node_id'], file_id: package_info['contents_file_id'], scope: Api::Node::Scope::USER)
          end
        end

        # setup: files > short_link
        # Resolves the target folder, consumes link_type argument, computes purposes.
        # @return [Hash] ctx keys: sl_shared_data, sl_link_type, sl_token_purpose, sl_short_link_purpose, sl_perm_block, sl_shared_apifid, sl_folder_dest
        def setup_files_short_link(**)
          folder_dest = options.get_next_argument('path', validation: String)
          home_node_api = aoc_api.node_api_from(
            node_id: aoc_api.home[:node_id],
            **workspace_id_hash(name: true)
          )
          shared_apifid = home_node_api.resolve_api_fid(aoc_api.home[:file_id], folder_dest)
          shared_data = {
            node_id: shared_apifid.node_api.app_info.node_info['id'],
            file_id: shared_apifid.file_id
          }
          link_type = options.get_next_argument('link access (public or private)', accept_list: %i[public private])
          token_purpose, short_link_purpose = short_link_purposes(shared_data, link_type)
          perm_block = lambda do |op, id, access_levels|
            case op
            when :create
              perm_data = {
                'file_id'       => shared_apifid.file_id,
                'access_id'     => id,
                'access_type'   => 'user',
                'access_levels' => Api::AoC.expand_access_levels(access_levels),
                'tags'          => {
                  'url_token'        => true,
                  'folder_name'      => File.basename(folder_dest),
                  'created_by_name'  => aoc_api.current_user_info['name'],
                  'created_by_email' => aoc_api.current_user_info['email'],
                  'access_key'       => shared_apifid.node_api.app_info.node_info['access_key'],
                  'node'             => shared_apifid.node_api.app_info.node_info['name'],
                  **workspace_id_hash(string: true, name: true)
                }
              }
              created_data = shared_apifid.node_api.create('permissions', perm_data)
              aoc_api.permissions_send_event(event_data: created_data, app_info: shared_apifid.node_api.app_info)
            when :update
              found = shared_apifid.node_api.read('permissions', {file_id: shared_apifid.file_id, inherited: false, access_type: 'user', access_id: id}).find{ |i| i['access_id'].eql?(id)}
              raise Error, "Short link not found: #{id}" if found.nil?
              shared_apifid.node_api.update("permissions/#{found['id']}", {access_levels: Api::AoC.expand_access_levels(access_levels)})
            when :delete
              found = shared_apifid.node_api.read('permissions', {file_id: shared_apifid.file_id, inherited: false, access_type: 'user', access_id: id}).first
              raise Error, "Short link not found: #{id}" if found.nil?
              shared_apifid.node_api.delete("permissions/#{found['id']}")
            else Aspera.error_unexpected_value(op)
            end
          end
          {
            sl_shared_data:        shared_data,
            sl_link_type:          link_type,
            sl_token_purpose:      token_purpose,
            sl_short_link_purpose: short_link_purpose,
            sl_perm_block:         perm_block
          }
        end

        # setup: packages > shared_inboxes > short_link
        # Reads dropbox_id, consumes link_type argument, computes purposes.
        # @return [Hash] ctx keys: sl_shared_data, sl_link_type, sl_token_purpose, sl_short_link_purpose
        def setup_packages_short_link(**)
          dropbox_id = get_resource_id_from_args('dropboxes')
          shared_data = {dropbox_id: dropbox_id, name: ''}
          link_type = options.get_next_argument('link access (public or private)', accept_list: %i[public private])
          token_purpose, short_link_purpose = short_link_purposes(shared_data, link_type)
          {
            sl_shared_data:        shared_data,
            sl_link_type:          link_type,
            sl_token_purpose:      token_purpose,
            sl_short_link_purpose: short_link_purpose,
            sl_perm_block:         nil
          }
        end

        # Shared implementation for short_link > create
        def sl_exec_create(sl_shared_data:, sl_link_type:, sl_token_purpose:, sl_short_link_purpose:, sl_perm_block:, **)
          shared_data = sl_shared_data.dup
          workspace_id_hash(shared_data)
          create_payload = {purpose: sl_short_link_purpose, user_selected_name: nil}
          case sl_link_type
          when :private
            create_payload[:data] = shared_data
          when :public
            create_payload[:expires_at]       = nil
            create_payload[:password_enabled] = false
            shared_data[:name] = ''
            create_payload[:data] = {
              aoc:            true,
              url_token_data: {data: shared_data, purpose: sl_token_purpose}
            }
          end
          custom_data = value_create_modify(command: :create, default: {})
          access_levels = custom_data.delete('access_levels')
          if (pass = custom_data.delete('password'))
            create_payload[:data][:url_token_data][:password] = pass
            create_payload[:password_enabled] = true
          end
          create_payload.deep_merge!(custom_data)
          result_create_short_link = aoc_api.create('short_links', create_payload)
          sl_perm_block&.call(:create, result_create_short_link['resource_id'], access_levels) if sl_link_type.eql?(:public)
          Result::SingleObject.new(result_create_short_link)
        end

        # Shared implementation for short_link > delete|list|show|modify: fetch the short_list
        def sl_fetch_list(sl_shared_data:, sl_link_type:, sl_token_purpose:, sl_short_link_purpose:, **)
          shared_data = sl_shared_data.dup
          workspace_id_hash(shared_data)
          list_params = short_link_list_params(
            shared_data: shared_data, link_type: sl_link_type,
            token_purpose: sl_token_purpose, short_link_purpose: sl_short_link_purpose
          )
          {
            sl_short_list:     aoc_api.read_with_paging('short_links', list_params.merge(query_read_delete(default: {})).compact),
            sl_shared_data_ws: shared_data
          }
        end

        # Shared implementation for short_link > delete
        def sl_exec_delete(sl_shared_data_ws:, sl_short_list:, sl_link_type:, sl_perm_block:, **)
          one_id = options.instance_identifier(description: 'short link id')
          if sl_link_type.eql?(:public)
            found = sl_short_list[:items].find{ |item| item['id'].eql?(one_id)}
            raise BadIdentifier.new('Short link', one_id) if found.nil?
            sl_perm_block&.call(:delete, found['resource_id'], nil)
          end
          aoc_api.delete("short_links/#{one_id}", {edit_access: true, json_query: sl_shared_data_ws.to_json})
          Result::Status.new('deleted')
        end

        # Shared implementation for short_link > list
        def sl_exec_list(sl_short_list:, **)
          Result::ObjectList.new(sl_short_list[:items], fields: Formatter.all_but('data'), total: sl_short_list[:total])
        end

        # Shared implementation for short_link > show
        def sl_exec_show(sl_short_list:, **)
          one_id = options.instance_identifier(description: 'short link id')
          found = sl_short_list[:items].find{ |item| item['id'].eql?(one_id)}
          raise BadIdentifier.new('Short link', one_id) if found.nil?
          Result::SingleObject.new(found, fields: Formatter.all_but('data'))
        end

        # Shared implementation for short_link > modify
        def sl_exec_modify(sl_shared_data:, sl_short_list:, sl_link_type:, sl_perm_block:, **)
          raise Cli::BadArgument, 'modify is only available for public short links' unless sl_link_type.eql?(:public)
          one_id = options.instance_identifier(description: 'short link id')
          node_file = sl_shared_data.slice(:node_id, :file_id)
          modify_payload = {edit_access: true, json_query: node_file}
          custom_data = value_create_modify(command: :modify)
          if (pass = custom_data.delete('password'))
            modify_payload[:password_enabled] = true
            modify_payload[:data] = {url_token_data: {password: pass, data: node_file}}
          else
            modify_payload[:password_enabled] = false
          end
          if custom_data.delete('access_levels')
            found = sl_short_list[:items].find{ |item| item['id'].eql?(one_id)}
            raise BadIdentifier.new('Short link', one_id) if found.nil?
            sl_perm_block&.call(:update, found['resource_id'], nil)
          end
          modify_payload.deep_merge!(custom_data)
          aoc_api.update("short_links/#{one_id}", modify_payload)
          Result::Status.new('modified')
        end

        # files > short_link > create|delete|list|show|modify
        def action_files_short_link_create(**ctx) = sl_exec_create(**ctx)
        def action_files_short_link_list(**ctx)   = sl_exec_list(**sl_fetch_list(**ctx))
        def action_files_short_link_show(**ctx)   = sl_exec_show(**sl_fetch_list(**ctx))
        def action_files_short_link_delete(**ctx) = sl_exec_delete(**sl_fetch_list(**ctx), **ctx)
        def action_files_short_link_modify(**ctx) = sl_exec_modify(**sl_fetch_list(**ctx), **ctx)

        # packages > shared_inboxes > short_link > create|delete|list|show|modify
        def action_packages_shared_inboxes_short_link_create(**ctx) = sl_exec_create(**ctx)
        def action_packages_shared_inboxes_short_link_list(**ctx)   = sl_exec_list(**sl_fetch_list(**ctx))
        def action_packages_shared_inboxes_short_link_show(**ctx)   = sl_exec_show(**sl_fetch_list(**ctx))
        def action_packages_shared_inboxes_short_link_delete(**ctx) = sl_exec_delete(**sl_fetch_list(**ctx), **ctx)
        def action_packages_shared_inboxes_short_link_modify(**ctx) = sl_exec_modify(**sl_fetch_list(**ctx), **ctx)

        # files > FILES_COMMANDS (all Gen4 node commands + :transfer)
        FILES_COMMANDS.each do |action|
          define_action_method([:files, action]) do
            execute_nodegen4_command(action, aoc_api.home[:node_id], file_id: aoc_api.home[:file_id], scope: Api::Node::Scope::USER)
          end
        end

        # admin > application > instance > <type> > show|modify
        APP_TYPES.each do |app_type|
          define_action_method([:admin, :application, :instance, app_type, :show]) do |res_id:, **|
            Result::SingleObject.new(aoc_api.read("admin/apps_new/#{app_type}/#{res_id}", query_read_delete))
          end

          define_action_method([:admin, :application, :instance, app_type, :modify]) do |res_id:, **|
            aoc_api.update("admin/apps_new/#{app_type}/#{res_id}", options.get_next_argument('properties', validation: Hash))
            Result::Status.new('modified')
          end
        end

        def action_admin_application_membership_create
          data = options.get_next_argument('membership properties', validation: Hash)
          app_type = data.delete('app_type')
          Aspera.assert_type(app_type, String){'app_type'}
          Aspera.assert_values(app_type.to_sym, APP_TYPES){'app_type'}
          Result::SingleObject.new(aoc_api.create("apps/#{app_type}/app_memberships", data))
        end

        # admin > application > membership > show|delete
        def action_admin_application_membership_show(res_id:, **)
          Result::SingleObject.new(aoc_api.read("apps/app_memberships/#{res_id}", query_read_delete))
        end

        def action_admin_application_membership_delete(res_id:, **)
          aoc_api.delete("apps/app_memberships/#{res_id}")
          Result::Status.new('deleted')
        end

        # admin - setup: change API scope to admin once
        def setup_admin_scope(**)
          change_api_scope(Api::AoC::Scope::ADMIN)
          {}
        end

        # admin > subscription > account
        def action_admin_subscription_account
          org = aoc_api.read('organization')
          result = GraphQL.execute(api_from_options('bss/platform/graphql'), 'bss_subscription_account', {organization_id: org['id']})
          Result::SingleObject.new(result['aoc']['bssSubscription'])
        end

        # admin > subscription > usage
        def action_admin_subscription_usage
          org = aoc_api.read('organization')
          aggregate = options.get_next_argument('aggregation', accept_list: %i[ALL MONTHLY], default: :ALL)
          today = Date.today
          start_date = options.get_next_argument('start date', mandatory: false, default: today.prev_year.strftime('%Y-%m-%d'))
          end_date   = options.get_next_argument('end date',   mandatory: false, default: today.strftime('%Y-%m-%d'))
          result = GraphQL.execute(api_from_options('bss/platform/graphql'), 'bss_subscription_usage', {organization_id: org['id'], aggregate: aggregate, startDate: start_date, endDate: end_date})
          Result::SingleObject.new(result['aoc'])
        end

        # admin > analytics > application_events
        def action_admin_analytics_application_events
          analytics_api = build_analytics_api
          events = analytics_api.read("organizations/#{aoc_api.current_user_info['organization_id']}/application_events")['application_events']
          Result::ObjectList.new(events)
        end

        # admin > analytics > transfers
        def action_admin_analytics_transfers
          analytics_api = build_analytics_api
          event_resource_type = options.get_next_argument('resource', accept_list: %i[organizations users nodes])
          event_resource_id = options.get_next_argument("#{event_resource_type} identifier", mandatory: false) ||
            case event_resource_type
            when :organizations then aoc_api.current_user_info['organization_id']
            when :users         then aoc_api.current_user_info['id']
            when :nodes         then aoc_api.current_user_info['read_only_home_node_id']
            else Aspera.error_unreachable_line
            end
          filter = query_read_delete(default: {})
          filter['limit'] ||= 100
          if options.get_option(:once_only, mandatory: true)
            saved_date = []
            start_date_persistency = PersistencyActionOnce.new(
              manager: persistency,
              data:    saved_date,
              id:      IdGenerator.from_list('aoc_ana_date', options.get_option(:url, mandatory: true), aoc_api.workspace_info[:name], event_resource_type.to_s, event_resource_id)
            )
            start_date_time = saved_date.first
            stop_date_time  = Time.now.utc.strftime('%FT%T.%LZ')
            saved_date[0]   = stop_date_time
            filter['start_time'] = start_date_time unless start_date_time.nil?
            filter['stop_time']  = stop_date_time
          end
          events = analytics_api.read("#{event_resource_type}/#{event_resource_id}/transfers", filter)['transfers']
          start_date_persistency&.save
          events.each{ |tr_event| context.mailer.send_email_template(values: {ev: tr_event})} if !options.get_option(:notify_to).nil?
          Result::ObjectList.new(events)
        end

        # admin > analytics > files
        def action_admin_analytics_files
          analytics_api = build_analytics_api
          event_resource_type = options.get_next_argument('resource', accept_list: %i[organizations users nodes])
          event_resource_id = options.instance_identifier(description: "#{event_resource_type} identifier")
          event_resource_id =
            case event_resource_type
            when :organizations then aoc_api.current_user_info['organization_id']
            when :users         then aoc_api.current_user_info['id']
            when :nodes         then aoc_api.current_user_info['read_only_home_node_id']
            else Aspera.error_unreachable_line
            end if event_resource_id.empty?
          event_uuid = options.instance_identifier(description: 'event uuid')
          filter = query_read_delete(default: {})
          filter['limit'] ||= 100
          events = analytics_api.read("#{event_resource_type}/#{event_resource_id}/transfers/#{event_uuid}/files", filter)['files']
          Result::ObjectList.new(events)
        end

        # Lookup methods for instance_arg: + lookup: on admin resources.
        # One method per non-singleton resource; each delegates to get_resource_id_from_args.
        ADMIN_OBJECTS.reject{ |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton)}.each do |res|
          define_method(:"lookup_aoc_#{res}_id") do |_field, value|
            aoc_api.lookup_with_q(aoc_res_path(res), value: value)['id']
          end
        end

        # admin > <res> > list
        ADMIN_OBJECTS.each do |res|
          define_action_method([:admin, res, :list]) do
            c = aoc_res_cfg(res)
            result_list(c[:path], fields: c[:list_fields])
          end
        end

        # admin > <res> > show
        ADMIN_OBJECTS.reject{ |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton)}.each do |res|
          define_action_method([:admin, res, :show]) do |res_id:, **|
            c = aoc_res_cfg(res)
            Result::SingleObject.new(aoc_api.read("#{c[:path]}/#{res_id}", query_read_delete), fields: Formatter.all_but('certificate'))
          end
        end

        # admin > organization|self > show (singleton)
        %i[organization self].each do |res|
          define_action_method([:admin, res, :show]) do
            Result::SingleObject.new(aoc_api.read(res.to_s, query_read_delete), fields: Formatter.all_but('certificate'))
          end
        end

        # admin > <res> > create
        ADMIN_OBJECTS.reject{ |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton)}.each do |res|
          define_action_method([:admin, res, :create]) do
            c = aoc_res_cfg(res)
            path = c[:path]
            # Special case: client_registration_token has a different creation URL
            path = 'admin/client_registration/token' if path.eql?('admin/client_registration_tokens')
            workspace_id = aoc_api.workspace_info[:id] if c[:require_ws_id]
            do_bulk_operation(command: :create, descr: 'creation data', id_result: c[:id_result], schema: c[:schema]) do |params|
              params['workspace_id'] = workspace_id if c[:require_ws_id] && workspace_id && !params.key?('workspace_id')
              aoc_api.create(path, params)
            end
          end
        end

        # admin > <res> > modify
        ADMIN_OBJECTS.reject{ |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton) || ADMIN_OBJECT_CONFIG.dig(r, :ops)&.then{ |o| !o.include?(:modify)}}.each do |res|
          define_action_method([:admin, res, :modify]) do |res_id:, **|
            c = aoc_res_cfg(res)
            changes = options.get_next_argument('properties', validation: Hash, schema: c[:schema])
            do_bulk_operation(command: :modify, values: res_id) do |one_id|
              aoc_api.update("#{c[:path]}/#{one_id}", changes)
              {'id' => one_id}
            end
          end
        end

        # admin > <res> > delete
        ADMIN_OBJECTS.reject do |r|
          cfg = ADMIN_OBJECT_CONFIG.fetch(r, {})
          cfg[:singleton] || (cfg[:ops] && !cfg[:ops].include?(:delete))
        end.each do |res|
          define_action_method([:admin, res, :delete]) do |res_id:, **|
            c = aoc_res_cfg(res)
            do_bulk_operation(command: :delete, values: res_id) do |one_id|
              aoc_api.delete("#{c[:path]}/#{one_id}")
              {'id' => one_id}
            end
          end
        end

        # user > contacts > list|show|create|modify|delete (same API path as admin > contact)
        Operations::ALL.each do |op|
          define_action_method([:user, :contacts, op]) do |**ctx|
            send(CommandSpec.action_method([:admin, :contact, op]), **ctx)
          end
        end

        # admin > client > set_pub_key
        def action_admin_client_set_pub_key(res_id:, **)
          c = aoc_res_cfg(:client)
          the_private_key = options.get_next_argument('private_key PEM value', validation: String)
          the_public_key = OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s
          aoc_api.update("#{c[:path]}/#{res_id}", {jwt_grant_enabled: true, public_key: the_public_key})
          Result::Success.new
        end

        # admin > node > do | bearer_token — setup reuses the generic instance setup
        # (setup_admin_node_instance is auto-generated above, providing res_id:)

        # admin > node > do > <FILES_COMMAND>
        FILES_COMMANDS.each do |cmd|
          define_action_method([:admin, :node, :do, cmd]) do |res_id:, **|
            execute_nodegen4_command(cmd, res_id, scope: Api::Node::Scope::ADMIN)
          end
        end

        # admin > node > bearer_token
        def action_admin_node_bearer_token(res_id:, **)
          node_api = aoc_api.node_api_from(node_id: res_id, scope: options.get_next_argument('scope', default: Api::Node::Scope::ADMIN))
          Result::Text.new(node_api.oauth.authorization)
        end

        # admin > workspace > dropbox — res_id: already in ctx via instance_arg:
        def setup_admin_workspace_dropbox(res_id:, **)
          {ws_res_id: res_id}
        end

        # admin > workspace > dropbox > list
        def action_admin_workspace_dropbox_list(ws_res_id:, **)
          query = options.get_option(:query) || {}
          Result::ObjectList.new(aoc_api.read('dropboxes', query.merge({'workspace_id' => ws_res_id})), fields: %w[id name description])
        end

        # admin > workspace > shared_folder — res_id: already in ctx via instance_arg:
        def setup_admin_workspace_shared_folder(res_id:, **)
          resource_instance_path = "#{aoc_res_path(:workspace)}/#{res_id}"
          query = options.get_option(:query) || Api::AoC.workspace_access(res_id).merge({'admin' => true})
          shared_folders = aoc_api.read_with_paging("#{resource_instance_path}/permissions", query)[:items]
          {ws_res_id: res_id, shared_folders: shared_folders}
        end

        # admin > workspace > shared_folder > list
        def action_admin_workspace_shared_folder_list(shared_folders:, **)
          Result::ObjectList.new(shared_folders, fields: %w[id node_name node_id file_id file.path tags.aspera.files.workspace.share_as])
        end

        # admin > workspace > shared_folder > node|member — sf_id: already in ctx via instance_arg:
        def resolve_sf_item(shared_folders:, sf_id:, **)
          sf_item = shared_folders.find{ |i| i['id'].eql?(sf_id)}
          Aspera.assert(sf_item, 'shared folder not found')
          {sf_item: sf_item}
        end

        alias_method :setup_admin_workspace_shared_folder_node,   :resolve_sf_item
        alias_method :setup_admin_workspace_shared_folder_member, :resolve_sf_item

        # admin > workspace > shared_folder > node
        def action_admin_workspace_shared_folder_node(sf_item:, **)
          command_repo = options.get_next_command(FILES_COMMANDS)
          execute_nodegen4_command(command_repo, sf_item['node_id'], file_id: sf_item['file_id'], scope: Api::Node::Scope::ADMIN)
        end

        # admin > workspace > shared_folder > member > list
        def action_admin_workspace_shared_folder_member_list(ws_res_id:, sf_item:, **)
          node_api = aoc_api.node_api_from(
            node_id:        sf_item['node_id'],
            workspace_id:   ws_res_id,
            workspace_name: nil,
            scope:          Api::Node::Scope::USER
          )
          result = node_api.read('permissions', {'file_id' => sf_item['file_id'], 'tag' => "aspera.files.workspace.id=#{ws_res_id}"})
          result.each do |item|
            item['member'] = begin
              if Api::AoC.workspace_access?(item)
                {'name' => '[Internal permission]'}
              else
                aoc_api.read("admin/#{item['access_type']}s/#{item['access_id']}") rescue {'name' => 'not found'}
              end
            rescue => e
              {'name' => e.to_s}
            end
          end
          # TODO : read users and group name and add, if query "include_members"
          Result::ObjectList.new(result, fields: %w[access_type access_id access_level last_updated_at member.name member.email member.system_group_type member.system_group])
        end

        # admin > user > preferences|notifications > show|modify
        # (setup_admin_user_instance is auto-generated, providing res_id:)
        %i[preferences notifications].each do |pref|
          pref_path = pref.eql?(:preferences) ? 'user_interaction_preferences' : 'notification_preferences'
          define_action_method([:admin, :user, pref, :show]) do |res_id:, **|
            Result::SingleObject.new(aoc_api.read("#{aoc_res_path(:user)}/#{res_id}/#{pref_path}"))
          end
          define_action_method([:admin, :user, pref, :modify]) do |res_id:, **|
            aoc_api.update("#{aoc_res_path(:user)}/#{res_id}/#{pref_path}", options.get_next_argument('properties', validation: Hash))
            Result::Status.new('modified')
          end
        end

        # automation > workflows > CRUD operations
        Operations::ALL.each do |op|
          define_action_method([:automation, :workflows, op]) do
            entity_execute(api: @automation_api, entity: 'workflows', command: op)
          end
        end

        # automation > workflows > action > * (TODO: not fully implemented)
        %i[list create show].each do |cmd|
          define_action_method([:automation, :workflows, :action, cmd]) do
            wf_id = options.instance_identifier
            Log.log.warn{"Not implemented: #{cmd}"}
            step = @automation_api.create('steps', {'workflow_id' => wf_id})
            @automation_api.update("workflows/#{wf_id}", {'step_order' => [step['id']]})
            action = @automation_api.create('actions', {'step_id' => step['id'], 'type' => 'manual'})
            @automation_api.update("steps/#{step['id']}", {'action_order' => [action['id']]})
            Result::SingleObject.new(@automation_api.read("workflows/#{wf_id}"))
          end
        end

        def action_gateway
          require 'aspera/faspex_gw'
          parameters = value_create_modify(command: :gateway, default: {}).symbolize_keys
          uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
          server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
          Aspera.assert(parameters.except(*WebServerSimple::PARAMS).empty?){"unexpected parameters: #{parameters.except(*WebServerSimple::PARAMS).keys}"}
          server.mount(uri.path, Faspex4GWServlet, aoc_api, aoc_api.workspace_info[:id])
          server.start
          return Result::Status.new('Gateway terminated')
        end
      end
    end
  end
end
