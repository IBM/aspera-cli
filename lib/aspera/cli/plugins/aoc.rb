# frozen_string_literal: true

require 'aspera/schema/registry'
require 'aspera/cli/plugins/oauth'
require 'aspera/cli/plugins/node'
require 'aspera/cli/plugins/ats'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/special_values'
require 'aspera/cli/wizard'
require 'aspera/agent/node'
require 'aspera/transfer/result'
require 'aspera/transfer/spec'
require 'aspera/api/aoc'
require 'aspera/api/node'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/assert'
require 'aspera/graphql'
require 'securerandom'
require 'date'
require 'aspera/rainbow'
using Rainbow

module Aspera
  module Cli
    module Plugins
      class Aoc < Oauth # rubocop:disable Metrics/ClassLength
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
            Aspera.assert_array_all(fld, String, type: BadArgument) { 'fld' }
            Aspera.assert_values(fld.length, [1, 2]) { 'fld length' }
            folder = Environment.instance.sanitized_filename(package_info[fld[0]])
            if seq
              folder = next_available_folder(folder, always: !opt)
            elsif fld[1] && (Dir.exist?(folder) || !opt)
              # NOTE: it might already exist
              folder = "#{folder}.#{Environment.instance.sanitized_filename(fld[1])}"
            end
            File.join(destination_folder, folder)
          end

          # @return [String] AoC REST path for an admin resource type
          def aoc_res_path(res)
            cfg = ADMIN_OBJECT_CONFIG.fetch(res, {})
            return cfg[:path] if cfg[:path]
            "#{res}s".gsub(/ys$/, 'ies')
          end

          # @return [Hash] {path:, ops:, id_result:, require_ws_id:, list_fields:, schema:, query_component:}
          def aoc_res_cfg(res)
            cfg    = ADMIN_OBJECT_CONFIG.fetch(res, {})
            path   = aoc_res_path(res)
            ops    = cfg[:ops] || (Base::Operations::ALL + (cfg[:extra_ops] || []))
            schema = cfg[:create_schema] == false ? nil : Schema::Registry.req_body(Schema::Registry::AOC, "#{path}.post")
            {
              path:            path,
              ops:             ops,
              id_result:       cfg[:id_result] || 'id',
              require_ws_id:   cfg[:require_ws_id] || false,
              list_fields:     cfg.key?(:list_fields) ? cfg[:list_fields] : %w[id name],
              schema:          schema,
              query_component: Schema::Registry::AOC
            }
          end

          # DSL helper: register the 5 short_link leaf commands under the given parent path
          # and define the corresponding action methods on `base`.
          # @param base        [Class]         the plugin class
          # @param parent_path [Array<Symbol>] full path ending with :short_link
          def register_short_link_commands(base, parent_path)
            base.commands_under(parent_path) do
              base.command(
                :create, description: base.operation_description(:create, 'short link'),
                arguments: [{name: :short_link, type: Hash, mandatory: false, default: {}}]
              )
              base.command(
                :modify, description: base.operation_description(:modify, 'short link'),
                arguments: [{name: :short_link_id, type: :identifier}, {name: :short_link, type: Hash, mandatory: false, default: {}}]
              )
              base.command(:list, description: base.operation_description(:list, 'short link'))
              base.command(
                :show, description: base.operation_description(:show, 'short link'),
                arguments: [{name: :short_link_id, type: :identifier}]
              )
              base.command(
                :delete, description: base.operation_description(:delete, 'short link'),
                arguments: [{name: :short_link_id, type: :identifier}]
              )
            end
            base.define_action_method(parent_path + [:create]) do |short_link: {}, **ctx|
              sl_exec_create(short_link, **ctx)
            end
            base.define_action_method(parent_path + [:list]) do |**ctx|
              sl_exec_list(**sl_fetch_list(**ctx))
            end
            base.define_action_method(parent_path + [:show]) do |**ctx|
              sl_exec_show(**sl_fetch_list(**ctx))
            end
            base.define_action_method(parent_path + [:delete]) do |**ctx|
              sl_exec_delete(**sl_fetch_list(**ctx), **ctx)
            end
            base.define_action_method(parent_path + [:modify]) do |short_link: {}, **ctx|
              sl_exec_modify(short_link, **sl_fetch_list(**ctx), **ctx)
            end
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
          options.declare(:use_generic_client, description: 'Wizard: AoC: use global or org specific jwt client id', allowed: Type::BOOLEAN, default: Api::AoC.saas_url?(app_url))
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
        option :validate_metadata, description: 'Validate shared inbox metadata', allowed: Type::BOOLEAN, default: true
        option :package_folder,    schema: Schema::Registry::PACKAGE_FOLDER_OPTIONS

        use_options Node

        def initialize(**_)
          super
          @cache_workspace_info = nil
          @cache_home_node_file = nil
          @cache_api_aoc = nil
          @scope = Api::AoC::Scope::USER
          options.parse_options!
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
          if !workspace.nil? && (m = Parser.percent_selector(workspace))
            case m[:field]
            when 'name' then api.ws_ids[:name] = m[:value]
            when 'id' then api.ws_ids[:id] = m[:value]
            else Aspera.error_unexpected_value(m[:field]) { 'workspace selector: only `name` or `id`' }
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
        #   * `workspace_name` [String] (optional) the name, included if `name` is true.
        # @note The key type (String or Symbol) depends on the `string` parameter.
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

        # List all entities, given additional, default and user's queries
        # @param resource_class_path [String]     path to query on API
        # @param fields              [Array, nil] fields to display
        # @param base_query          [Hash]       a query applied always
        # @param default_query       [Hash]       default query unless overridden by user
        # @param query_component     [String, nil] registry component key; when set, --query=help shows filter schema
        # @yieldparam query [Hash] The user's or default query for modification
        def result_list(resource_class_path, fields: nil, base_query: {}, default_query: {}, query_component: nil)
          Aspera.assert_type(base_query, Hash)
          Aspera.assert_type(default_query, Hash)
          qs_path = query_component ? Schema::Registry.query_params(query_component, resource_class_path) : nil
          query = query_read_delete(default: default_query, schema: qs_path)
          # caller may add specific modifications or checks to query
          yield(query) if block_given?
          result = aoc_api.read_with_paging(resource_class_path, base_query.merge(query).compact)
          return Result::ObjectList.new(result[:items], fields: fields, total: result[:total])
        end

        # Translates `dropbox_name` to `dropbox_id` and fills current workspace_id
        def resolve_dropbox_name_default_ws_id(query)
          if query.key?('dropbox_name')
            # convenience: specify name instead of id
            Aspera.assert(!query.key?('dropbox_id'), type: BadArgument) { 'Use field dropbox_name or dropbox_id, not both' }
            # TODO : craft a query that looks for dropbox only in current workspace
            query['dropbox_id'] = aoc_api.lookup_with_q('dropboxes', value: query.delete('dropbox_name'))['id']
          end
          workspace_id_hash(query, string: true)
          # by default show dropbox packages only for dropboxes
          query['exclude_dropbox_packages'] = !query.key?('dropbox_id') unless query.key?('exclude_dropbox_packages')
        end

        # List all packages from the API using the current `--query` option.
        # The special `max` key is extracted *before* the API call and returned separately,
        # so callers that apply a post-API filter (e.g. once_only) can enforce the limit
        # after filtering rather than before.
        # @return [Array(Hash, Integer, nil)] [{items:,total:} paging result, max (or nil)]
        def list_all_packages_with_query
          query = query_read_delete(default: {}, schema: Schema::Registry.query_params(Schema::Registry::AOC, 'packages'))
          Aspera.assert_type(query, Hash) { 'query' }
          PACKAGE_RECEIVED_BASE_QUERY.each { |k, v| query[k] = v unless query.key?(k) }
          resolve_dropbox_name_default_ws_id(query)
          # Extract `max` before paging so callers can apply it after post-API filtering
          max_items = query.delete(RestList::MAX_ITEMS)&.to_i
          return aoc_api.read_with_paging('packages', query.compact), max_items
        end

        # Arguments of the node-to-node `transfer` command (files, admin node do, shared folder node)
        TRANSFER_ARGS = [{name: :direction, allowed: %i[push pull]}, {name: :source_folder, type: String}].freeze
        # Mount of the Node plugin Gen4 commands (`node access_keys do <id> ...`), instance: set per mount point
        NODE_GEN4_MOUNT = {plugin: Node, at: %i[access_keys do]}.freeze
        # Package identifier argument, `%name:` selector (lookup method shared with `admin package`)
        PACKAGE_ID_ARG = {name: :package_id, type: :identifier, lookup: :lookup_aoc_package_id}.freeze
        private_constant :TRANSFER_ARGS, :NODE_GEN4_MOUNT, :PACKAGE_ID_ARG

        # Node API on a Gen4 node, and its root file id.
        # @param node_id [String]      Node identifier
        # @param file_id [String, nil] Root file id; if nil, the access key root file id is used
        # @param scope   [String, nil] node scope (Api::Node::Scope::USER/ADMIN), or nil (requires secret)
        # @return [Array(Api::Node, String)]
        def nodegen4_root(node_id, file_id: nil, scope: nil)
          node_api = aoc_api.node_api_from(
            node_id:        node_id,
            scope:          scope,
            **workspace_id_hash(name: true)
          )
          file_id = node_api.read("access_keys/#{node_api.app_info.node_info['access_key']}")['root_file_id'] if file_id.nil?
          [node_api, file_id]
        end

        # Node plugin for Gen4 commands on a node, with the seed ctx of its `access_keys do` sub-tree.
        # Used as `instance:` of mounts of NODE_GEN4_MOUNT.
        # @return [Array(Node, Hash)]
        def nodegen4_plugin(node_id, file_id: nil, scope: nil)
          node_api, file_id = nodegen4_root(node_id, file_id: file_id, scope: scope)
          [Node.new(context: context, api: node_api), {do_root_file_id: file_id}]
        end

        # Node-to-node transfer: client side is agent, server side is transfer server, in same workspace.
        # @param direction     [Symbol] :push or :pull
        # @param source_folder [String] source folder
        # @return [Result]
        def nodegen4_transfer(node_id, direction:, source_folder:, file_id: nil, scope: nil)
          top_node_api, file_id = nodegen4_root(node_id, file_id: file_id, scope: scope)
          case direction
          when :push
            client_direction = Transfer::Spec::DIRECTION_SEND
            client_folder = source_folder
            server_folder = transfer.destination_folder(client_direction)
          when :pull
            client_direction = Transfer::Spec::DIRECTION_RECEIVE
            client_folder = transfer.destination_folder(client_direction)
            server_folder = source_folder
          else Aspera.error_unexpected_value(direction) { 'direction' }
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
          Runner.result_transfer(transfer.start(server_apifid.node_api.transfer_spec_gen4(
            server_apifid.file_id,
            client_direction,
            add_ts
          )))
        end

        # Execute an action on admin resources
        # @param resource_type [Symbol] One of ADMIN_OBJECTS
        # Per-resource configuration for admin CRUD resources.
        # Keys: path, list_fields, id_result, require_ws_id, create_schema, extra_ops, singleton, op_setup, op_mount, op_descriptions
        # op_setup: Hash of op => setup method name, used for ops that require consuming an instance identifier.
        #   For Operations::INSTANCE ops (show/modify/delete), use the auto-generated :setup_admin_<res>_instance.
        #   For extra_ops that are instance ops, specify explicitly (or rely on the auto-generated one).
        # op_mount: Hash of op => mount: of that op's node.
        # op_descriptions: Hash of op => description, for ops other than standard ones.
        ADMIN_OBJECT_CONFIG = {
          client:                    {
            extra_ops:       %i[set_pub_key],
            extra_op_args:   {set_pub_key: [{name: :private_key_pem, type: String}]},
            op_descriptions: {set_pub_key: 'Set public key of client from a private key'}
          },
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
          node:                      {
            list_fields:     %w[id name host access_key],
            extra_ops:       %i[do bearer_token update_status],
            extra_op_args:   {bearer_token: [{name: :scope, mandatory: false, default: nil}]},
            op_mount:        {do: NODE_GEN4_MOUNT.merge(instance: :admin_node_do_plugin)},
            op_descriptions: {do: 'Execute command on node', bearer_token: 'Generate bearer token for node', update_status: 'Ask AoC to scan node and update its status'}
          },
          operation:                 {list_fields: %w[id type status created_at updated_at workspace_id user_id workspace_membership_id group_membership_id], ops: %i[list show modify]},
          organization:              {singleton: true},
          package:                   {},
          saml_configuration:        {create_schema: false},
          self:                      {singleton: true, op_descriptions: {show: 'Show current user'}},
          short_link:                {list_fields: %w[id short_url data.url_token_data.purpose password_enabled password_protected updated_by_user_id updated_at]},
          user:                      {
            list_fields:     %w[id name email],
            extra_ops:       %i[preferences notifications],
            op_setup:        {preferences: :setup_admin_user_instance, notifications: :setup_admin_user_instance},
            op_descriptions: {preferences: 'Manage user preferences', notifications: 'Manage user notification preferences'}
          },
          workspace:                 {
            extra_ops:       %i[shared_folder dropbox],
            op_setup:        {shared_folder: :setup_admin_workspace_shared_folder, dropbox: :setup_admin_workspace_dropbox},
            op_descriptions: {shared_folder: 'Manage shared folders of workspace', dropbox: 'Manage shared inboxes of workspace'}
          },
          workspace_membership:      {list_fields: %w[id workspace_id member_type member_id]}
        }.freeze
        private_constant :ADMIN_OBJECT_CONFIG

        # Instance delegators so instance methods can call aoc_res_path/aoc_res_cfg without self.class.
        def aoc_res_path(res) = self.class.aoc_res_path(res)
        def aoc_res_cfg(res)  = self.class.aoc_res_cfg(res)

        # Known fixed set of AoC application types (verified against API: activity, automation, files, packages)
        APP_TYPES = %i[activity automation files packages].freeze

        ADMIN_ACTIONS = (%i[bearer_token application ats usage_reports analytics subscription auth_providers] + ADMIN_OBJECTS).freeze

        # Build analytics REST API (shared by action_admin_analytics_*)
        def build_analytics_api
          Rest.new(**aoc_api.params.deep_merge({
            base_url: "#{aoc_api.base_url.gsub('/api/v1', '')}/analytics/v2",
            auth:     {params: {scope: Api::AoC::Scope::ADMIN_USER}}
          }))
        end

        # Compute short-link purposes from shared_data keys and link_type.
        # @param shared_data [Hash] :dropbox_id + :name or :file_id + :node_id
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
          skip_package = skip_ids_persistency.data.to_h { |i| [i, true] }
          all_packages.reject! { |pkg| skip_package[pkg['id']] }
        end

        # --- DSL command declarations ---

        # Root-level commands
        command :reminder, description: 'Send reminder email with list of orgs'
        command(
          :servers, description: 'List AoC servers (no auth)',
          action: lambda do |**|
            no_auth_api = Api::AoC.new(url: options.get_option(:url), auth: :none)
            Result::ObjectList.new(no_auth_api.read('servers'))
          end
        )
        command :bearer_token,      description: 'Show bearer token',
          action: ->(**) { Result::Text.new(aoc_api.oauth.authorization) }
        command :organization,      description: 'Show organization info',
          action: ->(**) { Result::SingleObject.new(aoc_api.read('organization')) }
        command :tier_restrictions, description: 'Show tier restrictions',
          action: ->(**) { Result::SingleObject.new(aoc_api.read('tier_restrictions')) }
        command :user,              description: 'User commands'
        # Node Gen4 read-only commands on packages: `packages <command> <package_id> ...`
        command :packages,          description: 'Package commands', setup: :setup_workspace_display,
          mount: NODE_GEN4_MOUNT.merge(instance: :package_node_plugin, only: Node::NODE4_READ_ACTIONS, arguments: [PACKAGE_ID_ARG])
        command :files,             description: 'Files commands (workspace-aware)', setup: :setup_workspace_display,
          mount: NODE_GEN4_MOUNT.merge(instance: :files_node_plugin)
        command :admin, description: 'Administration commands', setup: :setup_admin_scope
        commands_under :admin do
          command :bearer_token,   description: 'Show admin bearer token',
            action: ->(**) { Result::Text.new(aoc_api.oauth.authorization) }
          command :application,    description: 'Manage applications'
          command :ats, description: 'Manage ATS (Aspera Transfer Service)',
            mount: {plugin: Ats, instance: :build_ats_plugin}
          command :usage_reports,  description: 'List usage reports',
            action: ->(**) { result_list('usage_reports', base_query: workspace_id_hash) }
          command :auth_providers, description: 'Manage auth providers'
          command :subscription,   description: 'Show subscription info'
          command :analytics,      description: 'Query analytics'
          ADMIN_OBJECTS.each do |res|
            cfg            = ADMIN_OBJECT_CONFIG.fetch(res, {})
            op_setup       = cfg[:op_setup] || {}
            op_mount       = cfg[:op_mount] || {}
            extra_op_args  = cfg[:extra_op_args] || {}
            is_singleton   = cfg[:singleton]
            id_arg_spec    = is_singleton ? [] : [{name: :"#{res}_id", type: :identifier, lookup: :"lookup_aoc_#{res}_id"}]
            ops            = if cfg[:ops]
              cfg[:ops]
            elsif is_singleton
              %i[show]
            else
              Operations::ALL + (cfg[:extra_ops] || [])
            end
            command res, description: "Manage #{res.to_s.tr('_', ' ')}"
            commands_under res do
              ops.each do |op|
                extra_setup = op_setup[op]
                base_attrs = extra_setup ? {setup: extra_setup} : {}
                base_attrs[:mount] = op_mount[op] if op_mount.key?(op)
                extra_arg_list =
                  if !is_singleton && op.eql?(:create)
                    c = aoc_res_cfg(res)
                    [{name: res, type: Hash, bulk: true, schema: c[:schema]}]
                  elsif !is_singleton && op.eql?(:modify)
                    c = aoc_res_cfg(res)
                    [{name: res, type: Hash, schema: c[:schema]}]
                  elsif extra_op_args.key?(op)
                    extra_op_args[op]
                  else
                    []
                  end
                # For non-global ops, prepend the identifier spec
                arg_list = (Operations::GLOBAL.include?(op) ? [] : id_arg_spec) + extra_arg_list
                merged = arg_list.empty? ? base_attrs : base_attrs.merge(arguments: arg_list)
                # Attach query_schema (full path) to :list CommandSpec so --help shows the tip
                if op.eql?(:list)
                  c = aoc_res_cfg(res)
                  merged = merged.merge(query_schema: Schema::Registry.query_params(c[:query_component], c[:path]))
                end
                description = cfg.dig(:op_descriptions, op) ||
                  (Operations::ALL.include?(op) ? operation_description(op, entity_noun(res, singular: false)) : op.to_s.tr('_', ' ').capitalize)
                command op, description: description, **merged
              end
            end
          end
        end
        # admin > workspace > shared_folder sub-tree
        commands_under %i[admin workspace shared_folder] do
          command :list,   description: 'List shared folders',
            action: ->(shared_folders:, **) { Result::ObjectList.new(shared_folders, fields: %w[id node_name node_id file_id file.path tags.aspera.files.workspace.share_as]) }
          command :node,   description: 'Execute node command on shared folder',
            arguments: [{name: :shared_folder_id, type: :identifier}],
            setup: :setup_admin_workspace_shared_folder_node,
            mount: NODE_GEN4_MOUNT.merge(instance: :admin_workspace_shared_folder_node_plugin)
          command :member, description: 'Show folder members',
            arguments: [{name: :shared_folder_id, type: :identifier}],
            setup: :setup_admin_workspace_shared_folder_member
        end
        # admin > workspace > shared_folder > node: Gen4 commands are mounted, plus node-to-node transfer
        commands_under %i[admin workspace shared_folder node] do
          command :transfer, description: 'Transfer files (node-to-node)', arguments: TRANSFER_ARGS,
            action: ->(sf_item:, direction:, source_folder:, **) { nodegen4_transfer(sf_item['node_id'], file_id: sf_item['file_id'], scope: Api::Node::Scope::ADMIN, direction: direction, source_folder: source_folder) }
        end
        commands_under %i[admin workspace shared_folder member] do
          command :list, description: 'List members of a shared folder'
        end
        # admin > workspace > dropbox sub-tree
        commands_under %i[admin workspace dropbox] do
          command(
            :list, description: 'List dropboxes in workspace',
            action: lambda do |ws_res_id:, **|
              query = options.get_option(:query) || {}
              Result::ObjectList.new(aoc_api.read('dropboxes', query.merge({'workspace_id' => ws_res_id})), fields: %w[id name description])
            end
          )
        end
        # admin > node > do: Gen4 commands are mounted (op_mount), plus node-to-node transfer
        commands_under %i[admin node do] do
          command :transfer, description: 'Transfer files (node-to-node)', arguments: TRANSFER_ARGS,
            action: ->(node_id:, direction:, source_folder:, **) { nodegen4_transfer(node_id, scope: Api::Node::Scope::ADMIN, direction: direction, source_folder: source_folder) }
        end
        # admin > user > preferences|notifications sub-trees
        %i[preferences notifications].each do |pref|
          commands_under [:admin, :user, pref] do
            command :show,   description: "Show user #{pref}"
            command :modify, description: "Modify user #{pref}",
              arguments: [{name: pref, type: Hash}]
          end
        end
        commands_under %i[admin auth_providers] do
          command :list, description: 'List auth providers',
            action: ->(**) { result_list('admin/auth_providers') }
          command :update, description: 'Update auth provider', action: ->(**) { Aspera.error_not_implemented }
        end
        commands_under %i[admin subscription] do
          command(
            :account, description: 'Show subscription account',
            action: lambda do |**|
              org = aoc_api.read('organization')
              result = GraphQL.execute(api_from_options('bss/platform/graphql'), 'bss_subscription_account', {organization_id: org['id']})
              Result::SingleObject.new(result['aoc']['bssSubscription'])
            end
          )
          command :usage, description: 'Show subscription usage',
            arguments: [
              {name: :aggregate,   mandatory: false, default: :ALL, allowed: %i[ALL MONTHLY]},
              {name: :start_date,  mandatory: false, default: nil},
              {name: :end_date,    mandatory: false, default: nil}
            ]
        end
        commands_under %i[admin analytics] do
          command(
            :application_events, description: 'List application events',
            action: lambda do |**|
              events = build_analytics_api.read("organizations/#{aoc_api.current_user_info['organization_id']}/application_events")['application_events']
              Result::ObjectList.new(events)
            end
          )
          command :transfers,          description: 'List transfer events',
            arguments: [
              {name: :event_resource_type, mandatory: true,  allowed: %i[organizations users nodes]},
              {name: :event_resource_id,   mandatory: false, default: nil}
            ]
          command :files,              description: 'List file events',
            arguments: [
              {name: :event_resource_type, mandatory: true, allowed: %i[organizations users nodes]},
              {name: :event_resource_id,   mandatory: true},
              {name: :event_uuid,          mandatory: true}
            ]
        end
        # application sub-commands
        commands_under %i[admin application] do
          command :types,      description: 'List application types',
            action: ->(**) { Result::ObjectList.new(aoc_api.read('admin/apps')) }
          command :settings,   description: 'Manage per-app-type settings'
          command :instance,   description: 'Manage app instances'
          command :membership, description: 'Manage app memberships'
        end
        APP_SETTINGS_PATH = %i[admin application settings].freeze
        APP_INSTANCE_PATH = %i[admin application instance].freeze
        private_constant :APP_SETTINGS_PATH, :APP_INSTANCE_PATH
        commands_under APP_SETTINGS_PATH do
          APP_TYPES.each do |app_type|
            command app_type, description: "Settings for #{app_type} app"
            commands_under app_type do
              command :show, description: "Show #{app_type} settings",
                action: ->(**) { Result::SingleObject.new(aoc_api.read("/apps/#{app_type}/settings")) }
              command(
                :modify, description: "Modify #{app_type} settings",
                arguments: [{name: :settings, type: Hash}],
                action: lambda do |settings:, **|
                  aoc_api.update("/apps/#{app_type}/settings", settings)
                  Result::Status.new('modified')
                end
              )
            end
          end
        end
        commands_under APP_INSTANCE_PATH do
          command :list, description: 'List app instances'
          APP_TYPES.each do |app_type|
            command app_type, description: "Show or modify a #{app_type} instance"
            commands_under app_type do
              command :show,   description: "Show #{app_type} instance",
                arguments: [{name: :instance_id, type: :identifier}]
              command :modify, description: "Modify #{app_type} instance",
                arguments: [{name: :instance_id, type: :identifier}, {name: :instance, type: Hash}]
            end
          end
        end
        commands_under %i[admin application membership] do
          command :list, description: 'List app memberships', action: ->(**) { result_list('apps/app_memberships') }
          command :show, description: 'Show an app membership', arguments: [{name: :membership_id, type: :identifier}],
            action: ->(membership_id:, **) { Result::SingleObject.new(aoc_api.read("apps/app_memberships/#{membership_id}", query_read_delete)) }
          command(
            :delete, description: 'Delete an app membership', arguments: [{name: :membership_id, type: :identifier}],
            action: lambda do |membership_id:, **|
              aoc_api.delete("apps/app_memberships/#{membership_id}")
              Result::Status.new('deleted')
            end
          )
          command :create, description: 'Create an app membership', arguments: [{name: :membership, type: Hash}]
        end
        command :automation,        description: 'Automation commands (BETA)', setup: :setup_automation_api
        command :gateway,           description: 'Start AoC Faspex4 gateway',
          arguments: [{name: :parameters, type: Hash, mandatory: false, default: {}}]

        # user sub-commands
        commands_under :user do
          commands_under :workspaces, description: "User's workspaces" do
            command :list,    description: 'List workspaces', action: ->(**) { result_list('workspaces', fields: %w[id name]) }
            command :current, description: 'Show current workspace', action: ->(**) { Result::SingleObject.new(aoc_api.workspace_info) }
          end
          commands_under :profile, description: "Manager user's profile" do
            command :show, description: 'Show user profile', action: ->(**) { Result::SingleObject.new(aoc_api.current_user_info(exception: true)) }
            command(
              :modify, description: 'Modify user profile',
              arguments: [{name: :profile, type: Hash}],
              action: lambda do |profile:, **|
                aoc_api.update("users/#{aoc_api.current_user_info(exception: true)['id']}", profile)
                Result::Status.new('modified')
              end
            )
          end
          command :preferences,   description: 'User interaction preferences'
          command :notifications, description: 'Notification preferences'
          command :contacts,      description: 'Manage contacts'
          # user > contacts sub-commands (same CRUD as admin > contact)
          commands_under %i[contacts] do
            contact_id = {name: :contact_id, type: :identifier, lookup: :lookup_aoc_contact_id}
            contact_schema = aoc_res_cfg(:contact)[:schema]
            command :list,   description: operation_description(:list, 'contact')
            command :show,   description: operation_description(:show, 'contact'), arguments: [contact_id]
            command :create, description: operation_description(:create, 'contact'), arguments: [{name: :contact, type: Hash, bulk: true, schema: contact_schema}]
            command :modify, description: operation_description(:modify, 'contact'), arguments: [contact_id, {name: :contact, type: Hash, schema: contact_schema}]
            command :delete, description: operation_description(:delete, 'contact'), arguments: [contact_id]
          end
          command :settings, description: 'Manage client settings'
          commands_under %i[settings] do
            crud_commands api: :aoc_api, entity: 'client_settings', name: 'client setting'
          end
        end

        commands_under %i[user preferences] do
          command(
            :show, description: 'Show user preferences',
            action: lambda do |**|
              user_id = aoc_api.current_user_info(exception: true)['id']
              Result::SingleObject.new(aoc_api.read("users/#{user_id}/user_interaction_preferences"))
            end
          )
          command(
            :modify, description: 'Modify user preferences',
            arguments: [{name: :preferences, type: Hash}],
            action: lambda do |preferences:, **|
              user_id = aoc_api.current_user_info(exception: true)['id']
              aoc_api.update("users/#{user_id}/user_interaction_preferences", preferences)
              Result::Status.new('modified')
            end
          )
        end

        commands_under %i[user notifications] do
          command(
            :show, description: 'Show notification preferences',
            action: lambda do |**|
              user_id = aoc_api.current_user_info(exception: true)['id']
              Result::SingleObject.new(aoc_api.read("users/#{user_id}/notification_preferences"))
            end
          )
          command(
            :modify, description: 'Modify notification preferences',
            arguments: [{name: :notifications, type: Hash}],
            action: lambda do |notifications:, **|
              user_id = aoc_api.current_user_info(exception: true)['id']
              aoc_api.update("users/#{user_id}/notification_preferences", notifications)
              Result::Status.new('modified')
            end
          )
        end

        # packages sub-commands — instance commands consume package_id
        # Not `crud_commands`: `list` has its own query and `once_only` persistency.
        commands_under :packages do
          command :shared_inboxes, description: 'Shared inbox commands'
          command :send, description: 'Send a package', transfer_paths: :send,
            arguments: [{name: :package, type: Hash, schema: Schema::Registry.req_body(Schema::Registry::AOC, 'packages.post')}]
          command :receive, description: 'Receive packages', aliases: [:recv], transfer_paths: :receive,
            arguments: [PACKAGE_ID_ARG]
          command :list, description: 'List packages'
          command :show, description: 'Show a package',
            arguments: [PACKAGE_ID_ARG],
            action: ->(package_id:, **) { Result::SingleObject.new(aoc_api.read("packages/#{package_id}")) }
          command :delete, description: 'Delete packages',
            arguments: [PACKAGE_ID_ARG.merge(bulk: true)]
          command(
            :modify, description: 'Modify a package',
            arguments: [PACKAGE_ID_ARG, {name: :package, type: Hash}],
            action: lambda do |package:, package_id:, **|
              aoc_api.update("packages/#{package_id}", package)
              Result::Status.new('modified')
            end
          )
        end

        commands_under %i[packages shared_inboxes] do
          command :list,       description: 'List shared inboxes'
          command :show,       description: 'Show a shared inbox',
            arguments: [{name: :dropbox_id, type: :identifier, lookup: :lookup_aoc_dropbox_id}],
            action: ->(dropbox_id:, **) { Result::SingleObject.new(aoc_api.read("dropboxes/#{dropbox_id}")) }
          command :short_link, description: 'Manage shared inbox short links',
            arguments: [{name: :link_type, allowed: %i[public private]}, {name: :dropbox_id, type: :identifier, lookup: :lookup_aoc_dropbox_id}],
            setup: :setup_packages_short_link
        end
        # packages > shared_inboxes > short_link sub-commands
        register_short_link_commands(self, %i[packages shared_inboxes short_link])

        # files sub-commands: Gen4 commands are mounted, plus AoC-specific commands
        commands_under :files do
          command :short_link, description: 'Manage file short link',
            arguments: [{name: :folder, type: String}, {name: :link_type, allowed: %i[public private]}],
            setup: :setup_files_short_link
          command :transfer, description: 'Transfer files (node-to-node)', arguments: TRANSFER_ARGS,
            action: ->(direction:, source_folder:, **) { nodegen4_transfer(aoc_api.home[:node_id], file_id: aoc_api.home[:file_id], scope: Api::Node::Scope::USER, direction: direction, source_folder: source_folder) }
        end
        # files > short_link sub-commands
        register_short_link_commands(self, %i[files short_link])

        # automation sub-commands
        # Automation API: a workflow has ordered steps (step_order), a step has ordered actions (action_order)
        AUTOMATION_CRUD = {api: :@automation_api, body_component: Schema::Registry::AUTOMATION}.freeze
        private_constant :AUTOMATION_CRUD
        commands_under :automation do
          commands_under :workflows do
            crud_commands(**AUTOMATION_CRUD, entity: 'workflows', items_key: 'workflows', query_component: Schema::Registry::AUTOMATION)
            command :launch, description: 'Launch a workflow',
              arguments: [{name: :workflow_id, type: :identifier}],
              action: ->(workflow_id:, **) { Result::SingleObject.new(@automation_api.create("workflows/#{workflow_id}/launch", {})) }
            command :update_state, description: 'Update state of workflow',
              arguments: [{name: :workflow_id, type: :identifier},
                          {name: :state, type: Hash, schema: Schema::Registry.req_body(Schema::Registry::AUTOMATION, 'workflows/{id}/update_state.put')}],
              action: ->(workflow_id:, state:, **) { Result::SingleObject.new(@automation_api.update("workflows/#{workflow_id}/update_state", state)) }
            command(
              :cancel_instances, description: 'Cancel all jobs of workflow',
              arguments: [{name: :workflow_id, type: :identifier}],
              action: lambda do |workflow_id:, **|
                @automation_api.update("workflows/#{workflow_id}/cancel_instances", {})
                Result::Status.new('canceled')
              end
            )
            command(
              :delete_instances, description: 'Delete all jobs of workflow',
              arguments: [{name: :workflow_id, type: :identifier}],
              action: lambda do |workflow_id:, **|
                @automation_api.delete("workflows/#{workflow_id}/delete_instances")
                Result::Status.new('deleted')
              end
            )
            command :action, description: 'Manage actions of workflow',
              arguments: [{name: :workflow_id, type: :identifier}]
            command :permissions, description: 'Manage permissions of workflow',
              arguments: [{name: :workflow_id, type: :identifier}]
          end
          # workflow_id is resolved by the parent command
          commands_under %i[workflows action] do
            command :list,   description: 'List actions of all steps of workflow'
            command :create, description: 'Add a step with one action at the end of workflow',
              arguments: [{name: :action, type: Hash, mandatory: false, default: {}, schema: Schema::Registry.req_body(Schema::Registry::AUTOMATION, 'actions.post')}]
          end
          commands_under %i[workflows permissions] do
            # API requires query parameter workflow_id
            command(
              :list, description: 'List permissions of workflow',
              query_schema: Schema::Registry.query_params(Schema::Registry::AUTOMATION, 'workflow_permissions'),
              action: lambda do |workflow_id:, **|
                schema = Schema::Registry.query_params(Schema::Registry::AUTOMATION, 'workflow_permissions')
                query = (query_read_delete(schema: schema) || {}).merge('workflow_id' => workflow_id)
                Result::ObjectList.new(@automation_api.read('workflow_permissions', query))
              end
            )
            command(
              :create, description: 'Create a permission on workflow',
              arguments: [{name: :workflow_permission, type: Hash, bulk: true, schema: Schema::Registry.req_body(Schema::Registry::AUTOMATION, 'workflow_permissions.post')}],
              action: lambda do |workflow_id:, workflow_permission:, **|
                bulk_result(workflow_permission, command: :create) do |params|
                  @automation_api.create('workflow_permissions', params.merge('workflow_id' => workflow_id))
                end
              end
            )
            crud_commands(**AUTOMATION_CRUD, entity: 'workflow_permissions', name: 'workflow permission', operations: %i[modify delete])
          end
          commands_under :instances do
            crud_commands(
              **AUTOMATION_CRUD, entity: 'workflow_instances', name: 'workflow instance', operations: %i[list show delete],
              items_key: 'workflow_instances', query_component: Schema::Registry::AUTOMATION
            )
            command :cancel, description: 'Cancel workflow instance',
              arguments: [{name: :workflow_instance_id, type: :identifier}],
              action: ->(workflow_instance_id:, **) { Result::SingleObject.new(@automation_api.update("workflow_instances/#{workflow_instance_id}", {'status' => 'canceled'})) }
          end
          commands_under :steps do
            crud_commands(**AUTOMATION_CRUD, entity: 'steps', operations: %i[create show modify delete])
          end
          commands_under :actions do
            crud_commands(**AUTOMATION_CRUD, entity: 'actions', operations: %i[create show modify delete])
          end
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

        def action_reminder(**)
          user_email = options.get_option(:username, mandatory: true)
          no_auth_api = Api::AoC.new(url: options.get_option(:url), auth: :none)
          no_auth_api.create('organization_reminders', {email: user_email})
          return Result::Status.new("List of organizations user is member of, has been sent by e-mail to #{user_email}")
        end

        # packages > send
        def action_packages_send(package:, **)
          package_data = package
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

        # packages > receive — package_id: from arguments:(:identifier) (or overridden by public_link)
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
            all_packages, = list_all_packages_with_query
            Aspera.assert(skip_ids_persistency, 'INIT requires option once_only')
            skip_ids_persistency.data.clear.concat(all_packages[:items].map { |e| e['id'] })
            skip_ids_persistency.save
            return Result::Status.new("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
          when SpecialValues::ALL
            all_packages, max_items = list_all_packages_with_query
            reject_packages_from_persistency(all_packages[:items], skip_ids_persistency)
            all_packages[:items] = all_packages[:items][0, max_items] if max_items
            ids_to_download = all_packages[:items].map { |e| e['id'] }
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
            if skip_ids_persistency && statuses.is_a?(Transfer::Result::Success)
              skip_ids_persistency.data.push(package_id)
              skip_ids_persistency.save
            end
          end
          return Runner.result_transfer_multiple(result_transfer)
        end

        # packages > list
        def action_packages_list(**)
          result, max_items = list_all_packages_with_query
          skip_ids_persistency = package_persistency
          reject_packages_from_persistency(result[:items], skip_ids_persistency)
          result[:items] = result[:items][0, max_items] if max_items
          display_fields = PACKAGE_LIST_DEFAULT_FIELDS
          display_fields += ['workspace_id'] if aoc_api.workspace_info[:id].nil?
          Result::ObjectList.new(result[:items], fields: display_fields, total: result[:total])
        end

        # packages > delete
        def action_packages_delete(package_id:, **)
          bulk_result(package_id, command: :delete) do |one_id|
            Aspera.assert_type(one_id, String, Integer) { 'identifier' }
            aoc_api.delete("packages/#{one_id}")
          end
        end

        # Used as `instance:` of the mount on packages: node of the package contents
        # @return [Array(Node, Hash)]
        def package_node_plugin(package_id:, **)
          package_info = aoc_api.read("packages/#{package_id}")
          # An id that is not a single path segment (e.g. `/`) reads the list of packages
          Aspera.assert(package_info.is_a?(Hash), type: Cli::BadArgument) { "invalid package id: #{package_id}" }
          nodegen4_plugin(package_info['node_id'], file_id: package_info['contents_file_id'], scope: Api::Node::Scope::USER)
        end

        # setup: files > short_link
        # Resolves the target folder, consumes link_type argument, computes purposes.
        # @return [Hash] ctx keys: sl_shared_data, sl_link_type, sl_token_purpose, sl_short_link_purpose, sl_perm_block, sl_shared_apifid, sl_folder_dest
        def setup_files_short_link(folder:, link_type:, **)
          home_node_api = aoc_api.node_api_from(
            node_id: aoc_api.home[:node_id],
            **workspace_id_hash(name: true)
          )
          shared_apifid = home_node_api.resolve_api_fid(aoc_api.home[:file_id], folder)
          shared_data = {
            node_id: shared_apifid.node_api.app_info.node_info['id'],
            file_id: shared_apifid.file_id
          }
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
                  'folder_name'      => File.basename(folder),
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
              found = shared_apifid.node_api.read('permissions', {file_id: shared_apifid.file_id, inherited: false, access_type: 'user', access_id: id}).find { |i| i['access_id'].eql?(id) }
              Aspera.assert(!found.nil?, type: Error) { "Short link not found: #{id}" }
              shared_apifid.node_api.update("permissions/#{found['id']}", {access_levels: Api::AoC.expand_access_levels(access_levels)})
            when :delete
              found = shared_apifid.node_api.read('permissions', {file_id: shared_apifid.file_id, inherited: false, access_type: 'user', access_id: id}).first
              Aspera.assert(!found.nil?, type: Error) { "Short link not found: #{id}" }
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
        # link_type: and dropbox_id: resolved via arguments: on the node, computes purposes.
        # @return [Hash] ctx keys: sl_shared_data, sl_link_type, sl_token_purpose, sl_short_link_purpose
        def setup_packages_short_link(link_type:, dropbox_id:, **)
          shared_data = {dropbox_id: dropbox_id, name: ''}
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
        def sl_exec_create(custom_data = {}, sl_shared_data:, sl_link_type:, sl_token_purpose:, sl_short_link_purpose:, sl_perm_block:, **)
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
          custom_data = custom_data.dup
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
        def sl_exec_delete(sl_shared_data_ws:, sl_short_list:, sl_link_type:, sl_perm_block:, short_link_id: nil, **)
          one_id = short_link_id
          if sl_link_type.eql?(:public)
            found = sl_short_list[:items].find { |item| item['id'].eql?(one_id) }
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
        def sl_exec_show(sl_short_list:, short_link_id: nil, **)
          one_id = short_link_id
          found = sl_short_list[:items].find { |item| item['id'].eql?(one_id) }
          raise BadIdentifier.new('Short link', one_id) if found.nil?
          Result::SingleObject.new(found, fields: Formatter.all_but('data'))
        end

        # Shared implementation for short_link > modify
        def sl_exec_modify(custom_data = {}, sl_shared_data:, sl_short_list:, sl_link_type:, sl_perm_block:, short_link_id: nil, **)
          Aspera.assert_values(sl_link_type, [:public], type: Cli::BadArgument) { 'link_type' }
          one_id = short_link_id
          node_file = sl_shared_data.slice(:node_id, :file_id)
          modify_payload = {edit_access: true, json_query: node_file}
          custom_data = custom_data.dup
          if (pass = custom_data.delete('password'))
            modify_payload[:password_enabled] = true
            modify_payload[:data] = {url_token_data: {password: pass, data: node_file}}
          else
            modify_payload[:password_enabled] = false
          end
          if custom_data.delete('access_levels')
            found = sl_short_list[:items].find { |item| item['id'].eql?(one_id) }
            raise BadIdentifier.new('Short link', one_id) if found.nil?
            sl_perm_block&.call(:update, found['resource_id'], nil)
          end
          modify_payload.deep_merge!(custom_data)
          aoc_api.update("short_links/#{one_id}", modify_payload)
          Result::Status.new('modified')
        end

        # files - mount target: Gen4 commands on the user's home folder
        def files_node_plugin(**)
          nodegen4_plugin(aoc_api.home[:node_id], file_id: aoc_api.home[:file_id], scope: Api::Node::Scope::USER)
        end

        # admin > application > instance > <type> > show|modify
        APP_TYPES.each do |app_type|
          define_action_method([:admin, :application, :instance, app_type, :show]) do |**kwargs|
            app_id = kwargs[:instance_id]
            Result::SingleObject.new(aoc_api.read("admin/apps_new/#{app_type}/#{app_id}", query_read_delete))
          end

          define_action_method([:admin, :application, :instance, app_type, :modify]) do |instance:, **kwargs|
            app_id = kwargs[:instance_id]
            aoc_api.update("admin/apps_new/#{app_type}/#{app_id}", instance)
            Result::Status.new('modified')
          end
        end

        def action_admin_application_instance_list(**)
          result_list(
            'admin/apps_new',
            fields:        %w[id app_type available workspace_id],
            default_query: {workspace_id: aoc_api.workspace_info[:id]}
          )
        end

        def action_packages_shared_inboxes_list(**)
          result_list(
            'dropbox_memberships',
            fields: %w[dropbox_id dropbox.name],
            default_query: workspace_id_hash({'embed[]' => 'dropbox', 'aggregate_permissions_by_dropbox' => true, 'sort' => 'dropbox_name'}, string: true)
          )
        end

        def action_admin_application_membership_create(membership:, **)
          data = membership.dup
          app_type = data.delete('app_type')
          Aspera.assert_type(app_type, String) { 'app_type' }
          Aspera.assert_values(app_type.to_sym, APP_TYPES) { 'app_type' }
          Result::SingleObject.new(aoc_api.create("apps/#{app_type}/app_memberships", data))
        end

        # admin - setup: change API scope to admin once
        def setup_admin_scope(**)
          change_api_scope(Api::AoC::Scope::ADMIN)
          {}
        end

        # admin > subscription > usage
        def action_admin_subscription_usage(aggregate:, start_date:, end_date:, **)
          today      = Date.today
          aggregate  = :ALL if aggregate.nil?
          start_date = today.prev_year.strftime('%Y-%m-%d') if start_date.nil?
          end_date   = today.strftime('%Y-%m-%d') if end_date.nil?
          org    = aoc_api.read('organization')
          result = GraphQL.execute(
            api_from_options('bss/platform/graphql'), 'bss_subscription_usage',
            {organization_id: org['id'], aggregate: aggregate, startDate: start_date, endDate: end_date}
          )
          Result::SingleObject.new(result['aoc'])
        end

        # admin > analytics > transfers
        def action_admin_analytics_transfers(event_resource_type:, event_resource_id:, **)
          event_resource_id ||=
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
          events = build_analytics_api.read("#{event_resource_type}/#{event_resource_id}/transfers", filter)['transfers']
          start_date_persistency&.save
          events.each { |tr_event| context.mailer.send_email_template(values: {ev: tr_event}) } if !options.get_option(:notify_to).nil?
          Result::ObjectList.new(events)
        end

        # admin > analytics > files
        def action_admin_analytics_files(event_resource_type:, event_resource_id:, event_uuid:, **)
          event_resource_id =
            case event_resource_type
            when :organizations then aoc_api.current_user_info['organization_id']
            when :users         then aoc_api.current_user_info['id']
            when :nodes         then aoc_api.current_user_info['read_only_home_node_id']
            else Aspera.error_unreachable_line
            end if event_resource_id.to_s.empty?
          filter = query_read_delete(default: {})
          filter['limit'] ||= 100
          events = build_analytics_api.read("#{event_resource_type}/#{event_resource_id}/transfers/#{event_uuid}/files", filter)['files']
          Result::ObjectList.new(events)
        end

        # Lookup methods for arguments:(:identifier) + lookup: on admin resources.
        # One method per non-singleton resource: percent selector searches with `q=<value>`.
        ADMIN_OBJECTS.reject { |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton) }.each do |res|
          define_method(:"lookup_aoc_#{res}_id") do |_field, value, **|
            aoc_api.lookup_with_q(aoc_res_path(res), value: value)['id']
          end
        end

        # admin > <res> > list
        ADMIN_OBJECTS.each do |res|
          define_action_method([:admin, res, :list]) do |**|
            c = aoc_res_cfg(res)
            result_list(c[:path], fields: c[:list_fields], query_component: c[:query_component])
          end
        end

        # admin > <res> > show
        ADMIN_OBJECTS.reject { |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton) }.each do |res|
          define_action_method([:admin, res, :show]) do |**kwargs|
            res_id = kwargs[:"#{res}_id"]
            c = aoc_res_cfg(res)
            Result::SingleObject.new(aoc_api.read("#{c[:path]}/#{res_id}", query_read_delete), fields: Formatter.all_but('certificate'))
          end
        end

        # admin > organization|self > show (singleton)
        %i[organization self].each do |res|
          define_action_method([:admin, res, :show]) do |**|
            Result::SingleObject.new(aoc_api.read(res.to_s, query_read_delete), fields: Formatter.all_but('certificate'))
          end
        end

        # admin > <res> > create
        ADMIN_OBJECTS.reject { |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton) }.each do |res|
          define_action_method([:admin, res, :create]) do |**kwargs|
            data = kwargs.fetch(res)
            c = aoc_res_cfg(res)
            path = c[:path]
            # Special case: client_registration_token has a different creation URL
            path = 'admin/client_registration/token' if path.eql?('admin/client_registration_tokens')
            workspace_id = aoc_api.workspace_info[:id] if c[:require_ws_id]
            bulk_result(data, command: :create, id_result: c[:id_result]) do |params|
              params['workspace_id'] = workspace_id if c[:require_ws_id] && workspace_id && !params.key?('workspace_id')
              aoc_api.create(path, params)
            end
          end
        end

        # admin > <res> > modify
        ADMIN_OBJECTS.reject { |r| ADMIN_OBJECT_CONFIG.dig(r, :singleton) || ADMIN_OBJECT_CONFIG.dig(r, :ops)&.then { |o| !o.include?(:modify) } }.each do |res|
          define_action_method([:admin, res, :modify]) do |**kwargs|
            data = kwargs.fetch(res)
            res_id = kwargs[:"#{res}_id"]
            c = aoc_res_cfg(res)
            aoc_api.update("#{c[:path]}/#{res_id}", data)
            Result::Status.new('modified')
          end
        end

        # admin > <res> > delete
        ADMIN_OBJECTS.reject do |r|
          cfg = ADMIN_OBJECT_CONFIG.fetch(r, {})
          cfg[:singleton] || (cfg[:ops] && !cfg[:ops].include?(:delete))
        end.each do |res|
          define_action_method([:admin, res, :delete]) do |**kwargs|
            res_id = kwargs[:"#{res}_id"]
            c = aoc_res_cfg(res)
            bulk_result(res_id, command: :delete) do |one_id|
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

        # automation > workflows > action > list
        # A workflow has ordered steps (step_order), a step has ordered actions (action_order)
        def action_automation_workflows_action_list(workflow_id:, **)
          workflow = @automation_api.read("workflows/#{workflow_id}")
          actions = Array(workflow['step_order']).flat_map do |step_id|
            step = @automation_api.read("steps/#{step_id}")
            Array(step['action_order']).map { |action_id| @automation_api.read("actions/#{action_id}") }
          end
          Result::ObjectList.new(actions)
        end

        # automation > workflows > action > create
        # Default action type is `manual`
        def action_automation_workflows_action_create(workflow_id:, action:, **)
          workflow = @automation_api.read("workflows/#{workflow_id}")
          step = @automation_api.create('steps', {'workflow_id' => workflow_id})
          @automation_api.update("workflows/#{workflow_id}", {'step_order' => Array(workflow['step_order']) + [step['id']]})
          new_action = @automation_api.create('actions', {'type' => 'manual'}.merge(action).merge('step_id' => step['id']))
          @automation_api.update("steps/#{step['id']}", {'action_order' => [new_action['id']]})
          Result::SingleObject.new(new_action)
        end

        # admin > client > set_pub_key
        def action_admin_client_set_pub_key(private_key_pem:, client_id:, **)
          c = aoc_res_cfg(:client)
          the_public_key = OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s
          aoc_api.update("#{c[:path]}/#{client_id}", {jwt_grant_enabled: true, public_key: the_public_key})
          Result::Success.new
        end

        # admin > ats — build and return an Ats plugin instance wired to the AoC ATS API.
        # Mount target of `admin ats`.
        # @return [Ats] configured Ats plugin instance
        def build_ats_plugin(**)
          ats_api = Rest.new(**aoc_api.params.deep_merge({
            base_url: "#{aoc_api.base_url}/admin/ats/pub/v1",
            auth:     {params: {scope: Api::AoC::Scope::ADMIN_USER}}
          }))
          Ats.new(context: context, api: ats_api)
        end

        # admin > node > do | bearer_token — setup reuses the generic instance setup
        # (setup_admin_node_instance is auto-generated above, providing res_id:)

        # admin > node > do - mount target: Gen4 commands on the node, admin scope
        def admin_node_do_plugin(node_id:, **)
          nodegen4_plugin(node_id, scope: Api::Node::Scope::ADMIN)
        end

        # admin > node > bearer_token
        def action_admin_node_bearer_token(scope:, node_id:, **)
          scope ||= Api::Node::Scope::ADMIN
          node_api = aoc_api.node_api_from(node_id: node_id, scope: scope)
          Result::Text.new(node_api.oauth.authorization)
        end

        # admin > node > update_status
        def action_admin_node_update_status(node_id:, **)
          Result::SingleObject.new(aoc_api.read("#{aoc_res_path(:node)}/#{node_id}/update_status"), fields: %w[status error_time error_message])
        end

        # admin > workspace > dropbox — res_id: already in ctx via arguments:(:identifier)
        def setup_admin_workspace_dropbox(workspace_id:, **)
          {ws_res_id: workspace_id}
        end

        # admin > workspace > shared_folder — res_id: already in ctx via arguments:(:identifier)
        def setup_admin_workspace_shared_folder(workspace_id:, **)
          resource_instance_path = "#{aoc_res_path(:workspace)}/#{workspace_id}"
          query = options.get_option(:query) || Api::AoC.workspace_access(workspace_id).merge({'admin' => true})
          shared_folders = aoc_api.read_with_paging("#{resource_instance_path}/permissions", query)[:items]
          {ws_res_id: workspace_id, shared_folders: shared_folders}
        end

        # admin > workspace > shared_folder > node|member — shared_folder_id: already in ctx via arguments:(:identifier)
        def resolve_sf_item(shared_folders:, shared_folder_id:, **)
          sf_item = shared_folders.find { |i| i['id'].eql?(shared_folder_id) }
          Aspera.assert(sf_item, 'shared folder not found')
          {sf_item: sf_item}
        end

        alias_method :setup_admin_workspace_shared_folder_node,   :resolve_sf_item
        alias_method :setup_admin_workspace_shared_folder_member, :resolve_sf_item

        # admin > workspace > shared_folder > node - mount target: Gen4 commands on the shared folder, admin scope
        def admin_workspace_shared_folder_node_plugin(sf_item:, **)
          nodegen4_plugin(sf_item['node_id'], file_id: sf_item['file_id'], scope: Api::Node::Scope::ADMIN)
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
          define_action_method([:admin, :user, pref, :show]) do |user_id:, **|
            Result::SingleObject.new(aoc_api.read("#{aoc_res_path(:user)}/#{user_id}/#{pref_path}"))
          end
          define_action_method([:admin, :user, pref, :modify]) do |user_id:, **kwargs|
            aoc_api.update("#{aoc_res_path(:user)}/#{user_id}/#{pref_path}", kwargs.fetch(pref))
            Result::Status.new('modified')
          end
        end

        def action_gateway(parameters: {}, **)
          require 'aspera/faspex_gw'
          parameters = parameters.symbolize_keys
          uri = URI.parse(parameters.delete(:url) { WebServerSimple::DEFAULT_URL })
          server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
          Aspera.assert(parameters.except(*WebServerSimple::PARAMS).empty?) { "unexpected parameters: #{parameters.except(*WebServerSimple::PARAMS).keys}" }
          server.mount(uri.path, Faspex4GWServlet, aoc_api, aoc_api.workspace_info[:id])
          server.start
          return Result::Status.new('Gateway terminated')
        end
      end
    end
  end
end
