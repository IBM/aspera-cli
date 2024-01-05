# frozen_string_literal: true

# spellchecker: ignore workgroups mypackages passcode

require 'aspera/cli/basic_auth_plugin'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/nagios'
require 'aspera/environment'
require 'securerandom'
require 'tty-spinner'

module Aspera
  module Cli
    module Plugins
      class Faspex5 < Aspera::Cli::BasicAuthPlugin
        RECIPIENT_TYPES = %w[user workgroup external_user distribution_list shared_inbox].freeze
        PACKAGE_TERMINATED = %w[completed failed].freeze
        API_DETECT = 'api/v5/configuration/ping'
        # list of supported mailbox types (to list packages)
        API_LIST_MAILBOX_TYPES = %w[inbox inbox_history inbox_all inbox_all_history outbox outbox_history pending pending_history all].freeze
        PACKAGE_ALL_INIT = 'INIT'
        PACKAGE_SEND_FROM_REMOTE_SOURCE = 'remote_source'
        # Faspex API v5: get transfer spec for connect
        TRANSFER_CONNECT = 'connect'
        ADMIN_RESOURCES = %i[
          accounts contacts jobs workgroups shared_inboxes nodes oauth_clients registrations saml_configs
          metadata_profiles email_notifications alternate_addresses
        ].freeze
        JOB_RUNNING = %w[queued working].freeze
        STANDARD_PATH = '/aspera/faspex'
        PER_PAGE_DEFAULT = 100
        private_constant(*%i[JOB_RUNNING RECIPIENT_TYPES PACKAGE_TERMINATED API_DETECT API_LIST_MAILBOX_TYPES PACKAGE_SEND_FROM_REMOTE_SOURCE PER_PAGE_DEFAULT])
        class << self
          def application_name
            'Faspex'
          end

          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)

            urls.each do |base_url|
              next unless base_url.start_with?('https://')
              api = Rest.new(base_url: base_url, redirect_max: 1)
              result = api.read(API_DETECT)
              next unless result[:http].code.start_with?('2') && result[:http].body.strip.empty?
              url_length = -2 - API_DETECT.length
              # take redirect if any
              return {
                version: result[:http]['x-ibm-aspera'] || '5',
                url:     result[:http].uri.to_s[0..url_length]
              }
            rescue StandardError => e
              Log.log.debug{"detect error: #{e}"}
            end
            return nil
          end

          def wizard(object:, private_key_path:, pub_key_pem:)
            options = object.options
            formatter = object.formatter
            instance_url = options.get_option(:url, mandatory: true)
            wiz_username = options.get_option(:username, mandatory: true)
            raise "Username shall be an email in Faspex: #{wiz_username}" if !(wiz_username =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
            if options.get_option(:client_id).nil? || options.get_option(:client_secret).nil?
              formatter.display_status('Ask the ascli client id and secret to your Administrator.'.red)
              formatter.display_status("Admin should login to: #{instance_url}")
              OpenApplication.instance.uri(instance_url)
              formatter.display_status('Navigate to: 𓃑  → Admin → Configurations → API clients')
              formatter.display_status('Create an API client with:')
              formatter.display_status('- name: ascli')
              formatter.display_status('- JWT: enabled')
              formatter.display_status("Then, logged in as #{wiz_username.red} go to your profile:")
              formatter.display_status('👤 → Account Settings → Preferences -> Public Key in PEM:')
              formatter.display_status(pub_key_pem)
              formatter.display_status('Once set, fill in the parameters:')
            end
            return {
              preset_value: {
                url:           instance_url,
                username:      wiz_username,
                auth:          :jwt.to_s,
                private_key:   "@file:#{private_key_path}",
                client_id:     options.get_option(:client_id, mandatory: true),
                client_secret: options.get_option(:client_secret, mandatory: true)
              },
              test_args:    'user profile show'
            }
          end

          def public_link?(url)
            url.include?('/public/')
          end
        end

        def initialize(env)
          super(env)
          options.declare(:client_id, 'OAuth client identifier')
          options.declare(:client_secret, 'OAuth client secret')
          options.declare(:redirect_uri, 'OAuth redirect URI for web authentication')
          options.declare(:auth, 'OAuth type of authentication', values: %i[boot].concat(Oauth::STD_AUTH_TYPES), default: :jwt)
          options.declare(:private_key, 'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.declare(:passphrase, 'OAuth JWT RSA private key passphrase')
          options.declare(:box, "Package inbox, either shared inbox name or one of: #{API_LIST_MAILBOX_TYPES.join(', ')} or #{ExtendedValue::ALL}", default: 'inbox')
          options.declare(:shared_folder, 'Send package with files from shared folder')
          options.declare(:group_type, 'Type of shared box', values: %i[shared_inboxes workgroups], default: :shared_inboxes)
          options.parse_options!
        end

        def api_url
          return "#{@faspex5_api_base_url}/api/v5"
        end

        def auth_api_url
          return "#{@faspex5_api_base_url}/auth"
        end

        def set_api
          # get endpoint, remove unnecessary trailing slashes
          @faspex5_api_base_url = options.get_option(:url, mandatory: true).gsub(%r{/+$}, '')
          auth_type = self.class.public_link?(@faspex5_api_base_url) ? :public_link : options.get_option(:auth, mandatory: true)
          case auth_type
          when :public_link
            encoded_context = Rest.decode_query(URI.parse(@faspex5_api_base_url).query)['context']
            raise 'Bad faspex5 public link, missing context in query' if encoded_context.nil?
            @pub_link_context = JSON.parse(Base64.decode64(encoded_context))
            Log.log.trace1{Log.dump(:@pub_link_context, @pub_link_context)}
            # ok, we have the additional parameters, get the base url
            @faspex5_api_base_url = @faspex5_api_base_url.gsub(%r{/public/.*}, '').gsub(/\?.*/, '')
            @api_v5 = Rest.new({
              base_url: api_url,
              headers:  {'Passcode' => @pub_link_context['passcode']}
            })
          when :boot
            # the password here is the token copied directly from browser in developer mode
            @api_v5 = Rest.new({
              base_url: api_url,
              headers:  {'Authorization' => options.get_option(:password, mandatory: true)}
            })
          when :web
            # opens a browser and ask user to auth using web
            @api_v5 = Rest.new({
              base_url: api_url,
              auth:     {
                type:         :oauth2,
                base_url:     auth_api_url,
                grant_method: :web,
                client_id:    options.get_option(:client_id, mandatory: true),
                web:          {redirect_uri: options.get_option(:redirect_uri, mandatory: true)}
              }})
          when :jwt
            app_client_id = options.get_option(:client_id, mandatory: true)
            @api_v5 = Rest.new({
              base_url: api_url,
              auth:     {
                type:         :oauth2,
                base_url:     auth_api_url,
                grant_method: :jwt,
                client_id:    app_client_id,
                jwt:          {
                  payload:         {
                    iss: app_client_id,    # issuer
                    aud: app_client_id,    # audience (this field is not clear...)
                    sub: "user:#{options.get_option(:username, mandatory: true)}" # subject is a user
                  },
                  private_key_obj: OpenSSL::PKey::RSA.new(options.get_option(:private_key, mandatory: true), options.get_option(:passphrase)),
                  headers:         {typ: 'JWT'}
                }
              }})
          else raise 'Unexpected case for option: auth'
          end
        end

        # if recipient is just an email, then convert to expected API hash : name and type
        def normalize_recipients(parameters)
          return unless parameters.key?('recipients')
          raise 'Field recipients must be an Array' unless parameters['recipients'].is_a?(Array)
          recipient_types = RECIPIENT_TYPES
          if parameters.key?('recipient_types')
            recipient_types = parameters['recipient_types']
            parameters.delete('recipient_types')
            recipient_types = [recipient_types] unless recipient_types.is_a?(Array)
          end
          parameters['recipients'].map! do |recipient_data|
            # if just a string, assume it is the name
            if recipient_data.is_a?(String)
              matched = @api_v5.lookup_by_name('contacts', recipient_data, {context: 'packages', type: Rest.array_params(recipient_types)})
              recipient_data = {
                name:           matched['name'],
                recipient_type: matched['type']
              }
            end
            # result for mapping
            recipient_data
          end
        end

        # wait for package status to be in provided list
        def wait_package_status(id, status_list: PACKAGE_TERMINATED)
          total_sent = false
          loop do
            status = @api_v5.read("packages/#{id}/upload_details")[:data]
            status['id'] = id
            # user asked to not follow
            return status if status_list.nil?
            if status['upload_status'].eql?('submitted')
              config.progress_bar&.event(session_id: nil, type: :pre_start, info: status['upload_status'])
            elsif !total_sent
              config.progress_bar&.event(session_id: id, type: :session_start)
              config.progress_bar&.event(session_id: id, type: :session_size, info: status['bytes_total'].to_i)
              total_sent = true
            else
              config.progress_bar&.event(session_id: id, type: :transfer, info: status['bytes_written'].to_i)
            end
            if status_list.include?(status['upload_status'])
              # if status['upload_status'].eql?('completed')
              config.progress_bar&.event(session_id: id, type: :end)
              return status
              # end
            end
            sleep(1.0)
          end
        end

        def wait_for_job(job_id)
          spinner = nil
          loop do
            status = @api_v5.read("jobs/#{job_id}", {type: :formatted})[:data]
            return status unless JOB_RUNNING.include?(status['status'])
            if spinner.nil?
              spinner = TTY::Spinner.new('[:spinner] :title', format: :classic)
              spinner.start
            end
            spinner.update(title: status['status'])
            spinner.spin
            sleep(0.5)
          end
          raise 'internal error'
        end

        # Get a (full or partial) list of all entities of a given type
        # @param type [String] the type of entity to list (just a name)
        # @param query [Hash,nil] additional query parameters
        # @param real_path [String] real path if it's n ot just the type
        # @param item_list_key [String] key in the result to get the list of items
        def list_entities(type:, real_path: nil, query: nil, item_list_key: nil)
          query = {} if query.nil?
          type = type.to_s if type.is_a?(Symbol)
          item_list_key = type if item_list_key.nil?
          raise "internal error: Invalid type #{type.class}" unless type.is_a?(String)
          full_path = real_path.nil? ? type : real_path
          result = []
          offset = 0
          max_items = query.delete(MAX_ITEMS)
          remain_pages = query.delete(MAX_PAGES)
          # merge default parameters, by default 100 per page
          query = {'limit'=> PER_PAGE_DEFAULT}.merge(query)
          loop do
            query['offset'] = offset
            page_result = @api_v5.read(full_path, query)[:data]
            result.concat(page_result[item_list_key])
            # reach the limit set by user ?
            if !max_items.nil? && (result.length >= max_items)
              result = result.slice(0, max_items)
              break
            end
            break if result.length >= page_result['total_count']
            remain_pages -= 1 unless remain_pages.nil?
            break if remain_pages == 0
            offset += page_result[item_list_key].length
          end
          return result
        end

        # lookup an entity id from its name
        def lookup_entity_by_field(type:, value:, field: 'name', query: :default, real_path: nil, item_list_key: nil)
          if query.eql?(:default)
            raise 'Default query is on name only' unless field.eql?('name')
            query = {'q'=> value}
          end
          found = list_entities(type: type, real_path: real_path, query: query, item_list_key: item_list_key).select{|i|i[field].eql?(value)}
          case found.length
          when 0 then raise "No #{type} with #{field} = #{value}"
          when 1 then return found.first
          else raise "Found #{found.length} #{real_path} with #{field} = #{value}"
          end
        end

        # list all packages with optional filter
        def list_packages_with_filter
          filter = options.get_next_argument('filter', mandatory: false, type: Proc, default: ->(_x){true})
          # translate box name to API prefix (with ending slash)
          box = options.get_option(:box)
          real_path =
            case box
            when ExtendedValue::ALL then 'packages' # only admin can list all packages globally
            when *API_LIST_MAILBOX_TYPES then "#{box}/packages"
            else
              group_type = options.get_option(:group_type)
              "#{group_type}/#{lookup_entity_by_field(type: group_type, value: box)['id']}/packages"
            end
          return list_entities(
            type: 'packages',
            query:  query_read_delete(default: {}),
            real_path: real_path).select(&filter)
        end

        def package_receive(package_ids)
          # prepare persistency if needed
          skip_ids_persistency = nil
          if options.get_option(:once_only, mandatory: true)
            # read ids from persistency
            skip_ids_persistency = PersistencyActionOnce.new(
              manager: @agents[:persistency],
              data:    [],
              id:      IdGenerator.from_list([
                'faspex_recv',
                options.get_option(:url, mandatory: true),
                options.get_option(:username, mandatory: true),
                options.get_option(:box, mandatory: true)
              ]))
          end
          packages = []
          case package_ids
          when PACKAGE_ALL_INIT
            raise 'Only with option once_only' unless skip_ids_persistency
            skip_ids_persistency.data.clear.concat(list_packages_with_filter.map{|p|p['id']})
            skip_ids_persistency.save
            return Main.result_status("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
          when ExtendedValue::ALL
            # TODO: if packages have same name, they will overwrite ?
            packages = list_packages_with_filter
            Log.log.trace1{Log.dump(:package_ids, packages.map{|p|p['id']})}
            Log.log.trace1{Log.dump(:skip_ids, skip_ids_persistency.data)}
            packages.reject!{|p|skip_ids_persistency.data.include?(p['id'])} if skip_ids_persistency
            Log.log.trace1{Log.dump(:package_ids, packages.map{|p|p['id']})}
          else
            # a single id was provided, or a list of ids
            package_ids = [package_ids] unless package_ids.is_a?(Array)
            raise 'Expecting a single package id or a list of ids' unless package_ids.is_a?(Array)
            raise 'Package id shall be String' unless package_ids.all?(String)
            # packages = package_ids.map{|pkg_id|@api_v5.read("packages/#{pkg_id}")[:data]}
            packages = package_ids.map{|pkg_id|{'id'=>pkg_id}}
          end
          result_transfer = []
          param_file_list = {}
          begin
            param_file_list['paths'] = transfer.source_list.map{|source|{'path'=>source}}
          rescue Cli::BadArgument
            # paths is optional
          end
          download_params = {
            type:          'received',
            transfer_type: TRANSFER_CONNECT
          }
          box = options.get_option(:box)
          case box
          when /outbox/ then download_params[:type] = 'sent'
          when *API_LIST_MAILBOX_TYPES then nil # nothing to do
          else # shared inbox / workgroup
            download_params[:recipient_workgroup_id] = lookup_entity_by_field(type: options.get_option(:group_type), value: box)['id']
          end
          packages.each do |package|
            pkg_id = package['id']
            formatter.display_status("Receiving package #{pkg_id}")
            # TODO: allow from sent as well ?
            transfer_spec = @api_v5.call(
              operation:   'POST',
              subpath:     "packages/#{pkg_id}/transfer_spec/download",
              headers:     {'Accept' => 'application/json'},
              url_params:  download_params,
              json_params: param_file_list
            )[:data]
            # delete flag for Connect Client
            transfer_spec.delete('authentication')
            statuses = transfer.start(transfer_spec)
            result_transfer.push({'package' => pkg_id, Main::STATUS_FIELD => statuses})
            # skip only if all sessions completed
            if TransferAgent.session_status(statuses).eql?(:success) && skip_ids_persistency
              skip_ids_persistency.data.push(pkg_id)
              skip_ids_persistency.save
            end
          end
          return Main.result_transfer_multiple(result_transfer)
        end

        def package_action
          command = options.get_next_command(%i[show browse status delete receive send list])
          package_id =
            if %i[receive show browse status delete].include?(command)
              @pub_link_context&.key?('package_id') ? @pub_link_context['package_id'] : instance_identifier
            end
          case command
          when :show
            return {type: :single_object, data: @api_v5.read("packages/#{package_id}")[:data]}
          when :browse
            path = options.get_next_argument('path', expected: :single, mandatory: false) || '/'
            # TODO: support multi-page listing ?
            params = {
              # recipient_user_id: 25,
              # offset:            0,
              # limit:             25
            }
            result = @api_v5.call({
              operation:   'POST',
              subpath:     "packages/#{package_id}/files/received",
              headers:     {'Accept' => 'application/json'},
              url_params:  params,
              json_params: {'path' => path, 'filters' => {'basenames'=>[]}}})[:data]
            formatter.display_item_count(result['item_count'], result['total_count'])
            return {type: :object_list, data: result['items']}
          when :status
            status = wait_package_status(package_id, status_list: nil)
            return {type: :single_object, data: status}
          when :delete
            ids = package_id
            ids = [ids] unless ids.is_a?(Array)
            raise 'Package identifier must be a single id or an Array' unless ids.is_a?(Array) && ids.all?(String)
            # API returns 204, empty on success
            @api_v5.call({operation: 'DELETE', subpath: 'packages', headers: {'Accept' => 'application/json'}, json_params: {ids: ids}})
            return Main.result_status('Package(s) deleted')
          when :receive
            return package_receive(package_id)
          when :send
            parameters = value_create_modify(command: command)
            normalize_recipients(parameters)
            package = @api_v5.create('packages', parameters)[:data]
            shared_folder = options.get_option(:shared_folder)
            if shared_folder.nil?
              # send from local files
              transfer_spec = @api_v5.call(
                operation:   'POST',
                subpath:     "packages/#{package['id']}/transfer_spec/upload",
                headers:     {'Accept' => 'application/json'},
                url_params:  {transfer_type: TRANSFER_CONNECT},
                json_params: {paths: transfer.source_list}
              )[:data]
              # well, we asked a TS for connect, but we actually want a generic one
              transfer_spec.delete('authentication')
              return Main.result_transfer(transfer.start(transfer_spec))
            else
              # send from remote shared folder
              if (m = shared_folder.match(REGEX_LOOKUP_ID_BY_FIELD))
                shared_folder = lookup_entity_by_field(type: 'shared_folders', value: m[2])['id']
              end
              transfer_request = {shared_folder_id: shared_folder, paths: transfer.source_list}
              # start remote transfer and get first status
              result = @api_v5.create("packages/#{package['id']}/remote_transfer", transfer_request)[:data]
              result['id'] = package['id']
              unless result['status'].eql?('completed')
                formatter.display_status("Package #{package['id']}")
                result = wait_package_status(package['id'])
              end
              return {type: :single_object, data: result}
            end
          when :list
            return {
              type:   :object_list,
              data:   list_packages_with_filter,
              fields: %w[id title release_date total_bytes total_files created_time state]
            }
          end # case package
        end

        ACTIONS = %i[health version user bearer_token packages shared_folders admin gateway postprocessing].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          set_api unless command.eql?(:postprocessing)
          case command
          when :version
            return { type: :single_object, data: @api_v5.read('version')[:data] }
          when :health
            nagios = Nagios.new
            begin
              result = Rest.new(base_url: @faspex5_api_base_url).read('health')[:data]
              result.each do |k, v|
                nagios.add_ok(k, v.to_s)
              end
            rescue StandardError => e
              nagios.add_critical('faspex api', e.to_s)
            end
            return nagios.result
          when :user
            case options.get_next_command(%i[profile])
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return { type: :single_object, data: @api_v5.read('account/preferences')[:data] }
              when :modify
                @api_v5.update('account/preferences', options.get_next_argument('modified parameters', type: Hash))
                return Main.result_status('modified')
              end
            end
          when :bearer_token
            return {type: :text, data: @api_v5.oauth_token}
          when :packages
            return package_action
          when :shared_folders
            all_shared_folders = @api_v5.read('shared_folders')[:data]['shared_folders']
            case options.get_next_command(%i[list browse])
            when :list
              return {type: :object_list, data: all_shared_folders}
            when :browse
              shared_folder_id = instance_identifier do |field, value|
                matches = all_shared_folders.select{|i|i[field].eql?(value)}
                raise "no match for #{field} = #{value}" if matches.empty?
                raise "multiple matches for #{field} = #{value}" if matches.length > 1
                matches.first['id']
              end
              path = options.get_next_argument('folder path', mandatory: false) || '/'
              node = all_shared_folders.find{|i|i['id'].eql?(shared_folder_id)}
              raise "No such shared folder id #{shared_folder_id}" if node.nil?
              result = @api_v5.call({
                operation:   'POST',
                subpath:     "nodes/#{node['node_id']}/shared_folders/#{shared_folder_id}/browse",
                headers:     {'Accept' => 'application/json', 'Content-Type' => 'application/json'},
                json_params: {'path': path, 'filters': {'basenames': []}},
                url_params:  {offset: 0, limit: 100}
              })[:data]
              if result.key?('items')
                return {type: :object_list, data: result['items']}
              else
                return {type: :single_object, data: result['self']}
              end
            end
          when :admin
            case options.get_next_command(%i[resource smtp].freeze)
            when :resource
              res_type = options.get_next_command(ADMIN_RESOURCES)
              res_path = list_key = res_type.to_s
              id_as_arg = false
              display_fields = nil
              adm_api = @api_v5
              special_query = :default
              available_commands = [].concat(Plugin::ALL_OPS)
              case res_type
              when :metadata_profiles
                res_path = 'configuration/metadata_profiles'
                list_key = 'profiles'
              when :alternate_addresses
                res_path = 'configuration/alternate_addresses'
              when :email_notifications
                list_key = false
                id_as_arg = 'type'
              when :accounts
                display_fields = Formatter.all_but('user_profile_data_attributes')
              when :oauth_clients
                display_fields = Formatter.all_but('public_key')
                adm_api = Rest.new(@api_v5.params.merge({base_url: auth_api_url}))
              when :shared_inboxes, :workgroups
                available_commands.push(:members, :saml_groups, :invite_external_collaborator)
                special_query = {'all': true}
              when :nodes
                available_commands.push(:shared_folders)
              end
              res_command = options.get_next_command(available_commands)
              case res_command
              when *Plugin::ALL_OPS
                return entity_command(res_command, adm_api, res_path, item_list_key: list_key, display_fields: display_fields, id_as_arg: id_as_arg) do |field, value|
                  lookup_entity_by_field(
                    type: res_type, real_path: res_path, field: field, value: value, query: special_query)['id']
                end
              when :shared_folders
                node_id = instance_identifier do |field, value|
                  lookup_entity_by_field(type: res_type.to_s, field: field, value: value)['id']
                end
                sh_path = "#{res_path}/#{node_id}/shared_folders"
                return entity_action(adm_api, sh_path, item_list_key: 'shared_folders') do |field, value|
                         lookup_entity_by_field(
                           type: 'shared_folders', real_path: sh_path, field: field, value: value)['id']
                       end
              when :invite_external_collaborator
                shared_inbox_id = instance_identifier { |field, value| lookup_entity_by_field(type: res_type.to_s, field: field, value: value)['id']}
                creation_payload = value_create_modify(command: res_command, type: [Hash, String])
                creation_payload = {'email_address' => creation_payload} if creation_payload.is_a?(String)
                res_path = "#{res_type}/#{shared_inbox_id}/external_collaborator"
                result = adm_api.create(res_path, creation_payload)[:data]
                formatter.display_status(result['message'])
                result = lookup_entity_by_field(
                  type: 'members', real_path: "#{res_type}/#{shared_inbox_id}/members", value: creation_payload['email_address'],
                  query: {})
                return {type: :single_object, data: result}
              when :members, :saml_groups
                res_id = instance_identifier { |field, value| lookup_entity_by_field(type: res_type.to_s, field: field, value: value)['id']}
                res_prefix = "#{res_type}/#{res_id}"
                res_path = "#{res_prefix}/#{res_command}"
                list_key = res_command.to_s
                list_key = 'groups' if res_command.eql?(:saml_groups)
                sub_command = options.get_next_command(%i[create list modify delete])
                if sub_command.eql?(:create) && options.get_option(:value).nil?
                  raise "use option 'value' to provide saml group_id and access (refer to API)" unless res_command.eql?(:members)
                  # first arg is one user name or list of users
                  users = options.get_next_argument('user id, or email, or list of')
                  users = [users] unless users.is_a?(Array)
                  users = users.map do |user|
                    if (m = user.match(REGEX_LOOKUP_ID_BY_FIELD))
                      lookup_entity_by_field(
                        type: 'accounts', field: m[1], value: m[2],
                        query: {type: Rest.array_params(%w{local_user saml_user self_registered_user external_user})})['id']
                    else
                      # it's the user id (not member id...)
                      user
                    end
                  end
                  access = options.get_next_argument('level', mandatory: false, expected: %i[submit_only standard shared_inbox_admin], default: :standard)
                  # TODO: unshift to command line parameters instead of using deprecated option "value"
                  options.set_option(:value, {user: users.map{|u|{id: u, access: access}}})
                end
                return entity_command(sub_command, adm_api, res_path, item_list_key: list_key) do |field, value|
                         lookup_entity_by_field(
                           type: 'accounts', field: field, value: value,
                           query: {type: Rest.array_params(%w{local_user saml_user self_registered_user external_user})})['id']
                       end
              end
            when :smtp
              smtp_path = 'configuration/smtp'
              smtp_cmd = options.get_next_command(%i[show create modify delete test])
              case smtp_cmd
              when :show
                return { type: :single_object, data: @api_v5.read(smtp_path)[:data] }
              when :create
                return { type: :single_object, data: @api_v5.create(smtp_path, value_create_modify(command: smtp_cmd))[:data] }
              when :modify
                return { type: :single_object, data: @api_v5.update(smtp_path, value_create_modify(command: smtp_cmd))[:data] }
              when :delete
                return { type: :single_object, data: @api_v5.delete(smtp_path)[:data] }
              when :test
                test_data = options.get_next_argument('Email or test data, see API')
                test_data = {test_email_recipient: test_data} if test_data.is_a?(String)
                creation = @api_v5.create(File.join(smtp_path, 'test'), test_data)[:data]
                result = wait_for_job(creation['job_id'])
                result['serialized_args'] = JSON.parse(result['serialized_args']) rescue result['serialized_args']
                return { type: :single_object, data: result }
              end
            end
          when :gateway
            require 'aspera/faspex_gw'
            url = value_create_modify(command: command, type: String)
            uri = URI.parse(url)
            server = WebServerSimple.new(uri)
            server.mount(uri.path, Faspex4GWServlet, @api_v5, nil)
            # on ctrl-c, tell server main loop to exit
            trap('INT') { server.shutdown }
            formatter.display_status("Gateway for Faspex 4-style API listening on #{url}")
            Log.log.info("Listening on #{url}")
            # this is blocking until server exits
            server.start
            return Main.result_status('Gateway terminated')
          when :postprocessing
            require 'aspera/faspex_postproc' # cspell:disable-line
            parameters = value_create_modify(command: command)
            parameters = parameters.symbolize_keys
            raise 'Missing key: url' unless parameters.key?(:url)
            uri = URI.parse(parameters[:url])
            parameters[:processing] ||= {}
            parameters[:processing][:root] = uri.path
            server = WebServerSimple.new(uri, certificate: parameters[:certificate])
            server.mount(uri.path, Faspex4PostProcServlet, parameters[:processing])
            # on ctrl-c, tell server main loop to exit
            trap('INT') { server.shutdown }
            formatter.display_status("Web-hook for Faspex 4-style post processing listening on #{uri.port}")
            Log.log.info("Listening on #{uri.port}")
            # this is blocking until server exits
            server.start
            return Main.result_status('Gateway terminated')
          end # case command
        end # action
      end # Faspex5
    end # Plugins
  end # Cli
end # Aspera
