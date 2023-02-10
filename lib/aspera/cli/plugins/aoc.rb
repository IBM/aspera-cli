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
      class Aoc < Aspera::Cli::BasicAuthPlugin
        class << self
          def detect(base_url)
            api = Rest.new({base_url: base_url})
            # either in standard domain, or product name in page
            if URI.parse(base_url).host.end_with?(Aspera::AoC::PROD_DOMAIN) ||
                api.call({operation: 'GET', redirect_max: 1, headers: {'Accept' => 'text/html'}})[:http].body.include?(Aspera::AoC::PRODUCT_NAME)
              return {product: :aoc, version: 'SaaS' }
            end
            return nil
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
        ENTITY_NAME_SPECIFIER = 'name'
        PACKAGE_QUERY_DEFAULT = {'archived' => false, 'exclude_dropbox_packages' => true, 'has_content' => true, 'received' => true}.freeze

        def initialize(env)
          super(env)
          @cache_workspace_info = nil
          @cache_home_node_file = nil
          @cache_api_aoc = nil
          options.add_opt_list(:auth, Oauth::STD_AUTH_TYPES, 'OAuth type of authentication')
          options.add_opt_list(:operation, %i[push pull], 'client operation for transfers')
          options.add_opt_simple(:client_id, 'OAuth API client identifier')
          options.add_opt_simple(:client_secret, 'OAuth API client secret')
          options.add_opt_simple(:redirect_uri, 'OAuth API client redirect URI')
          options.add_opt_simple(:private_key, 'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.add_opt_simple(:scope, 'OAuth scope for AoC API calls')
          options.add_opt_simple(:passphrase, 'RSA private key passphrase')
          options.add_opt_simple(:workspace, 'Name of workspace')
          options.add_opt_simple(:name, "Resource name (prefer to use keyword #{ENTITY_NAME_SPECIFIER})")
          options.add_opt_simple(:link, 'Public link to shared resource')
          options.add_opt_simple(:new_user_option, 'New user creation option for unknown package recipients')
          options.add_opt_simple(:from_folder, 'Source folder for Folder-to-Folder transfer')
          options.add_opt_boolean(:validate_metadata, 'Validate shared inbox metadata')
          options.set_option(:validate_metadata, :yes)
          options.set_option(:operation, :push)
          options.set_option(:auth, :jwt)
          options.set_option(:scope, AoC::SCOPE_FILES_USER)
          options.set_option(:private_key, '@file:' + env[:private_key_path]) if env[:private_key_path].is_a?(String)
          options.set_option(:workspace, :default)
          options.parse_options!
          # add node plugin options
          Node.new(env.merge({man_only: true, skip_basic_auth_options: true}))
        end

        # build list of options for AoC API, based on options of CLI
        def aoc_params(subpath)
          # copy command line options to args
          return Aspera::AoC::OPTIONS_NEW.each_with_object({subpath: subpath}){|i, m|m[i] = options.get_option(i)}
        end

        def aoc_api
          if @cache_api_aoc.nil?
            @cache_api_aoc = AoC.new(aoc_params(AoC::API_V1))
            # add keychain for access key secrets
            @cache_api_aoc.secret_finder = @agents[:config]
          end
          return @cache_api_aoc
        end

        # @return [Hash] current workspace information,
        def current_workspace_info
          return @cache_workspace_info unless @cache_workspace_info.nil?
          default_workspace_id = if aoc_api.url_token_data.nil?
            aoc_api.current_user_info['default_workspace_id']
          else
            aoc_api.url_token_data['data']['workspace_id']
          end

          ws_name = options.get_option(:workspace)
          ws_id =
            case ws_name
            when :default
              Log.log.debug('Using default workspace'.green)
              raise CliError, 'No default workspace defined for user, please specify workspace' if default_workspace_id.nil?
              default_workspace_id
            when String then aoc_api.lookup_entity_by_name('workspaces', ws_name)['id']
            when NilClass then nil
            else raise CliError, 'unexpected value type for workspace'
            end
          @cache_workspace_info =
            begin
              aoc_api.read("workspaces/#{ws_id}")[:data]
            rescue Aspera::RestCallError => e
              Log.log.debug(e.message)
              { 'id' => :undefined, 'name' => :undefined }
            end
          Log.dump(:current_workspace_info, @cache_workspace_info)
          # display workspace
          default_flag = @cache_workspace_info['id'] == default_workspace_id ? ' (default)' : ''
          formatter.display_status("Current Workspace: #{@cache_workspace_info['name'].to_s.red}#{default_flag}")
          return @cache_workspace_info
        end

        # @return [Hash] with :node_id and :file_id
        def home_info
          return @cache_home_node_file unless @cache_home_node_file.nil?
          if !aoc_api.url_token_data.nil?
            assert_public_link_types(['view_shared_file'])
            home_node_id = aoc_api.url_token_data['data']['node_id']
            home_file_id = aoc_api.url_token_data['data']['file_id']
          end
          home_node_id ||= current_workspace_info['home_node_id'] || current_workspace_info['node_id']
          home_file_id ||= current_workspace_info['home_file_id']
          raise "Cannot get user's home node id, check your default workspace or specify one" if home_node_id.to_s.empty?
          @cache_home_node_file = {
            node_id: home_node_id,
            file_id: home_file_id
          }
          return @cache_home_node_file
        end

        # get identifier or name from command line
        # @return identifier
        def get_resource_id_from_args(resource_class_path)
          l_res_id = options.get_option(:id)
          l_res_name = options.get_option(:name)
          raise 'Provide either option id or name, not both' unless l_res_id.nil? || l_res_name.nil?
          # try to find item by name (single partial match or exact match)
          l_res_id = aoc_api.lookup_entity_by_name(resource_class_path, l_res_name)['id'] unless l_res_name.nil?
          # if no name or id option, taken on command line (after command)
          if l_res_id.nil?
            l_res_id = options.get_next_argument('identifier')
            l_res_id = aoc_api.lookup_entity_by_name(resource_class_path, options.get_next_argument('identifier'))['id'] if l_res_id.eql?(ENTITY_NAME_SPECIFIER)
          end
          return l_res_id
        end

        def get_resource_path_from_args(resource_class_path)
          return "#{resource_class_path}/#{get_resource_id_from_args(resource_class_path)}"
        end

        def assert_public_link_types(expected)
          raise CliBadArgument, "public link type is #{aoc_api.url_token_data['purpose']} but action requires one of #{expected.join(',')}" \
          unless expected.include?(aoc_api.url_token_data['purpose'])
        end

        # Call aoc_api.read with same parameters.
        # Use paging if necessary to get all results
        # @return [Hash] {list: , total: }
        def read_with_paging(resource_class_path, base_query)
          raise 'Query must be Hash' unless base_query.is_a?(Hash)
          # set default large page if user does not specify own parameters. AoC Caps to 1000 anyway
          base_query['per_page'] = 1000 unless base_query.key?('per_page')
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
            result = aoc_api.read(resource_class_path, query)
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
          return {list: item_list, total: total_count}
        end

        NODE4_EXT_COMMANDS = %i[transfer].concat(Node::COMMANDS_GEN4).freeze
        private_constant :NODE4_EXT_COMMANDS

        # @param file_id [String] root file id for the operation (can be AK root, or other, e.g. package, or link)
        # @param scope [String] node scope, or nil (admin)
        def execute_nodegen4_command(command_repo, node_id, file_id: nil, scope: nil)
          top_node_api = aoc_api.node_api_from(node_id: node_id, workspace_info: current_workspace_info, scope: scope)
          file_id = top_node_api.read("access_keys/#{top_node_api.app_info[:node_info]['access_key']}")[:data]['root_file_id'] if file_id.nil?
          node_plugin = Node.new(@agents.merge(
            skip_basic_auth_options: true,
            skip_node_options:       true,
            node_api:                top_node_api))
          case command_repo
          when *Node::COMMANDS_GEN4
            return node_plugin.execute_command_gen4(command_repo, file_id)
          when :transfer
            # client side is agent
            # server side is protocol server
            # in same workspace
            # default is push
            case options.get_option(:operation, is_type: :mandatory)
            when :push
              client_direction = Fasp::TransferSpec::DIRECTION_SEND
              client_folder = options.get_option(:from_folder, is_type: :mandatory)
              server_folder = transfer.destination_folder(client_direction)
            when :pull
              client_direction = Fasp::TransferSpec::DIRECTION_RECEIVE
              client_folder = transfer.destination_folder(client_direction)
              server_folder = options.get_option(:from_folder, is_type: :mandatory)
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
          else raise "INTERNAL ERROR: Missing case: #{command_repo}"
          end # command_repo
          # raise 'internal error:shall not reach here'
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
              providers = aoc_api.read('admin/auth_providers')[:data]
              return {type: :object_list, data: providers}
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
            result = bss_api.create('graphql', {'variables' => {'organization_id' => org['id']}, 'query' => graphql_query})[:data]['data']
            return {type: :single_object, data: result['aoc']['bssSubscription']}
          when :ats
            ats_api = Rest.new(aoc_api.params.deep_merge({
              base_url: aoc_api.params[:base_url] + '/admin/ats/pub/v1',
              auth:     {scope: AoC::SCOPE_FILES_ADMIN_USER}
            }))
            return Ats.new(@agents.merge(skip_node_options: true)).execute_action_gen(ats_api)
          when :analytics
            analytics_api = Rest.new(aoc_api.params.deep_merge({
              base_url: aoc_api.params[:base_url].gsub('/api/v1', '') + '/analytics/v2',
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
              filter_resource = options.get_option(:name) || 'organizations'
              filter_id = options.get_option(:id) ||
                case filter_resource
                when 'organizations' then aoc_api.current_user_info['organization_id']
                when 'users' then aoc_api.current_user_info['id']
                when 'nodes' then aoc_api.current_user_info['id'] # TODO: consistent ? # rubocop:disable Lint/DuplicateBranch
                else raise 'organizations or users for option --name'
                end
              filter = options.get_option(:query) || {}
              raise 'query must be Hash' unless filter.is_a?(Hash)
              filter['limit'] ||= 100
              if options.get_option(:once_only, is_type: :mandatory)
                saved_date = []
                start_date_persistency = PersistencyActionOnce.new(
                  manager: @agents[:persistency],
                  data: saved_date,
                  ids: IdGenerator.from_list(['aoc_ana_date', options.get_option(:url, is_type: :mandatory), current_workspace_info['name']].push(
                    filter_resource,
                    filter_id)))
                start_date_time = saved_date.first
                stop_date_time = Time.now.utc.strftime('%FT%T.%LZ')
                # Log.log().error("start: #{start_date_time}")
                # Log.log().error("end:   #{stop_date_time}")
                saved_date[0] = stop_date_time
                filter['start_time'] = start_date_time unless start_date_time.nil?
                filter['stop_time'] = stop_date_time
              end
              events = analytics_api.read("#{filter_resource}/#{filter_id}/#{event_type}", option_url_query(filter))[:data][event_type]
              start_date_persistency&.save
              if !options.get_option(:notif_to).nil?
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
              when :dropbox then resource_type.to_s + 'es'
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
              list_or_one = options.get_next_argument('creation data', type: Hash)
              return do_bulk_operation(list_or_one, 'created', id_result: id_result) do |params|
                raise 'expecting Hash' unless params.is_a?(Hash)
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
              items = read_with_paging(resource_class_path, option_url_query(default_query))
              count_msg = "Items: #{items[:list].length}/#{items[:total]}"
              count_msg = count_msg.bg_red unless items[:list].length.eql?(items[:total].to_i)
              formatter.display_status(count_msg)
              return {type: :object_list, data: items[:list], fields: default_fields}
            when :show
              object = aoc_api.read(resource_instance_path)[:data]
              fields = object.keys.reject{|k|k.eql?('certificate')}
              return { type: :single_object, data: object, fields: fields }
            when :modify
              changes = options.get_next_argument('modified parameters (hash)')
              aoc_api.update(resource_instance_path, changes)
              return Main.result_status('modified')
            when :delete
              return do_bulk_operation(res_id, 'deleted') do |one_id|
                aoc_api.delete("#{resource_class_path}/#{one_id}")
                {'id' => one_id}
              end
            when :set_pub_key
              # special : reads private and generate public
              the_private_key = options.get_next_argument('private_key')
              the_public_key = OpenSSL::PKey::RSA.new(the_private_key).public_key.to_s
              aoc_api.update(resource_instance_path, {jwt_grant_enabled: true, public_key: the_public_key})
              return Main.result_success
            when :do
              command_repo = options.get_next_command(NODE4_EXT_COMMANDS)
              return execute_nodegen4_command(command_repo, res_id)
            else raise 'unknown command'
            end
          when :usage_reports
            return {type: :object_list, data: aoc_api.read('usage_reports', {workspace_id: current_workspace_info['id']})[:data]}
          end
        end

        # must be public
        ACTIONS = %i[reminder servers bearer_token organization tier_restrictions user packages files admin automation gateway].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :reminder
            # send an email reminder with list of orgs
            user_email = options.get_option(:username, is_type: :mandatory)
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
            case options.get_next_command(%i[workspaces profile])
            # when :settings
            # return {type: :object_list,data: aoc_api.read('client_settings/')[:data]}
            when :workspaces
              case options.get_next_command(%i[list current])
              when :list
                return {type: :object_list, data: aoc_api.read('workspaces')[:data], fields: %w[id name]}
              when :current
                return { type: :single_object, data: current_workspace_info }
              end
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: aoc_api.current_user_info(exception: true) }
              when :modify
                aoc_api.update("users/#{aoc_api.current_user_info(exception: true)['id']}", options.get_next_argument('modified parameters (hash)'))
                return Main.result_status('modified')
              end
            end
          when :packages
            package_command = options.get_next_command(%i[shared_inboxes send recv list show delete].concat(Node::NODE4_READ_ACTIONS))
            case package_command
            when :shared_inboxes
              case options.get_next_command(%i[list show])
              when :list
                query = option_url_query(nil)
                if query.nil?
                  query = {'embed[]' => 'dropbox', 'aggregate_permissions_by_dropbox' => true, 'sort' => 'dropbox_name'}
                  query['workspace_id'] = current_workspace_info['id'] unless current_workspace_info['id'].eql?(:undefined)
                end
                return {type: :object_list, data: aoc_api.read('dropbox_memberships', query)[:data], fields: ['dropbox_id', 'dropbox.name']}
              when :show
                return {type: :single_object, data: aoc_api.read(get_resource_path_from_args('dropboxes'), query)[:data]}
              end
            when :send
              package_data = options.get_option(:value, is_type: :mandatory)
              raise CliBadArgument, 'value must be hash, refer to doc' unless package_data.is_a?(Hash)
              new_user_option = options.get_option(:new_user_option)
              option_validate = options.get_option(:validate_metadata)
              # works for both normal usr auth and link auth
              package_data['workspace_id'] ||= current_workspace_info['id']

              if !aoc_api.url_token_data.nil?
                assert_public_link_types(%w[send_package_to_user send_package_to_dropbox])
                box_type = aoc_api.url_token_data['purpose'].split('_').last
                package_data['recipients'] = [{'id' => aoc_api.url_token_data['data']["#{box_type}_id"], 'type' => box_type}]
                # enforce workspace id from link (should be already ok, but in case user wanted to override)
                package_data['workspace_id'] = aoc_api.url_token_data['data']['workspace_id']
              end

              # transfer may raise an error
              created_package = aoc_api.create_package_simple(package_data, option_validate, new_user_option)
              Main.result_transfer(transfer.start(created_package[:spec], rest_token: created_package[:node]))
              # return all info on package (especially package id)
              return { type: :single_object, data: created_package[:info]}
            when :recv
              if !aoc_api.url_token_data.nil?
                assert_public_link_types(['view_received_package'])
                options.set_option(:id, aoc_api.url_token_data['data']['package_id'])
              end
              # scalar here
              ids_to_download = instance_identifier
              skip_ids_data = []
              skip_ids_persistency = nil
              if options.get_option(:once_only, is_type: :mandatory)
                skip_ids_persistency = PersistencyActionOnce.new(
                  manager: @agents[:persistency],
                  data: skip_ids_data,
                  id: IdGenerator.from_list(['aoc_recv', options.get_option(:url, is_type: :mandatory),
                                             current_workspace_info['id']].concat(aoc_api.additional_persistence_ids)))
              end
              if VAL_ALL.eql?(ids_to_download)
                query = option_url_query(PACKAGE_QUERY_DEFAULT)
                raise 'option query must be Hash' unless query.is_a?(Hash)
                if query.key?('dropbox_name')
                  # convenience: specify name instead of id
                  raise 'not both dropbox_name and dropbox_id' if query.key?('dropbox_id')
                  query['dropbox_id'] = aoc_api.lookup_entity_by_name('dropboxes', query['dropbox_name'])['id']
                  query.delete('dropbox_name')
                end
                query['workspace_id'] ||= current_workspace_info['id'] unless current_workspace_info['id'].eql?(:undefined)
                # get list of packages in inbox
                package_info = aoc_api.read('packages', query)[:data]
                # remove from list the ones already downloaded
                ids_to_download = package_info.map{|e|e['id']}
                # array here
                ids_to_download.reject!{|id|skip_ids_data.include?(id)}
              end # VAL_ALL
              # list here
              ids_to_download = [ids_to_download] unless ids_to_download.is_a?(Array)
              result_transfer = []
              formatter.display_status("found #{ids_to_download.length} package(s).")
              ids_to_download.each do |package_id|
                package_info = aoc_api.read("packages/#{package_id}")[:data]
                formatter.display_status("downloading package: #{package_info['name']}")
                package_node_api = aoc_api.node_api_from(package_info: package_info, scope: AoC::SCOPE_NODE_USER)
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
              package_id = options.get_next_argument('package ID')
              package_info = aoc_api.read("packages/#{package_id}")[:data]
              return { type: :single_object, data: package_info }
            when :list
              display_fields = %w[id name bytes_transferred]
              query = option_url_query(PACKAGE_QUERY_DEFAULT)
              raise 'option query must be Hash' unless query.is_a?(Hash)
              if query.key?('dropbox_name')
                # convenience: specify name instead of id
                raise 'not both dropbox_name and dropbox_id' if query.key?('dropbox_id')
                query['dropbox_id'] = aoc_api.lookup_entity_by_name('dropboxes', query['dropbox_name'])['id']
                query.delete('dropbox_name')
              end
              if current_workspace_info['id'].eql?(:undefined)
                display_fields.push('workspace_id')
              else
                query['workspace_id'] ||= current_workspace_info['id']
              end
              packages = aoc_api.read('packages', query)[:data]
              return {type: :object_list, data: packages, fields: display_fields}
            when :delete
              list_or_one = instance_identifier
              return do_bulk_operation(list_or_one, 'deleted') do |id|
                raise 'expecting String identifier' unless id.is_a?(String) || id.is_a?(Integer)
                aoc_api.delete("packages/#{id}")[:data]
              end
            when *Node::NODE4_READ_ACTIONS
              package_id = options.get_next_argument('package ID')
              package_info = aoc_api.read("packages/#{package_id}")[:data]
              return execute_nodegen4_command(package_command, package_info['node_id'], file_id: package_info['file_id'], scope: AoC::SCOPE_NODE_USER)
            end
          when :files
            command_repo = options.get_next_command([:short_link].concat(NODE4_EXT_COMMANDS))
            case command_repo
            when *NODE4_EXT_COMMANDS
              return execute_nodegen4_command(command_repo, home_info[:node_id], file_id: home_info[:file_id], scope: AoC::SCOPE_NODE_USER)
            when :short_link
              # TODO: move to permissions ?
              folder_dest = options.get_option(:to_folder)
              value_option = options.get_option(:value)
              case value_option
              when 'public'  then value_option = {'purpose' => 'token_auth_redirection'}
              when 'private' then value_option = {'purpose' => 'shared_folder_auth_link'}
              when NilClass, Hash then nil # keep value
              else raise 'value must be either: public, private, Hash or nil'
              end
              create_params = nil
              shared_apfid = nil
              if !folder_dest.nil?
                home_node_api = aoc_api.node_api_from(node_id: home_info[:node_id], workspace_info: current_workspace_info, scope: AoC::SCOPE_NODE_USER)
                shared_apfid = home_node_api.resolve_api_fid(home_info[:file_id], folder_dest)
                create_params = {
                  file_id:      shared_apfid[:file_id],
                  node_id:      shared_apfid[:api].app_info[:node_info]['id'],
                  workspace_id: current_workspace_info['id']
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
                options.set_option(:value, value_option)
              end
              result = entity_action(aoc_api, 'short_links', id_default: 'self')
              if result[:data].is_a?(Hash) && result[:data].key?('created_at') && result[:data]['resource_type'].eql?('UrlToken')
                # TODO: access level as arg
                access_levels = Aspera::Node::ACCESS_LEVELS # ['delete','list','mkdir','preview','read','rename','write']
                perm_data = {
                  'file_id'       => shared_apfid[:file_id],
                  'access_type'   => 'user',
                  'access_id'     => result[:data]['resource_id'],
                  'access_levels' => access_levels,
                  'tags'          => {
                    'url_token'        => true,
                    'workspace_id'     => current_workspace_info['id'],
                    'workspace_name'   => current_workspace_info['name'],
                    'folder_name'      => 'my folder',
                    'created_by_name'  => aoc_api.current_user_info['name'],
                    'created_by_email' => aoc_api.current_user_info['email'],
                    'access_key'       => shared_apfid[:api].app_info[:node_info]['access_key'],
                    'node'             => shared_apfid[:api].app_info[:node_info]['host']
                  }
                }
                shared_apfid[:api].create("permissions?file_id=#{shared_apfid[:file_id]}", perm_data)
                # TODO: event ?
              end
              return result
            end # files command
            throw('Error: shall not reach this line')
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
                return entity_command(wf_command, automation_api, 'workflows', id_default: :id)
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
            url = options.get_option(:value, is_type: :mandatory)
            server = FaspexGW.new(URI.parse(url), aoc_api, current_workspace_info['id'])
            trap('INT') { server.shutdown }
            formatter.display_status("Faspex 4 gateway listening on #{url}")
            Log.log.info("Listening on #{url}")
            # this is blocking until server exits
            server.start
            return Main.result_status('Gateway terminated')
          else
            raise "internal error: #{command}"
          end # action
          raise 'internal error: command shall return'
        end

        private :aoc_params,
          :home_info,
          :assert_public_link_types,
          :execute_admin_action
      end # AoC
    end # Plugins
  end # Cli
end # Aspera
