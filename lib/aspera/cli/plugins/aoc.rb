# frozen_string_literal: true

require 'aspera/cli/plugins/node'
require 'aspera/cli/plugins/ats'
require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/special_values'
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
      class Aoc < Cli::BasicAuthPlugin
        # default redirect for AoC web auth
        REDIRECT_LOCALHOST = 'http://localhost:12345'
        # OAuth methods supported
        STD_AUTH_TYPES = %i[web jwt].freeze
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
          kms_profile].freeze
        # query to list fully received packages
        PACKAGE_RECEIVED_BASE_QUERY = {
          'archived'    => false,
          'has_content' => true,
          'received'    => true,
          'completed'   => true}.freeze
        # options and parameters for Api::AoC.new
        OPTIONS_NEW = %i[url auth client_id client_secret scope redirect_uri private_key passphrase username password workspace].freeze
        private_constant :REDIRECT_LOCALHOST, :STD_AUTH_TYPES, :ADMIN_OBJECTS, :PACKAGE_RECEIVED_BASE_QUERY, :OPTIONS_NEW
        class << self
          def application_name
            'Aspera on Cloud'
          end

          def detect(base_url)
            # no protocol ?
            base_url = "https://#{base_url}" unless base_url.match?(%r{^[a-z]{1,6}://})
            # only org provided ?
            base_url = "#{base_url}.#{Api::AoC::SAAS_DOMAIN_PROD}" unless base_url.include?('.')
            # AoC is only https
            return nil unless base_url.start_with?('https://')
            res_http = Rest.new(base_url: base_url, redirect_max: 0).call(operation: 'GET', subpath: 'auth/ping', return_error: true)[:http]
            return nil if res_http['Location'].nil?
            redirect_uri = URI.parse(res_http['Location'])
            od = Api::AoC.split_org_domain(URI.parse(base_url))
            return nil unless redirect_uri.path.end_with?("oauth2/#{od[:organization]}/login")
            # either in standard domain, or product name in page
            return {
              version: Api::AoC.saas_url?(base_url) ? 'SaaS' : 'Self-managed',
              url:     base_url
            }
          end

          # @param url [String] url to check
          # @return [Bool] true if private key is required for the url (i.e. no passcode)
          def private_key_required?(url)
            # pub link do not need private key
            return Api::AoC.link_info(url)[:token].nil?
          end

          # @param object [Plugin] An instance of this class
          # @param private_key_path [String] path to private key
          # @param pub_key_pem [String] PEM of public key
          # @return [Hash] :preset_value, :test_args
          def wizard(object:, private_key_path: nil, pub_key_pem: nil)
            # set vars to look like object
            options = object.options
            formatter = object.formatter
            instance_url = options.get_option(:url, mandatory: true)
            pub_link_info = Api::AoC.link_info(instance_url)
            if !pub_link_info[:token].nil?
              pub_api = Rest.new(base_url: "https://#{URI.parse(pub_link_info[:url]).host}/api/v1")
              pub_info = pub_api.read('env/url_token_check', {token: pub_link_info[:token]})
              preset_value = {
                link: instance_url
              }
              preset_value[:password] = options.get_option(:password, mandatory: true) if pub_info['password_protected']
              return {
                preset_value: preset_value,
                test_args:    'organization'
              }
            end
            options.declare(:use_generic_client, 'Wizard: AoC: use global or org specific jwt client id', values: :bool, default: Api::AoC.saas_url?(instance_url))
            options.parse_options!
            # make username mandatory for jwt, this triggers interactive input
            wiz_username = options.get_option(:username, mandatory: true)
            raise "Username shall be an email in AoC: #{wiz_username}" if !(wiz_username =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
            # Set the pub key and jwt tag in the user's profile automatically
            auto_set_pub_key = false
            auto_set_jwt = false
            # use browser authentication to bootstrap
            use_browser_authentication = false
            if options.get_option(:use_generic_client)
              formatter.display_status('Using global client_id.')
              formatter.display_status('Please Login to your Aspera on Cloud instance.')
              formatter.display_status('Navigate to: 👤 → Account Settings → Profile → Public Key')
              formatter.display_status('Check or update the value to:'.red.blink)
              formatter.display_status(pub_key_pem)
              if !options.get_option(:test_mode)
                formatter.display_status('Once updated or validated, press enter.')
                Environment.instance.open_uri(instance_url)
                $stdin.gets
              end
            else
              formatter.display_status('Using organization specific client_id.')
              if options.get_option(:client_id).nil? || options.get_option(:client_secret).nil?
                formatter.display_status('Please login to your Aspera on Cloud instance.'.red)
                formatter.display_status('Navigate to: 𓃑  → Admin → Integrations → API Clients')
                formatter.display_status('Check or create in integration:')
                formatter.display_status('- name: cli')
                formatter.display_status("- redirect uri: #{REDIRECT_LOCALHOST}")
                formatter.display_status('- origin: localhost')
                formatter.display_status('Use the generated client id and secret in the following prompts.'.red)
              end
              Environment.instance.open_uri("#{instance_url}/admin/integrations/api-clients")
              options.get_option(:client_id, mandatory: true)
              options.get_option(:client_secret, mandatory: true)
              # use_browser_authentication = true
            end
            if use_browser_authentication
              formatter.display_status('We will use web authentication to bootstrap.')
              auto_set_pub_key = true
              auto_set_jwt = true
              raise 'TODO'
              # aoc_api.oauth.grant_method = :web
              # aoc_api.oauth.scope = Api::AoC::SCOPE_FILES_ADMIN
              # aoc_api.oauth.specific_parameters[:redirect_uri] = REDIRECT_LOCALHOST
            end
            myself = object.aoc_api.read('self')
            if auto_set_pub_key
              Aspera.assert(myself['public_key'].empty?, exception_class: Cli::Error){'Public key is already set in profile (use --override=yes)'} unless option_override
              formatter.display_status('Updating profile with the public key.')
              aoc_api.update("users/#{myself['id']}", {'public_key' => pub_key_pem})
            end
            if auto_set_jwt
              formatter.display_status('Enabling JWT for client')
              aoc_api.update("clients/#{options.get_option(:client_id)}", {'jwt_grant_enabled' => true, 'explicit_authorization_required' => false})
            end
            preset_result = {
              url:         instance_url,
              username:    myself['email'],
              auth:        :jwt.to_s,
              private_key: "@file:#{private_key_path}"
            }
            # set only if non nil
            %i[client_id client_secret].each do |s|
              o = options.get_option(s)
              preset_result[s.to_s] = o unless o.nil?
            end
            return {
              preset_value: preset_result,
              test_args:    'user profile show'
            }
          end
        end

        def initialize(**_)
          super
          @cache_workspace_info = nil
          @cache_home_node_file = nil
          @cache_api_aoc = nil
          options.declare(:auth, 'OAuth type of authentication', values: STD_AUTH_TYPES, default: :jwt)
          options.declare(:client_id, 'OAuth API client identifier')
          options.declare(:client_secret, 'OAuth API client secret')
          options.declare(:scope, 'OAuth scope for AoC API calls', default: Api::AoC::SCOPE_FILES_USER)
          options.declare(:redirect_uri, 'OAuth API client redirect URI')
          options.declare(:private_key, 'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.declare(:passphrase, 'RSA private key passphrase', types: String)
          options.declare(:workspace, 'Name of workspace', types: [String, NilClass], default: Api::AoC::DEFAULT_WORKSPACE)
          options.declare(:new_user_option, 'New user creation option for unknown package recipients', types: Hash)
          options.declare(:validate_metadata, 'Validate shared inbox metadata', values: :bool, default: true)
          options.parse_options!
          # add node plugin options (for manual)
          Node.declare_options(options)
        end

        def api_from_options(new_base_path)
          create_values = {subpath: new_base_path, secret_finder: config}
          # create an API object with the same options, but with a different subpath
          return Api::AoC.new(**OPTIONS_NEW.each_with_object(create_values) { |i, m|m[i] = options.get_option(i) unless options.get_option(i).nil?})
        rescue ArgumentError => e
          if (m = e.message.match(/missing keyword: :(.*)$/))
            raise Cli::Error, "Missing option: #{m[1]}"
          end
          raise
        end

        def aoc_api
          if @cache_api_aoc.nil?
            @cache_api_aoc = api_from_options(Api::AoC::API_V1)
            organization = @cache_api_aoc.read('organization')
            if organization['http_gateway_enabled'] && organization['http_gateway_server_url']
              transfer.httpgw_url_cb = lambda { organization['http_gateway_server_url'] }
              # @cache_api_aoc.current_user_info['connect_disabled']
            end
          end
          return @cache_api_aoc
        end

        # Get resource identifier from command line, either directly or from name.
        # @param resource_class_path url path for resource
        # @return identifier
        def get_resource_id_from_args(resource_class_path)
          return instance_identifier do |field, value|
            Aspera.assert(field.eql?('name'), exception_class: Cli::BadArgument){'only selection by name is supported'}
            aoc_api.lookup_by_name(resource_class_path, value)['id']
          end
        end

        # Get resource path from command line
        def get_resource_path_from_args(resource_class_path)
          return "#{resource_class_path}/#{get_resource_id_from_args(resource_class_path)}"
        end

        # Call block with same query using paging and response information
        # block must return a hash with :data and :http keys
        # @return [Hash] {data: , total: }
        def api_call_paging(base_query={})
          Aspera.assert_type(base_query, Hash){'query'}
          Aspera.assert(block_given?)
          # set default large page if user does not specify own parameters. AoC Caps to 1000 anyway
          base_query['per_page'] = 1000 unless base_query.key?('per_page')
          max_items = base_query.delete(MAX_ITEMS)
          max_pages = base_query.delete(MAX_PAGES)
          item_list = []
          total_count = nil
          current_page = base_query['page']
          current_page = 1 if current_page.nil?
          page_count = 0
          loop do
            query = base_query.clone
            query['page'] = current_page
            result = yield(query)
            Aspera.assert(result[:data])
            Aspera.assert(result[:http])
            total_count = result[:http]['X-Total-Count']
            page_count += 1
            current_page += 1
            add_items = result[:data]
            break if add_items.empty?
            # append new items to full list
            item_list += add_items
            break if !max_items.nil? && item_list.count >= max_items
            break if !max_pages.nil? && page_count >= max_pages
          end
          item_list = item_list[0..max_items - 1] if !max_items.nil? && item_list.count > max_items
          return {data: item_list, total: total_count}
        end

        # read using the query and paging
        # @return [Hash] {data: , total: }
        def api_read_all(resource_class_path, base_query={})
          return api_call_paging(base_query) do |query|
            aoc_api.call(operation: 'GET', subpath: resource_class_path, headers: {'Accept' => 'application/json'}, query: query)
          end
        end

        # list all entities, given additional, default and user's queries
        # @param resource_class_path path to query on API
        # @param fields fields to display
        # @param base_query a query applied always
        # @param default_query default query unless overriden by user
        def result_list(resource_class_path, fields: nil, base_query: {}, default_query: {})
          Aspera.assert_type(base_query, Hash)
          Aspera.assert_type(default_query, Hash)
          user_query = query_read_delete(default: default_query)
          # caller may add specific modifications or checks
          yield(user_query) if block_given?
          return {type: :object_list, fields: fields}.merge(api_read_all(resource_class_path, base_query.merge(user_query).compact))
        end

        def resolve_dropbox_name_default_ws_id(query)
          if query.key?('dropbox_name')
            # convenience: specify name instead of id
            raise 'not both dropbox_name and dropbox_id' if query.key?('dropbox_id')
            # TODO : craft a query that looks for dropbox only in current workspace
            query['dropbox_id'] = aoc_api.lookup_by_name('dropboxes', query['dropbox_name'])['id']
            query.delete('dropbox_name')
          end
          query['workspace_id'] ||= aoc_api.workspace[:id] unless aoc_api.workspace[:id].eql?(:undefined)
          # by default show dropbox packages only for dropboxes
          query['exclude_dropbox_packages'] = !query.key?('dropbox_id') unless query.key?('exclude_dropbox_packages')
        end

        NODE4_EXT_COMMANDS = %i[transfer].concat(Node::COMMANDS_GEN4).freeze
        private_constant :NODE4_EXT_COMMANDS

        # @param file_id [String] root file id for the operation (can be AK root, or other, e.g. package, or link)
        # @param scope [String] node scope, or nil (admin)
        def execute_nodegen4_command(command_repo, node_id, file_id: nil, scope: nil)
          top_node_api = aoc_api.node_api_from(
            node_id:        node_id,
            workspace_id:   aoc_api.workspace[:id],
            workspace_name: aoc_api.workspace[:name],
            scope:          scope
          )
          file_id = top_node_api.read("access_keys/#{top_node_api.app_info[:node_info]['access_key']}")['root_file_id'] if file_id.nil?
          node_plugin = Node.new(**init_params, api: top_node_api)
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
              add_ts)))
          else Aspera.error_unreachable_line
          end
          Aspera.error_unreachable_line
        end

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
          supported_operations.push(:do) if resource_type.eql?(:node)
          supported_operations.push(:set_pub_key) if resource_type.eql?(:client)
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
            when :contact then default_fields = %w[email name source_id source_type]
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
            fields = object.keys.reject{|k|k.eql?('certificate')}
            return { type: :single_object, data: object, fields: fields }
          when :modify
            changes = options.get_next_argument('properties', validation: Hash)
            return do_bulk_operation(command: command, descr: 'identifier', values: res_id) do |one_id|
              aoc_api.update("#{resource_class_path}/#{one_id}", changes)
              {'id' => one_id}
            end
          when :delete
            return do_bulk_operation(command: command, descr: 'identifier', values: res_id) do |one_id|
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
            # init context
            aoc_api.context = :files
            return execute_nodegen4_command(command_repo, res_id)
          else Aspera.error_unexpected_value(command)
          end
        end

        ADMIN_ACTIONS = %i[ats resource usage_reports analytics subscription auth_providers].concat(ADMIN_OBJECTS).freeze

        def execute_admin_action
          # upgrade scope to admin
          aoc_api.oauth.scope = Api::AoC::SCOPE_FILES_ADMIN
          command_admin = options.get_next_command(ADMIN_ACTIONS)
          case command_admin
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
              raise 'not implemented'
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
              return {type: :single_object, data: result['aoc']['bssSubscription']}
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
                {query:     graphql_query,
                 variables: {
                   organization_id: org['id'],
                   aggregate:       aggregate,
                   startDate:       start_date,
                   endDate:         end_date}})['data']
              return {type: :single_object, data: result['aoc']}
            end
          when :ats
            ats_api = Rest.new(**aoc_api.params.deep_merge({
              base_url: "#{aoc_api.base_url}/admin/ats/pub/v1",
              auth:     {scope: Api::AoC::SCOPE_FILES_ADMIN_USER}
            }))
            return Ats.new(**init_params).execute_action_gen(ats_api)
          when :analytics
            analytics_api = Rest.new(**aoc_api.params.deep_merge({
              base_url: "#{aoc_api.base_url.gsub('/api/v1', '')}/analytics/v2",
              auth:     {scope: Api::AoC::SCOPE_FILES_ADMIN_USER}
            }))
            command_analytics = options.get_next_command(%i[application_events transfers])
            case command_analytics
            when :application_events
              event_type = command_analytics.to_s
              events = analytics_api.read("organizations/#{aoc_api.current_user_info['organization_id']}/#{event_type}")[event_type]
              return {type: :object_list, data: events}
            when :transfers
              event_type = command_analytics.to_s
              filter_resource = options.get_next_argument('resource', accept_list: %i[organizations users nodes])
              filter_id = options.get_next_argument('identifier', mandatory: false) ||
                case filter_resource
                when :organizations then aoc_api.current_user_info['organization_id']
                when :users then aoc_api.current_user_info['id']
                when :nodes then aoc_api.current_user_info['id'] # TODO: consistent ? # rubocop:disable Lint/DuplicateBranch
                else Aspera.error_unreachable_line
                end
              filter = options.get_option(:query) || {}
              filter['limit'] ||= 100
              if options.get_option(:once_only, mandatory: true)
                aoc_api.context = :files
                saved_date = []
                start_date_persistency = PersistencyActionOnce.new(
                  manager: persistency,
                  data: saved_date,
                  id: IdGenerator.from_list([
                    'aoc_ana_date',
                    options.get_option(:url, mandatory: true),
                    aoc_api.workspace[:name],
                    filter_resource.to_s,
                    filter_id
                  ]))
                start_date_time = saved_date.first
                stop_date_time = Time.now.utc.strftime('%FT%T.%LZ')
                # Log.log().error("start: #{start_date_time}")
                # Log.log().error("end:   #{stop_date_time}")
                saved_date[0] = stop_date_time
                filter['start_time'] = start_date_time unless start_date_time.nil?
                filter['stop_time'] = stop_date_time
              end
              events = analytics_api.read("#{filter_resource}/#{filter_id}/#{event_type}", query_read_delete(default: filter))[event_type]
              start_date_persistency&.save
              if !options.get_option(:notify_to).nil?
                events.each do |tr_event|
                  config.send_email_template(values: {ev: tr_event})
                end
              end
              return {type: :object_list, data: events}
            end
          when :usage_reports
            aoc_api.context = :files
            return result_list('usage_reports', base_query: {workspace_id: aoc_api.workspace[:id]})
          end
        end

        # Create a shared link for the given entity
        # @param shared_data [Hash] information for shared data
        # @param block [Proc] Optional: called on creation
        def short_link_command(shared_data, purpose_public:)
          link_type = options.get_next_argument('link type', accept_list: %i[public private])
          purpose_local = case link_type
          when :public
            case purpose_public
            when /package/ then 'send_package_to_dropbox'
            when /shared/ then 'token_auth_redirection'
            else raise 'error'
            end
          when :private then 'shared_folder_auth_link'
          else Aspera.error_unreachable_line
          end
          case options.get_next_command(%i[create delete list])
          when :create
            creation_params = {
              purpose:            purpose_local,
              user_selected_name: nil
            }
            case link_type
            when :private
              creation_params[:data] = shared_data
            when :public
              creation_params[:expires_at]       = nil
              creation_params[:password_enabled] = false
              shared_data[:name] = ''
              creation_params[:data] = {
                aoc:            true,
                url_token_data: {
                  data:    shared_data,
                  purpose: purpose_public
                }
              }
            end
            result_create_short_link = aoc_api.create('short_links', creation_params)
            # public: Creation: permission on node
            yield(result_create_short_link['resource_id']) if block_given? && link_type.eql?(:public)
            return {type: :single_object, data: result_create_short_link}
          when :list
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
            return result_list('short_links', fields: Formatter.all_but('data'), base_query: list_params)
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

        # must be public
        ACTIONS = %i[reminder servers bearer_token organization tier_restrictions user packages files admin automation gateway].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          if %i[files packages].include?(command)
            default_flag = ' (default)' if options.get_option(:workspace).eql?(:default)
            aoc_api.context = command
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
            return {type: :object_list, data: Rest.new(base_url: "#{Api::AoC.api_base_url}/#{Api::AoC::API_V1}").read('servers')}
          when :bearer_token
            return {type: :text, data: aoc_api.oauth.authorization}
          when :organization
            return { type: :single_object, data: aoc_api.read('organization') }
          when :tier_restrictions
            return { type: :single_object, data: aoc_api.read('tier_restrictions') }
          when :user
            case options.get_next_command(%i[workspaces profile preferences])
            # when :settings
            # return {type: :object_list,data: aoc_api.read('client_settings/')}
            when :workspaces
              case options.get_next_command(%i[list current])
              when :list
                return result_list('workspaces', fields: %w[id name])
              when :current
                aoc_api.context = :files
                return { type: :single_object, data: aoc_api.read("workspaces/#{aoc_api.workspace[:id]}") }
              end
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: aoc_api.current_user_info(exception: true) }
              when :modify
                aoc_api.update("users/#{aoc_api.current_user_info(exception: true)['id']}", options.get_next_argument('properties', validation: Hash))
                return Main.result_status('modified')
              end
            when :preferences
              user_preferences_res = "users/#{aoc_api.current_user_info(exception: true)['id']}/user_interaction_preferences"
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: aoc_api.read(user_preferences_res) }
              when :modify
                aoc_api.update(user_preferences_res, options.get_next_argument('properties', validation: Hash))
                return Main.result_status('modified')
              end
            end
          when :packages
            package_command = options.get_next_command(%i[shared_inboxes send receive list show delete].concat(Node::NODE4_READ_ACTIONS), aliases: {recv: :receive})
            case package_command
            when :shared_inboxes
              case options.get_next_command(%i[list show short_link])
              when :list
                default_query = {'embed[]' => 'dropbox', 'aggregate_permissions_by_dropbox' => true, 'sort' => 'dropbox_name'}
                default_query['workspace_id'] = aoc_api.workspace[:id] unless aoc_api.workspace[:id].eql?(:undefined)
                return result_list('dropbox_memberships', fields: %w[dropbox_id dropbox.name], default_query: default_query)
              when :show
                return {type: :single_object, data: aoc_api.read(get_resource_path_from_args('dropboxes'))}
              when :short_link
                return short_link_command(
                  {
                    workspace_id: aoc_api.workspace[:id],
                    dropbox_id:   get_resource_id_from_args('dropboxes'),
                    name:         ''
                  },
                  purpose_public: 'send_package_to_dropbox')
              end
            when :send
              package_data = value_create_modify(command: package_command)
              new_user_option = options.get_option(:new_user_option)
              option_validate = options.get_option(:validate_metadata)
              # works for both normal usr auth and link auth
              package_data['workspace_id'] ||= aoc_api.workspace[:id]

              if !aoc_api.public_link.nil?
                aoc_api.assert_public_link_types(%w[send_package_to_user send_package_to_dropbox])
                box_type = aoc_api.public_link['purpose'].split('_').last
                package_data['recipients'] = [{'id' => aoc_api.public_link['data']["#{box_type}_id"], 'type' => box_type}]
                # enforce workspace id from link (should be already ok, but in case user wanted to override)
                package_data['workspace_id'] = aoc_api.public_link['data']['workspace_id']
              end

              # transfer may raise an error
              created_package = aoc_api.create_package_simple(package_data, option_validate, new_user_option)
              Main.result_transfer(transfer.start(created_package[:spec], rest_token: created_package[:node]))
              # return all info on package (especially package id)
              return { type: :single_object, data: created_package[:info]}
            when :receive
              ids_to_download = nil
              if !aoc_api.public_link.nil?
                aoc_api.assert_public_link_types(['view_received_package'])
                # set the package id, it will
                ids_to_download = aoc_api.public_link['data']['package_id']
              end
              # get from command line unless it was a public link
              ids_to_download ||= instance_identifier
              skip_ids_data = []
              skip_ids_persistency = nil
              if options.get_option(:once_only, mandatory: true)
                # TODO: add query info to id
                skip_ids_persistency = PersistencyActionOnce.new(
                  manager: persistency,
                  data: skip_ids_data,
                  id: IdGenerator.from_list(
                    ['aoc_recv',
                     options.get_option(:url, mandatory: true),
                     aoc_api.workspace[:id]
                    ].concat(aoc_api.additional_persistence_ids)))
              end
              case ids_to_download
              when SpecialValues::ALL, SpecialValues::INIT
                query = query_read_delete(default: PACKAGE_RECEIVED_BASE_QUERY)
                Aspera.assert_type(query, Hash){'query'}
                resolve_dropbox_name_default_ws_id(query)
                # remove from list the ones already downloaded
                all_ids = api_read_all('packages', query)[:data].map{|e|e['id']}
                if ids_to_download.eql?(SpecialValues::INIT)
                  Aspera.assert(skip_ids_persistency){'Only with option once_only'}
                  skip_ids_persistency.data.clear.concat(all_ids)
                  skip_ids_persistency.save
                  return Main.result_status("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
                end
                # array here
                ids_to_download = all_ids.reject{|id|skip_ids_data.include?(id)}
              else
                ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
              end
              file_list =
                begin
                  transfer.source_list.map{|i|{'source'=>i}}
                rescue Cli::BadArgument
                  [{'source' => '.'}]
                end
              # list here
              result_transfer = []
              formatter.display_status("found #{ids_to_download.length} package(s).")
              ids_to_download.each do |package_id|
                package_info = aoc_api.read("packages/#{package_id}")
                formatter.display_status("downloading package: [#{package_info['id']}] #{package_info['name']}")
                package_node_api = aoc_api.node_api_from(
                  node_id: package_info['node_id'],
                  workspace_id: aoc_api.workspace[:id],
                  workspace_name: aoc_api.workspace[:name],
                  package_info: package_info)
                statuses = transfer.start(
                  package_node_api.transfer_spec_gen4(
                    package_info['contents_file_id'],
                    Transfer::Spec::DIRECTION_RECEIVE,
                    {'paths'=> file_list}),
                  rest_token: package_node_api)
                result_transfer.push({'package' => package_id, Main::STATUS_FIELD => statuses})
                # update skip list only if all transfer sessions completed
                if TransferAgent.session_status(statuses).eql?(:success)
                  skip_ids_data.push(package_id)
                  skip_ids_persistency&.save
                end
              end
              return Main.result_transfer_multiple(result_transfer)
            when :show
              package_id = instance_identifier
              package_info = aoc_api.read("packages/#{package_id}")
              return { type: :single_object, data: package_info }
            when :list
              display_fields = %w[id name bytes_transferred]
              display_fields.push('workspace_id') if aoc_api.workspace[:id].eql?(:undefined)
              return result_list('packages', fields: display_fields, base_query: PACKAGE_RECEIVED_BASE_QUERY) do |query|
                       resolve_dropbox_name_default_ws_id(query)
                     end
            when :delete
              return do_bulk_operation(command: package_command, descr: 'identifier', values: instance_identifier) do |id|
                Aspera.assert_values(id.class, [String, Integer]){'identifier'}
                aoc_api.delete("packages/#{id}")
              end
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
                node_id:        aoc_api.home[:node_id],
                workspace_id:   aoc_api.workspace[:id],
                workspace_name: aoc_api.workspace[:name])
              shared_apfid = home_node_api.resolve_api_fid(aoc_api.home[:file_id], folder_dest)
              return short_link_command(
                {
                  workspace_id: aoc_api.workspace[:id],
                  node_id:      shared_apfid[:api].app_info[:node_info]['id'],
                  file_id:      shared_apfid[:file_id]
                }, purpose_public: 'view_shared_file') do |resource_id|
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
                           'workspace_id'     => aoc_api.workspace[:id],
                           'workspace_name'   => aoc_api.workspace[:name],
                           'folder_name'      => File.basename(folder_dest),
                           'created_by_name'  => aoc_api.current_user_info['name'],
                           'created_by_email' => aoc_api.current_user_info['email'],
                           'access_key'       => shared_apfid[:api].app_info[:node_info]['access_key'],
                           'node'             => shared_apfid[:api].app_info[:node_info]['host']
                         }
                       }
                       created_data = shared_apfid[:api].create('permissions', perm_data)
                       aoc_api.permissions_send_event(event_data: created_data, app_info: shared_apfid[:api].app_info)
                     end
            end
          when :automation
            Log.log.warn('BETA: work under progress')
            # automation api is not in the same place
            automation_api = Rest.new(**aoc_api.params, base_url: aoc_api.base_url.gsub('/api/', '/automation/'))
            command_automation = options.get_next_command(%i[workflows instances])
            case command_automation
            when :instances
              return entity_action(aoc_api, 'workflow_instances')
            when :workflows
              wf_command = options.get_next_command(%i[action launch].concat(Plugin::ALL_OPS))
              case wf_command
              when *Plugin::ALL_OPS
                return entity_command(wf_command, automation_api, 'workflows')
              when :launch
                wf_id = instance_identifier
                data = automation_api.create("workflows/#{wf_id}/launch", {})
                return {type: :single_object, data: data}
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
                return {type: :single_object, data: wf}
              end
            end
          when :admin
            return execute_admin_action
          when :gateway
            require 'aspera/faspex_gw'
            url = value_create_modify(command: command, type: String)
            uri = URI.parse(url)
            server = WebServerSimple.new(uri)
            aoc_api.context = :files
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
