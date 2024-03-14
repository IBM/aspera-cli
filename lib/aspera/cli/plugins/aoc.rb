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
require 'aspera/assert'
require 'securerandom'
require 'date'

module Aspera
  module Cli
    module Plugins
      class Aoc < Aspera::Cli::BasicAuthPlugin
        AOC_PATH_API_CLIENTS = 'admin/api-clients'
        # default redirect for AoC web auth
        DEFAULT_REDIRECT = 'http://localhost:12345'
        private_constant :AOC_PATH_API_CLIENTS, :DEFAULT_REDIRECT
        class << self
          def application_name
            'Aspera on Cloud'
          end

          def detect(base_url)
            # no protocol ?
            base_url = "https://#{base_url}" unless base_url.match?(%r{^[a-z]{1,6}://})
            # only org provided ?
            base_url = "#{base_url}.#{Aspera::AoC::PROD_DOMAIN}" unless base_url.include?('.')
            # AoC is only https
            return nil unless base_url.start_with?('https://')
            result = Rest.new({base_url: base_url, redirect_max: 10}).read('')
            # Any AoC is on this domain
            return nil unless result[:http].uri.host.end_with?(Aspera::AoC::PROD_DOMAIN)
            Log.log.debug{'AoC Main page: #{result[:http].body.include?(Aspera::AoC::PRODUCT_NAME)}'}
            base_url = result[:http].uri.to_s if result[:http].uri.path.include?('/public')
            # either in standard domain, or product name in page
            return {
              version: 'SaaS',
              url:     base_url
            }
          end

          def private_key_required?(url)
            # pub link do not need private key
            return AoC.link_info(url)[:token].nil?
          end

          # @param [Hash] env : options, formatter
          # @param [Hash] params : plugin_sym, instance_url
          # @return [Hash] :preset_value, :test_args
          def wizard(object:, private_key_path: nil, pub_key_pem: nil)
            # set vars to look like object
            options = object.options
            formatter = object.formatter
            options.declare(:use_generic_client, 'Wizard: AoC: use global or org specific jwt client id', values: :bool, default: true)
            options.parse_options!
            instance_url = options.get_option(:url, mandatory: true)
            pub_link_info = AoC.link_info(instance_url)
            if !pub_link_info[:token].nil?
              pub_api = Rest.new({base_url: "https://#{URI.parse(pub_link_info[:url]).host}/api/v1"})
              pub_info = pub_api.read('env/url_token_check', {token: pub_link_info[:token]})[:data]
              preset_value = {
                link: instance_url
              }
              preset_value[:password] = options.get_option(:password, mandatory: true) if pub_info['password_protected']
              return {
                preset_value: preset_value,
                test_args:    'organization'
              }
            end
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
                OpenApplication.instance.uri(instance_url)
                $stdin.gets
              end
            else
              formatter.display_status('Using organization specific client_id.')
              if options.get_option(:client_id).nil? || options.get_option(:client_secret).nil?
                formatter.display_status('Please login to your Aspera on Cloud instance.'.red)
                formatter.display_status('Navigate to: 𓃑  → Admin → Integrations → API Clients')
                formatter.display_status('Check or create in integration:')
                formatter.display_status("- name: #{@info[:name]}")
                formatter.display_status("- redirect uri: #{DEFAULT_REDIRECT}")
                formatter.display_status('- origin: localhost')
                formatter.display_status('Use the generated client id and secret in the following prompts.'.red)
              end
              OpenApplication.instance.uri("#{instance_url}/#{AOC_PATH_API_CLIENTS}")
              options.get_option(:client_id, mandatory: true)
              options.get_option(:client_secret, mandatory: true)
              use_browser_authentication = true
            end
            if use_browser_authentication
              formatter.display_status('We will use web authentication to bootstrap.')
              auto_set_pub_key = true
              auto_set_jwt = true
              aoc_api.oauth.generic_parameters[:grant_method] = :web
              aoc_api.oauth.generic_parameters[:scope] = AoC::SCOPE_FILES_ADMIN
              aoc_api.oauth.specific_parameters[:redirect_uri] = DEFAULT_REDIRECT
            end
            myself = object.aoc_api.read('self')[:data]
            if auto_set_pub_key
              assert(myself['public_key'].empty?, exception_class: Cli::Error){'Public key is already set in profile (use --override=yes)'} unless option_override
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
        # special value for package id
        KNOWN_AOC_RES = %i[
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
        PACKAGE_RECEIVED_BASE_QUERY = {
          'archived'    => false,
          'has_content' => true,
          'received'    => true,
          'completed'   => true}.freeze

        def initialize(env)
          super(env)
          @cache_workspace_info = nil
          @cache_home_node_file = nil
          @cache_api_aoc = nil
          options.declare(:auth, 'OAuth type of authentication', values: Oauth::STD_AUTH_TYPES, default: :jwt)
          options.declare(:client_id, 'OAuth API client identifier')
          options.declare(:client_secret, 'OAuth API client secret')
          options.declare(:scope, 'OAuth scope for AoC API calls', default: AoC::SCOPE_FILES_USER)
          options.declare(:redirect_uri, 'OAuth API client redirect URI')
          options.declare(:private_key, 'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.declare(:passphrase, 'RSA private key passphrase')
          options.declare(:workspace, 'Name of workspace', types: [String, NilClass], default: Aspera::AoC::DEFAULT_WORKSPACE)
          options.declare(:new_user_option, 'New user creation option for unknown package recipients')
          options.declare(:validate_metadata, 'Validate shared inbox metadata', values: :bool, default: true)
          options.parse_options!
          # add node plugin options (for manual)
          Node.declare_options(options)
        end

        OPTIONS_NEW = %i[url auth client_id client_secret scope redirect_uri private_key passphrase username password workspace].freeze

        def api_from_options(new_base_path)
          create_values = {subpath: new_base_path, secret_finder: @agents[:config]}
          # create an API object with the same options, but with a different subpath
          return Aspera::AoC.new(**OPTIONS_NEW.each_with_object(create_values) { |i, m|m[i] = options.get_option(i) unless options.get_option(i).nil?})
        rescue ArgumentError => e
          if (m = e.message.match(/missing keyword: :(.*)$/))
            raise Cli::Error, "Missing option: #{m[1]}"
          end
          raise
        end

        def aoc_api
          if @cache_api_aoc.nil?
            @cache_api_aoc = api_from_options(AoC::API_V1)
            organization = @cache_api_aoc.read('organization')[:data]
            if organization['http_gateway_enabled'] && organization['http_gateway_server_url']
              transfer.httpgw_url_cb = lambda { organization['http_gateway_server_url'] }
              # @cache_api_aoc.current_user_info['connect_disabled']
            end
          end
          return @cache_api_aoc
        end

        # get identifier or name from command line
        # @return identifier
        def get_resource_id_from_args(resource_class_path)
          return instance_identifier do |field, value|
            assert(field.eql?('name'), exception_class: Cli::BadArgument){'only selection by name is supported'}
            aoc_api.lookup_by_name(resource_class_path, value)['id']
          end
        end

        def get_resource_path_from_args(resource_class_path)
          return "#{resource_class_path}/#{get_resource_id_from_args(resource_class_path)}"
        end

        # Call block with same query using paging and response information
        # @return [Hash] {data: , total: }
        def api_call_paging(base_query={})
          assert_type(base_query, Hash){'query'}
          assert(block_given?)
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
            aoc_api.read(resource_class_path, query)
          end
        end

        # list all entities, given additional, default and user's queries
        def result_list(resource_class_path, fields: nil, base_query: {}, default_query: {})
          assert_type(base_query, Hash)
          assert_type(default_query, Hash)
          user_query = query_read_delete(default: default_query)
          # caller may add specific modifications or checks
          yield(user_query) if block_given?
          return {type: :object_list, fields: fields}.merge(api_read_all(resource_class_path, base_query.merge(user_query)))
        end

        def resolve_dropbox_name_default_ws_id(query)
          if query.key?('dropbox_name')
            # convenience: specify name instead of id
            raise 'not both dropbox_name and dropbox_id' if query.key?('dropbox_id')
            # TODO : craft a query that looks for dropbox only in current workspace
            query['dropbox_id'] = aoc_api.lookup_by_name('dropboxes', query['dropbox_name'])['id']
            query.delete('dropbox_name')
          end
          query['workspace_id'] ||= aoc_api.context[:workspace_id] unless aoc_api.context[:workspace_id].eql?(:undefined)
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
            workspace_id:   aoc_api.context[:workspace_id],
            workspace_name: aoc_api.context[:workspace_name],
            scope:          scope
          )
          file_id = top_node_api.read("access_keys/#{top_node_api.app_info[:node_info]['access_key']}")[:data]['root_file_id'] if file_id.nil?
          node_plugin = Node.new(@agents, api: top_node_api)
          case command_repo
          when *Node::COMMANDS_GEN4
            return node_plugin.execute_command_gen4(command_repo, file_id)
          when :transfer
            # client side is agent
            # server side is transfer server
            # in same workspace
            push_pull = options.get_next_argument('direction', expected: %i[push pull])
            source_folder = options.get_next_argument('folder of source files', type: String)
            case push_pull
            when :push
              client_direction = Fasp::TransferSpec::DIRECTION_SEND
              client_folder = source_folder
              server_folder = transfer.destination_folder(client_direction)
            when :pull
              client_direction = Fasp::TransferSpec::DIRECTION_RECEIVE
              client_folder = transfer.destination_folder(client_direction)
              server_folder = source_folder
            else error_unreachable_line
            end
            client_apfid = top_node_api.resolve_api_fid(file_id, client_folder)
            server_apfid = top_node_api.resolve_api_fid(file_id, server_folder)
            # force node as transfer agent
            @agents[:transfer].agent_instance = Fasp::AgentNode.new({
              url:      client_apfid[:api].params[:base_url],
              username: client_apfid[:api].app_info[:node_info]['access_key'],
              password: client_apfid[:api].oauth_token,
              root_id:  client_apfid[:file_id]
            })
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
          else error_unreachable_line
          end # command_repo
          error_unreachable_line
        end # execute_nodegen4_command

        def execute_admin_action
          # upgrade scope to admin
          aoc_api.oauth.generic_parameters[:scope] = AoC::SCOPE_FILES_ADMIN
          command_admin = options.get_next_command(%i[ats resource usage_reports analytics subscription auth_providers])
          case command_admin
          when :auth_providers
            command_auth_prov = options.get_next_command(%i[list update])
            case command_auth_prov
            when :list
              return result_list('admin/auth_providers')
            when :update
              raise 'not implemented'
            end
          when :subscription
            org = aoc_api.read('organization')[:data]
            bss_api = api_from_options('bss/platform')
            # cspell:disable
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
            # cspell:enable
            result = bss_api.create('graphql', {'variables' => {'organization_id' => org['id']}, 'query' => graphql_query})[:data]['data']
            return {type: :single_object, data: result['aoc']['bssSubscription']}
          when :ats
            ats_api = Rest.new(aoc_api.params.deep_merge({
              base_url: "#{aoc_api.params[:base_url]}/admin/ats/pub/v1",
              auth:     {scope: AoC::SCOPE_FILES_ADMIN_USER}
            }))
            return Ats.new(@agents).execute_action_gen(ats_api)
          when :analytics
            analytics_api = Rest.new(aoc_api.params.deep_merge({
              base_url: "#{aoc_api.params[:base_url].gsub('/api/v1', '')}/analytics/v2",
              auth:     {scope: AoC::SCOPE_FILES_ADMIN_USER}
            }))
            command_analytics = options.get_next_command(%i[application_events transfers])
            case command_analytics
            when :application_events
              event_type = command_analytics.to_s
              events = analytics_api.read("organizations/#{aoc_api.current_user_info['organization_id']}/#{event_type}")[:data][event_type]
              return {type: :object_list, data: events}
            when :transfers
              event_type = command_analytics.to_s
              filter_resource = options.get_next_argument('resource', expected: %i[organizations users nodes])
              filter_id = options.get_next_argument('identifier', mandatory: false) ||
                case filter_resource
                when :organizations then aoc_api.current_user_info['organization_id']
                when :users then aoc_api.current_user_info['id']
                when :nodes then aoc_api.current_user_info['id'] # TODO: consistent ? # rubocop:disable Lint/DuplicateBranch
                else error_unreachable_line
                end
              filter = options.get_option(:query) || {}
              filter['limit'] ||= 100
              if options.get_option(:once_only, mandatory: true)
                saved_date = []
                start_date_persistency = PersistencyActionOnce.new(
                  manager: @agents[:persistency],
                  data: saved_date,
                  id: IdGenerator.from_list([
                    'aoc_ana_date',
                    options.get_option(:url, mandatory: true),
                    aoc_api.context(:files)[:workspace_name],
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
              events = analytics_api.read("#{filter_resource}/#{filter_id}/#{event_type}", query_read_delete(default: filter))[:data][event_type]
              start_date_persistency&.save
              if !options.get_option(:notify_to).nil?
                events.each do |tr_event|
                  config.send_email_template(values: {ev: tr_event})
                end
              end
              return {type: :object_list, data: events}
            end
          when :resource
            resource_type = options.get_next_argument('resource', expected: KNOWN_AOC_RES)
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
                aoc_api.create(resource_class_path, params)[:data]
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
              when :group_membership then default_fields.push(*%w[group_id member_type member_id])
              when :workspace_membership then default_fields.push(*%w[workspace_id member_type member_id])
              end
              return result_list(resource_class_path, fields: default_fields, default_query: default_query)
            when :show
              object = aoc_api.read(resource_instance_path)[:data]
              # default: show all, but certificate
              fields = object.keys.reject{|k|k.eql?('certificate')}
              return { type: :single_object, data: object, fields: fields }
            when :modify
              changes = options.get_next_argument('properties', type: Hash)
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
              the_private_key = options.get_next_argument('private_key PEM value', type: String)
              the_public_key = OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s
              aoc_api.update(resource_instance_path, {jwt_grant_enabled: true, public_key: the_public_key})
              return Main.result_success
            when :do
              command_repo = options.get_next_command(NODE4_EXT_COMMANDS)
              # init context
              aoc_api.context(:files)
              return execute_nodegen4_command(command_repo, res_id)
            else error_unexpected_value(command)
            end
          when :usage_reports
            return result_list('usage_reports', base_query: {workspace_id: aoc_api.context(:files)[:workspace_id]})
          end
        end

        # must be public
        ACTIONS = %i[reminder servers bearer_token organization tier_restrictions user packages files admin automation gateway].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          if %i[files packages].include?(command)
            default_flag = ' (default)' if options.get_option(:workspace).eql?(:default)
            app_context = aoc_api.context(command)
            formatter.display_status("Workspace: #{app_context[:workspace_name].to_s.red}#{default_flag}")
            if !aoc_api.private_link.nil?
              folder_name = aoc_api.node_api_from(node_id: app_context[:home_node_id]).read("files/#{app_context[:home_file_id]}")[:data]['name']
              formatter.display_status("Private Folder: #{folder_name}")
            end
          end
          case command
          when :reminder
            # send an email reminder with list of orgs
            user_email = options.get_option(:username, mandatory: true)
            Rest.new(base_url: "#{AoC.api_base_url}/#{AoC::API_V1}").create('organization_reminders', {email: user_email})[:data]
            return Main.result_status("List of organizations user is member of, has been sent by e-mail to #{user_email}")
          when :servers
            return {type: :object_list, data: Rest.new(base_url: "#{AoC.api_base_url}/#{AoC::API_V1}").read('servers')[:data]}
          when :bearer_token
            return {type: :text, data: aoc_api.oauth_token}
          when :organization
            return { type: :single_object, data: aoc_api.read('organization')[:data] }
          when :tier_restrictions
            return { type: :single_object, data: aoc_api.read('tier_restrictions')[:data] }
          when :user
            case options.get_next_command(%i[workspaces profile preferences])
            # when :settings
            # return {type: :object_list,data: aoc_api.read('client_settings/')[:data]}
            when :workspaces
              case options.get_next_command(%i[list current])
              when :list
                return result_list('workspaces', fields: %w[id name])
              when :current
                return { type: :single_object, data: aoc_api.read("workspaces/#{aoc_api.context(:files)[:workspace_id]}")[:data] }
              end
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: aoc_api.current_user_info(exception: true) }
              when :modify
                aoc_api.update("users/#{aoc_api.current_user_info(exception: true)['id']}", options.get_next_argument('properties', type: Hash))
                return Main.result_status('modified')
              end
            when :preferences
              user_preferences_res = "users/#{aoc_api.current_user_info(exception: true)['id']}/user_interaction_preferences"
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: aoc_api.read(user_preferences_res)[:data] }
              when :modify
                aoc_api.update(user_preferences_res, options.get_next_argument('properties', type: Hash))
                return Main.result_status('modified')
              end
            end
          when :packages
            package_command = options.get_next_command(%i[shared_inboxes send receive list show delete].concat(Node::NODE4_READ_ACTIONS), aliases: {recv: :receive})
            case package_command
            when :shared_inboxes
              case options.get_next_command(%i[list show])
              when :list
                default_query = {'embed[]' => 'dropbox', 'aggregate_permissions_by_dropbox' => true, 'sort' => 'dropbox_name'}
                default_query['workspace_id'] = aoc_api.context[:workspace_id] unless aoc_api.context[:workspace_id].eql?(:undefined)
                return result_list('dropbox_memberships', fields: %w[dropbox_id dropbox.name], default_query: default_query)
              when :show
                return {type: :single_object, data: aoc_api.read(get_resource_path_from_args('dropboxes'), query)[:data]}
              end
            when :send
              package_data = value_create_modify(command: package_command)
              new_user_option = options.get_option(:new_user_option)
              option_validate = options.get_option(:validate_metadata)
              # works for both normal usr auth and link auth
              package_data['workspace_id'] ||= aoc_api.context[:workspace_id]

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
                  manager: @agents[:persistency],
                  data: skip_ids_data,
                  id: IdGenerator.from_list(
                    ['aoc_recv',
                     options.get_option(:url, mandatory: true),
                     aoc_api.context[:workspace_id]
                    ].concat(aoc_api.additional_persistence_ids)))
              end
              case ids_to_download
              when ExtendedValue::ALL, ExtendedValue::INIT
                query = query_read_delete(default: PACKAGE_RECEIVED_BASE_QUERY)
                assert_type(query, Hash){'query'}
                resolve_dropbox_name_default_ws_id(query)
                # remove from list the ones already downloaded
                all_ids = api_read_all('packages', query)[:data].map{|e|e['id']}
                if ids_to_download.eql?(ExtendedValue::INIT)
                  assert(skip_ids_persistency){'Only with option once_only'}
                  skip_ids_persistency.data.clear.concat(all_ids)
                  skip_ids_persistency.save
                  return Main.result_status("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
                end
                # array here
                ids_to_download = all_ids.reject{|id|skip_ids_data.include?(id)}
              else
                ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
              end # ExtendedValue::ALL
              # list here
              result_transfer = []
              formatter.display_status("found #{ids_to_download.length} package(s).")
              ids_to_download.each do |package_id|
                package_info = aoc_api.read("packages/#{package_id}")[:data]
                formatter.display_status("downloading package: [#{package_info['id']}] #{package_info['name']}")
                package_node_api = aoc_api.node_api_from(
                  node_id: package_info['node_id'],
                  workspace_id: aoc_api.context[:workspace_id],
                  workspace_name: aoc_api.context[:workspace_name],
                  package_info: package_info)
                statuses = transfer.start(
                  package_node_api.transfer_spec_gen4(
                    package_info['contents_file_id'],
                    Fasp::TransferSpec::DIRECTION_RECEIVE,
                    {'paths'=> [{'source' => '.'}]}),
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
              package_info = aoc_api.read("packages/#{package_id}")[:data]
              return { type: :single_object, data: package_info }
            when :list
              display_fields = %w[id name bytes_transferred]
              display_fields.push('workspace_id') if aoc_api.context[:workspace_id].eql?(:undefined)
              return result_list('packages', fields: display_fields, base_query: PACKAGE_RECEIVED_BASE_QUERY) do |query|
                       resolve_dropbox_name_default_ws_id(query)
                     end
            when :delete
              return do_bulk_operation(command: package_command, descr: 'identifier', values: identifier) do |id|
                assert_values(id.class, [String, Integer]){'identifier'}
                aoc_api.delete("packages/#{id}")[:data]
              end
            when *Node::NODE4_READ_ACTIONS
              package_id = instance_identifier
              package_info = aoc_api.read("packages/#{package_id}")[:data]
              return execute_nodegen4_command(package_command, package_info['node_id'], file_id: package_info['file_id'], scope: Aspera::Node::SCOPE_USER)
            end
          when :files
            command_repo = options.get_next_command([:short_link].concat(NODE4_EXT_COMMANDS))
            case command_repo
            when *NODE4_EXT_COMMANDS
              return execute_nodegen4_command(command_repo, aoc_api.context[:home_node_id], file_id: aoc_api.context[:home_file_id], scope: Aspera::Node::SCOPE_USER)
            when :short_link
              link_type = options.get_next_argument('link type', expected: %i[public private])
              short_link_command = options.get_next_command(%i[create delete list])
              folder_dest = options.get_next_argument('path', type: String)
              home_node_api = aoc_api.node_api_from(
                node_id:        aoc_api.context[:home_node_id],
                workspace_id:   aoc_api.context[:workspace_id],
                workspace_name: aoc_api.context[:workspace_name])
              shared_apfid = home_node_api.resolve_api_fid(aoc_api.context[:home_file_id], folder_dest)
              folder_info = {
                node_id:      shared_apfid[:api].app_info[:node_info]['id'],
                file_id:      shared_apfid[:file_id],
                workspace_id: aoc_api.context[:workspace_id]
              }
              purpose = case link_type
              when :public  then 'token_auth_redirection'
              when :private then 'shared_folder_auth_link'
              else error_unreachable_line
              end
              case short_link_command
              when :delete
                one_id = instance_identifier
                folder_info.delete(:workspace_id)
                delete_params = {
                  edit_access: true,
                  json_query:  folder_info.to_json
                }
                aoc_api.delete("short_links/#{one_id}", delete_params)
                if link_type.eql?(:public)
                  # TODO: get permission id..
                  # shared_apfid[:api].delete('permissions', {ids: })[:data]
                end
                return Main.result_status('deleted')
              when :list
                query = if link_type.eql?(:private)
                  folder_info
                else
                  {
                    url_token_data: {
                      data:    folder_info,
                      purpose: 'view_shared_file'
                    }
                  }
                end
                list_params = {
                  json_query:  query.to_json,
                  purpose:     purpose,
                  edit_access: true,
                  # embed: 'updated_by_user',
                  sort:        '-created_at'
                }
                return result_list('short_links', fields: Formatter.all_but('data'), base_query: list_params)
              when :create
                creation_params = {
                  purpose:            purpose,
                  user_selected_name: nil
                }
                case link_type
                when :private
                  creation_params[:data] = folder_info
                when :public
                  creation_params[:expires_at]       = nil
                  creation_params[:password_enabled] = false
                  folder_info[:name] = ''
                  creation_params[:data] = {
                    aoc:            true,
                    url_token_data: {
                      data:    folder_info,
                      purpose: 'view_shared_file'
                    }
                  }
                end
                result_create_short_link = aoc_api.create('short_links', creation_params)[:data]
                # public: Creation: permission on node
                if link_type.eql?(:public)
                  # TODO: merge with node permissions ?
                  # TODO: access level as arg
                  access_levels = Aspera::Node::ACCESS_LEVELS # ['delete','list','mkdir','preview','read','rename','write']
                  folder_name = File.basename(folder_dest)
                  perm_data = {
                    'file_id'       => shared_apfid[:file_id],
                    'access_id'     => result_create_short_link['resource_id'],
                    'access_type'   => 'user',
                    'access_levels' => access_levels,
                    'tags'          => {
                      'url_token'        => true,
                      'workspace_id'     => aoc_api.context[:workspace_id],
                      'workspace_name'   => aoc_api.context[:workspace_name],
                      'folder_name'      => folder_name,
                      'created_by_name'  => aoc_api.current_user_info['name'],
                      'created_by_email' => aoc_api.current_user_info['email'],
                      'access_key'       => shared_apfid[:api].app_info[:node_info]['access_key'],
                      'node'             => shared_apfid[:api].app_info[:node_info]['host']
                    }
                  }
                  created_data = shared_apfid[:api].create('permissions', perm_data)[:data]
                  aoc_api.permissions_send_event(created_data: created_data, app_info: shared_apfid[:api].app_info)
                  # TODO: event ?
                end
                return {type: :single_object, data: result_create_short_link}
              end # short_link command
            end # files command
            raise 'Error: shall not reach this line'
          when :automation
            Log.log.warn('BETA: work under progress')
            # automation api is not in the same place
            automation_rest_params = aoc_api.params.clone
            automation_rest_params[:base_url].gsub!('/api/', '/automation/')
            automation_api = Rest.new(automation_rest_params)
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
                data = automation_api.create("workflows/#{wf_id}/launch", {})[:data]
                return {type: :single_object, data: data}
              when :action
                # TODO: not complete
                wf_id = instance_identifier
                wf_action_cmd = options.get_next_command(%i[list create show])
                Log.log.warn{"Not implemented: #{wf_action_cmd}"}
                step = automation_api.create('steps', {'workflow_id' => wf_id})[:data]
                automation_api.update("workflows/#{wf_id}", {'step_order' => [step['id']]})
                action = automation_api.create('actions', {'step_id' => step['id'], 'type' => 'manual'})[:data]
                automation_api.update("steps/#{step['id']}", {'action_order' => [action['id']]})
                wf = automation_api.read("workflows/#{wf_id}")[:data]
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
            server.mount(uri.path, Faspex4GWServlet, aoc_api, aoc_api.context(:files)[:workspace_id])
            trap('INT') { server.shutdown }
            formatter.display_status("Faspex 4 gateway listening on #{url}")
            Log.log.info("Listening on #{url}")
            # this is blocking until server exits
            server.start
            return Main.result_status('Gateway terminated')
          else error_unreachable_line
          end # action
          error_unreachable_line
        end

        private :execute_admin_action
      end # AoC
    end # Plugins
  end # Cli
end # Aspera
