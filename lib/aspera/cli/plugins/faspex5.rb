# frozen_string_literal: true

# spellchecker: ignore workgroups mypackages passcode

require 'aspera/cli/plugins/oauth'
require 'aspera/cli/extended_value'
require 'aspera/cli/special_values'
require 'aspera/cli/wizard'
require 'aspera/api/faspex'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/nagios'
require 'aspera/environment'
require 'aspera/assert'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      class Faspex5 < Oauth
        class << self
          def application_name
            'Faspex'
          end

          def detect(address_or_url)
            # add scheme if missing
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{Api::Faspex::PATH_STANDARD_ROOT}") unless address_or_url.end_with?(Api::Faspex::PATH_STANDARD_ROOT)
            error = nil
            urls.each do |base_url|
              # Faspex is always HTTPS
              next unless base_url.start_with?('https://')
              api = Rest.new(base_url: base_url, redirect_max: 1)
              response = api.call(operation: 'GET', subpath: Api::Faspex::PATH_API_DETECT)[:http]
              next unless response.code.start_with?('2') && response.body.strip.empty?
              # end is at -1, and subtract 1 for "/"
              url_length = -2 - Api::Faspex::PATH_API_DETECT.length
              # take redirect if any
              return {
                version: response[Api::Faspex::HEADER_FASPEX_VERSION] || '5',
                url:     response.uri.to_s[0..url_length]
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [Wizard] The wizard object
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          client_id = options.get_option(:client_id)
          client_secret = options.get_option(:client_secret)
          if client_id.nil? || client_secret.nil?
            formatter.display_status('Ask the ascli client id and secret to your Administrator.'.red)
            formatter.display_status("Log in as an admin user at: #{app_url}")
            Environment.instance.open_uri(app_url)
            formatter.display_status('Navigate to: 𓃑  → Admin → Configurations → API clients')
            formatter.display_status('Create an API client with:')
            formatter.display_status('- name: ascli')
            formatter.display_status('- JWT: enabled')
            formatter.display_status('Upon creation, the admin shall get those parameters:')
            client_id = options.get_option(:client_id, mandatory: wizard.required)
            client_secret = options.get_option(:client_secret, mandatory: wizard.required)
          end
          wiz_username = options.get_option(:username, mandatory: true)
          wizard.check_email(wiz_username)
          private_key_path = wizard.ask_private_key(
            user: wiz_username,
            url: app_url,
            page: '👤 → Account Settings → Preferences → Public Key in PEM'
          )
          return {
            preset_value: {
              url:           app_url,
              username:      wiz_username,
              auth:          :jwt.to_s,
              private_key:   "@file:#{private_key_path}",
              client_id:     client_id,
              client_secret: client_secret
            },
            test_args:    'user profile show'
          }
        end

        def initialize(**_)
          super
          options.declare(:box, "Package inbox, either shared inbox name or one of: #{Api::Faspex::API_LIST_MAILBOX_TYPES.join(', ')} or #{SpecialValues::ALL}", default: 'inbox')
          options.declare(:shared_folder, 'Send package with files from shared folder')
          options.declare(:group_type, 'Type of shared box', allowed: %i[shared_inboxes workgroups], default: :shared_inboxes)
          options.parse_options!
        end

        def set_api
          # create an API object with the same options, but with a different subpath
          @api_v5 = new_with_options(Api::Faspex)
          # in case user wants to use HTTPGW tell transfer agent how to get address
          transfer.httpgw_url_cb = lambda{@api_v5.read('account')['gateway_url']}
        end

        # if recipient is just an email, then convert to expected API hash : name and type
        def normalize_recipients(parameters)
          return unless parameters.key?('recipients')
          Aspera.assert_type(parameters['recipients'], Array){'recipients'}
          recipient_types = Api::Faspex::RECIPIENT_TYPES
          if parameters.key?('recipient_types')
            recipient_types = parameters['recipient_types']
            parameters.delete('recipient_types')
            recipient_types = [recipient_types] unless recipient_types.is_a?(Array)
          end
          parameters['recipients'].map! do |recipient_data|
            # if just a string, make a general lookup and build expected name/type hash
            if recipient_data.is_a?(String)
              matched = @api_v5.lookup_by_name('contacts', recipient_data, query: Rest.php_style({context: 'packages', type: recipient_types}))
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
        def wait_package_status(id, status_list: Api::Faspex::PACKAGE_TERMINATED)
          total_sent = false
          loop do
            status = @api_v5.read("packages/#{id}/upload_details")
            status['id'] = id
            # user asked to not follow
            return status if status_list.nil?
            if status['upload_status'].eql?('submitted')
              config.progress_bar&.event(:sessions_init, session_id: nil, info: status['upload_status'])
            elsif !total_sent
              config.progress_bar&.event(:session_start, session_id: id)
              config.progress_bar&.event(:session_size, session_id: id, info: status['bytes_total'].to_i)
              total_sent = true
            else
              config.progress_bar&.event(:transfer, session_id: id, info: status['bytes_written'].to_i)
            end
            if status_list.include?(status['upload_status'])
              config.progress_bar&.event(:session_end, session_id: id)
              config.progress_bar&.event(:end)
              return status
            end
            sleep(1.0)
          end
        end

        # @param [Srting] job identifier
        # @return [Hash] result of API call for job status
        def wait_for_job(job_id)
          result = nil
          loop do
            result = @api_v5.read("jobs/#{job_id}", {type: :formatted})
            break unless Api::Faspex::JOB_RUNNING.include?(result['status'])
            formatter.long_operation_running(result['status'])
            sleep(0.5)
          end
          formatter.long_operation_terminated
          return result
        end

        # list all packages with optional filter
        def list_packages_with_filter(query: {})
          filter = options.get_next_argument('filter', mandatory: false, validation: Proc, default: ->(_x){true})
          # translate box name to API prefix (with ending slash)
          box = options.get_option(:box)
          entity =
            case box
            when SpecialValues::ALL then 'packages' # only admin can list all packages globally
            when *Api::Faspex::API_LIST_MAILBOX_TYPES then "#{box}/packages"
            else
              group_type = options.get_option(:group_type)
              "#{group_type}/#{lookup_entity_by_field(api: @api_v5, entity: group_type, value: box)['id']}/packages"
            end
          list, total = list_entities_limit_offset_total_count(
            api: @api_v5,
            entity: entity,
            query:  query_read_delete(default: query)
          )
          return list.select(&filter), total
        end

        def package_receive(package_ids)
          # prepare persistency if needed
          skip_ids_persistency = nil
          if options.get_option(:once_only, mandatory: true)
            # read ids from persistency
            skip_ids_persistency = PersistencyActionOnce.new(
              manager: persistency,
              data:    [],
              id:      IdGenerator.from_list([
                'faspex_recv',
                options.get_option(:url, mandatory: true),
                options.get_option(:username, mandatory: true),
                options.get_option(:box, mandatory: true)
              ])
            )
          end
          packages = []
          case package_ids
          when SpecialValues::INIT
            Aspera.assert(skip_ids_persistency){'Only with option once_only'}
            skip_ids_persistency.data.clear.concat(list_packages_with_filter.first.map{ |p| p['id']})
            skip_ids_persistency.save
            return Main.result_status("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
          when SpecialValues::ALL
            # TODO: if packages have same name, they will overwrite ?
            packages = list_packages_with_filter(query: {'status' => 'completed'}).first
            Log.dump(:package_ids, level: :trace1){packages.map{ |p| p['id']}}
            Log.dump(:skip_ids, skip_ids_persistency.data, level: :trace1)
            packages.reject!{ |p| skip_ids_persistency.data.include?(p['id'])} if skip_ids_persistency
            Log.dump(:package_ids, level: :trace1){packages.map{ |p| p['id']}}
          else
            # a single id was provided, or a list of ids
            package_ids = [package_ids] unless package_ids.is_a?(Array)
            Aspera.assert_type(package_ids, Array){'Expecting a single package id or a list of ids'}
            Aspera.assert(package_ids.all?(String)){'Package id shall be String'}
            # packages = package_ids.map{|pkg_id|@api_v5.read("packages/#{pkg_id}")}
            packages = package_ids.map{ |pkg_id| {'id'=>pkg_id}}
          end
          result_transfer = []
          param_file_list = {}
          begin
            param_file_list['paths'] = transfer.source_list.map{ |source| {'path'=>source}}
          rescue Cli::BadArgument
            # paths is optional
          end
          download_params = {
            type:          'received',
            transfer_type: Api::Faspex::TRANSFER_CONNECT
          }
          box = options.get_option(:box)
          case box
          when /outbox/ then download_params[:type] = 'sent'
          when *Api::Faspex::API_LIST_MAILBOX_TYPES then nil # nothing to do
          else # shared inbox / workgroup
            download_params[:recipient_workgroup_id] = lookup_entity_by_field(api: @api_v5, entity: options.get_option(:group_type), value: box)['id']
          end
          packages.each do |package|
            pkg_id = package['id']
            formatter.display_status("Receiving package #{pkg_id}")
            # TODO: allow from sent as well ?
            transfer_spec = @api_v5.call(
              operation:    'POST',
              subpath:      "packages/#{pkg_id}/transfer_spec/download",
              query:        download_params,
              content_type: Rest::MIME_JSON,
              body:         param_file_list,
              headers:      {'Accept' => Rest::MIME_JSON}
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

        # Browse a folder
        # @param browse_endpoint [String] the endpoint to browse
        def browse_folder(browse_endpoint)
          folders_to_process = [options.get_next_argument('folder path', default: '/')]
          query = query_read_delete(default: {})
          filters = query.delete('filters'){{}}
          Aspera.assert_type(filters, Hash)
          filters['basenames'] ||= []
          Aspera.assert_type(filters, Hash){'filters'}
          max_items = query.delete(MAX_ITEMS)
          recursive = query.delete('recursive')
          use_paging = query.delete('paging'){true}
          if use_paging
            browse_endpoint = "#{browse_endpoint}/page"
            query['per_page'] ||= 500
          else
            query['offset'] ||= 0
            query['limit'] ||= 500
          end
          all_items = []
          total_count = nil
          until folders_to_process.empty?
            path = folders_to_process.shift
            loop do
              response = @api_v5.call(
                operation:    'POST',
                subpath:      browse_endpoint,
                query:        query,
                content_type: Rest::MIME_JSON,
                body:         {'path' => path, 'filters' => filters},
                headers:      {'Accept' => Rest::MIME_JSON}
              )
              all_items.concat(response[:data]['items'])
              if !max_items.nil? && (all_items.count >= max_items)
                all_items = all_items.slice(0, max_items) if all_items.count > max_items
                break
              end
              folders_to_process.concat(response[:data]['items'].select{ |i| i['type'].eql?('directory')}.map{ |i| i['path']}) if recursive
              if use_paging
                iteration_token = response[:http][Api::Faspex::HEADER_ITERATION_TOKEN]
                break if iteration_token.nil? || iteration_token.empty?
                query['iteration_token'] = iteration_token
              else
                total_count = response[:data]['total_count'] if total_count.nil?
                break if response[:data]['item_count'].eql?(0)
                query['offset'] += response[:data]['item_count']
              end
              formatter.long_operation_running(all_items.count)
            end
            query.delete('iteration_token')
          end
          formatter.long_operation_terminated

          return Main.result_object_list(all_items, total: total_count)
        end

        def package_action
          command = options.get_next_command(%i[show browse status delete receive send list])
          package_id =
            if %i[receive show browse status delete].include?(command)
              @api_v5.pub_link_context&.key?('package_id') ? @api_v5.pub_link_context['package_id'] : instance_identifier
            end
          case command
          when :show
            return Main.result_single_object(@api_v5.read("packages/#{package_id}"))
          when :browse
            location = case options.get_option(:box)
            when 'inbox' then 'received'
            when 'outbox' then 'sent'
            else raise BadArgument, 'Browse only available for inbox and outbox'
            end
            return browse_folder("packages/#{package_id}/files/#{location}")
          when :status
            status_list = options.get_next_argument('list of states, or nothing', mandatory: false, validation: Array)
            status = wait_package_status(package_id, status_list: status_list)
            return Main.result_single_object(status)
          when :delete
            ids = package_id
            ids = [ids] unless ids.is_a?(Array)
            Aspera.assert_type(ids, Array){'Package identifier'}
            Aspera.assert(ids.all?(String)){"Package id(s) shall be String, but have: #{ids.map(&:class).uniq.join(', ')}"}
            # API returns 204, empty on success
            @api_v5.call(
              operation:    'DELETE',
              subpath:      'packages',
              content_type: Rest::MIME_JSON,
              body:         {ids: ids},
              headers:      {'Accept' => Rest::MIME_JSON}
            )
            return Main.result_status('Package(s) deleted')
          when :receive
            return package_receive(package_id)
          when :send
            parameters = value_create_modify(command: command)
            # autofill recipient for public url
            if @api_v5.pub_link_context&.key?('recipient_type') && !parameters.key?('recipients')
              parameters['recipients'] = [{
                name:           @api_v5.pub_link_context['name'],
                recipient_type: @api_v5.pub_link_context['recipient_type']
              }]
            end
            normalize_recipients(parameters)
            package = @api_v5.create('packages', parameters)
            shared_folder = options.get_option(:shared_folder)
            if shared_folder.nil?
              # send from local files
              transfer_spec = @api_v5.call(
                operation:    'POST',
                subpath:      "packages/#{package['id']}/transfer_spec/upload",
                query:        {transfer_type: Api::Faspex::TRANSFER_CONNECT},
                content_type: Rest::MIME_JSON,
                body:         {paths: transfer.source_list},
                headers:      {'Accept' => Rest::MIME_JSON}
              )[:data]
              # well, we asked a TS for connect, but we actually want a generic one
              transfer_spec.delete('authentication')
              return Main.result_transfer(transfer.start(transfer_spec))
            else
              # send from remote shared folder
              if (m = percent_selector?(shared_folder))
                shared_folder = lookup_entity_by_field(
                  api: @api_v5,
                  entity: 'shared_folders',
                  field: m[:field],
                  value: m[:value]
                )['id']
              end
              transfer_request = {shared_folder_id: shared_folder, paths: transfer.source_list}
              # start remote transfer and get first status
              result = @api_v5.create("packages/#{package['id']}/remote_transfer", transfer_request)
              result['id'] = package['id']
              unless result['status'].eql?('completed')
                formatter.display_status("Package #{package['id']}")
                result = wait_package_status(package['id'])
              end
              return Main.result_single_object(result)
            end
          when :list
            list, total = list_packages_with_filter
            return Main.result_object_list(list, total: total, fields: %w[id title release_date total_bytes total_files created_time state])
          end
        end

        def execute_resource(res_sym)
          exec_args = {
            api:    @api_v5,
            entity: res_sym.to_s,
            tclo:   true
          }
          res_id_query = :default
          available_commands = ALL_OPS
          case res_sym
          when :metadata_profiles
            exec_args[:entity] = 'configuration/metadata_profiles'
            exec_args[:items_key] = 'profiles'
          when :alternate_addresses
            exec_args[:entity] = 'configuration/alternate_addresses'
          when :distribution_lists
            exec_args[:entity] = 'account/distribution_lists'
            exec_args[:delete_style] = 'ids'
          when :email_notifications
            exec_args.delete(:items_key)
            exec_args[:id_as_arg] = 'type'
          when :accounts
            exec_args[:display_fields] = Formatter.all_but('user_profile_data_attributes')
            available_commands += [:reset_password]
          when :oauth_clients
            exec_args[:display_fields] = Formatter.all_but('public_key')
            exec_args[:api] = @api_v5.auth_api
            exec_args[:list_query] = {'expand': true, 'no_api_path': true, 'client_types[]': 'public'}
          when :shared_inboxes, :workgroups
            available_commands += %i[members saml_groups invite_external_collaborator]
            res_id_query = {'all': true}
          when :nodes
            available_commands += %i[shared_folders browse]
          end
          res_command = options.get_next_command(available_commands)
          return Main.result_value_list(Api::Faspex::EMAIL_NOTIF_LIST, name: 'email_id') if res_command.eql?(:list) && res_sym.eql?(:email_notifications)
          case res_command
          when *ALL_OPS
            return entity_execute(command: res_command, **exec_args) do |field, value|
                     lookup_entity_by_field(api: @api_v5, entity: exec_args[:entity], value: value, field: field, items_key: exec_args[:items_key], query: res_id_query)['id']
                   end
          when :shared_folders
            # nodes
            node_id = instance_identifier do |field, value|
              lookup_entity_by_field(api: @api_v5, entity: 'nodes', field: field, value: value)['id']
            end
            shfld_entity = "nodes/#{node_id}/shared_folders"
            sh_command = options.get_next_command(ALL_OPS + [:user])
            case sh_command
            when *ALL_OPS
              return entity_execute(
                api: @api_v5,
                entity: shfld_entity,
                command: sh_command
              ) do |field, value|
                       lookup_entity_by_field(api: @api_v5, entity: shfld_entity, field: field, value: value)['id']
                     end
            when :user
              sh_id = instance_identifier do |field, value|
                lookup_entity_by_field(api: @api_v5, entity: shfld_entity, field: field, value: value)['id']
              end
              user_path = "#{shfld_entity}/#{sh_id}/custom_access_users"
              return entity_execute(api: @api_v5, entity: user_path, items_key: 'users') do |field, value|
                       lookup_entity_by_field(api: @api_v5, entity: user_path, items_key: 'users', field: field, value: value)['id']
                     end

            end
          when :browse
            # nodes
            node_id = instance_identifier do |field, value|
              lookup_entity_by_field(api: @api_v5, entity: 'nodes', value: value, field: field)['id']
            end
            return browse_folder("nodes/#{node_id}/browse")
          when :invite_external_collaborator
            # :shared_inboxes, :workgroups
            shared_inbox_id = instance_identifier{ |field, value| lookup_entity_by_field(api: @api_v5, entity: res_sym.to_s, field: field, value: value, query: res_id_query)['id']}
            creation_payload = value_create_modify(command: res_command, type: [Hash, String])
            creation_payload = {'email_address' => creation_payload} if creation_payload.is_a?(String)
            result = @api_v5.create("#{res_sym}/#{shared_inbox_id}/external_collaborator", creation_payload)
            formatter.display_status(result['message'])
            result = lookup_entity_by_field(
              api: @api_v5,
              entity: "#{res_sym}/#{shared_inbox_id}/members",
              items_key: 'members',
              value: creation_payload['email_address'],
              query: {}
            )
            return Main.result_single_object(result)
          when :members, :saml_groups
            # :shared_inboxes, :workgroups
            res_id = instance_identifier{ |field, value| lookup_entity_by_field(api: @api_v5, entity: res_sym.to_s, field: field, value: value, query: res_id_query)['id']}
            res_path = "#{res_sym}/#{res_id}/#{res_command}"
            list_key = res_command.to_s
            list_key = 'groups' if res_command.eql?(:saml_groups)
            sub_command = options.get_next_command(%i[create list modify delete])
            if sub_command.eql?(:create) && res_command.eql?(:members)
              # first arg is one user name or list of users
              users = options.get_next_argument('user id, %name:, or Array')
              users = [users] unless users.is_a?(Array)
              users = users.map do |user|
                if (m = percent_selector?(user))
                  lookup_entity_by_field(
                    api: @api_v5,
                    entity: 'accounts',
                    field: m[:field],
                    value: m[:value],
                    query: Rest.php_style({type: %w{local_user saml_user self_registered_user external_user}})
                  )['id']
                else
                  # it's the user id (not member id...)
                  user
                end
              end
              access = options.get_next_argument('level', mandatory: false, accept_list: SHARED_INBOX_MEMBER_LEVELS, default: :standard)
              options.unshift_next_argument({user: users.map{ |u| {id: u, access: access}}})
            end
            return entity_execute(
              api: @api_v5,
              entity: res_path,
              command: sub_command,
              items_key: list_key
            ) do |field, value|
                     lookup_entity_by_field(
                       api: @api_v5,
                       entity: 'contacts',
                       field: field,
                       value: value,
                       query: Rest.php_style({type: %w{local_user saml_user self_registered_user external_user}})
                     )['id']
                   end
          when :reset_password
            # :accounts
            contact_id = instance_identifier{ |field, value| lookup_entity_by_field(api: @api_v5, entity: 'accounts', field: field, value: value, query: res_id_query)['id']}
            @api_v5.create("accounts/#{contact_id}/reset_password", {})
            return Main.result_status('password reset, user shall check email')
          end
          Aspera.error_unreachable_line
        end

        def execute_admin
          command = options.get_next_command(%i[configuration smtp events clean_deleted].concat(Api::Faspex::ADMIN_RESOURCES).freeze)
          case command
          when *Api::Faspex::ADMIN_RESOURCES
            return execute_resource(command)
          when :clean_deleted
            delete_data = value_create_modify(command: command, default: {})
            delete_data = @api_v5.read('configuration').slice('days_before_deleting_package_records') if delete_data.empty?
            res = @api_v5.create('internal/packages/clean_deleted', delete_data)
            return Main.result_single_object(res)
          when :events
            event_type = options.get_next_command(%i[application webhook])
            case event_type
            when :application
              list, total = list_entities_limit_offset_total_count(
                api: @api_v5,
                entity: 'application_events',
                query: query_read_delete
              )

              return Main.result_object_list(list, total: total, fields: %w[event_type created_at application user.name])
            when :webhook
              list, total = list_entities_limit_offset_total_count(
                api: @api_v5,
                entity: 'all_webhooks_events',
                query: query_read_delete,
                items_key: 'events'
              )
              return Main.result_object_list(list, total: total)
            end
          when :configuration
            conf_path = 'configuration'
            conf_cmd = options.get_next_command(%i[show modify])
            case conf_cmd
            when :show
              return Main.result_single_object(@api_v5.read(conf_path))
            when :modify
              return Main.result_single_object(@api_v5.update(conf_path, value_create_modify(command: conf_cmd)))
            end
          when :smtp
            # only one SMTP config
            smtp_path = 'configuration/smtp'
            smtp_cmd = options.get_next_command(%i[show create modify delete test])
            case smtp_cmd
            when :show
              return Main.result_single_object(@api_v5.read(smtp_path))
            when :create
              return Main.result_single_object(@api_v5.create(smtp_path, value_create_modify(command: smtp_cmd)))
            when :modify
              return Main.result_single_object(@api_v5.update(smtp_path, value_create_modify(command: smtp_cmd)))
            when :delete
              @api_v5.delete(smtp_path)
              return Main.result_status('SMTP configuration deleted')
            when :test
              test_data = options.get_next_argument('Email or test data, see API')
              test_data = {test_email_recipient: test_data} if test_data.is_a?(String)
              creation = @api_v5.create(File.join(smtp_path, 'test'), test_data)
              result = wait_for_job(creation['job_id'])
              result['serialized_args'] = JSON.parse(result['serialized_args']) rescue result['serialized_args']
              return Main.result_single_object(result)
            end
          end
        end

        ACTIONS = %i[health version user bearer_token packages shared_folders admin gateway postprocessing invitations].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          set_api unless %i{postprocessing health}.include?(command)
          case command
          when :version
            return Main.result_single_object(@api_v5.read('version'))
          when :health
            nagios = Nagios.new
            begin
              http_res = Rest.new(base_url: options.get_option(:url, mandatory: true))
                .call(operation: 'GET', subpath: 'health', headers: {'Accept' => Rest::MIME_JSON})
              http_res[:data].each do |k, v|
                nagios.add_ok(k, v.to_s)
              end
              nagios.add_ok('version', http_res[:http]['X-IBM-Aspera']) if http_res[:http]['X-IBM-Aspera']
            rescue StandardError => e
              nagios.add_critical('core', e.to_s)
            end
            Main.result_object_list(nagios.status_list)
          when :user
            case options.get_next_command(%i[account profile])
            when :account
              return Main.result_single_object(@api_v5.read('account', query_read_delete))
            when :profile
              case options.get_next_command(%i[show modify])
              when :show
                return Main.result_single_object(@api_v5.read('account/preferences'))
              when :modify
                @api_v5.update('account/preferences', options.get_next_argument('modified parameters', validation: Hash))
                return Main.result_status('modified')
              end
            end
          when :bearer_token
            return Main.result_text(@api_v5.oauth.authorization)
          when :packages
            return package_action
          when :shared_folders
            all_shared_folders = @api_v5.read('shared_folders')['shared_folders']
            case options.get_next_command(%i[list browse])
            when :list
              return Main.result_object_list(all_shared_folders)
            when :browse
              shared_folder_id = instance_identifier do |field, value|
                matches = all_shared_folders.select{ |i| i[field].eql?(value)}
                raise "no match for #{field} = #{value}" if matches.empty?
                raise "multiple matches for #{field} = #{value}" if matches.length > 1
                matches.first['id']
              end
              node = all_shared_folders.find{ |i| i['id'].eql?(shared_folder_id)}
              raise "No such shared folder id #{shared_folder_id}" if node.nil?
              return browse_folder("nodes/#{node['node_id']}/shared_folders/#{shared_folder_id}/browse")
            end
          when :admin
            return execute_admin
          when :invitations
            invitation_endpoint = 'invitations'
            invitation_command = options.get_next_command(%i[resend].concat(ALL_OPS))
            case invitation_command
            when :create
              return do_bulk_operation(command: invitation_command, descr: 'data') do |params|
                invitation_endpoint = params.key?('recipient_name') ? 'public_invitations' : 'invitations'
                @api_v5.create(invitation_endpoint, params)
              end
            when :resend
              @api_v5.create("#{invitation_endpoint}/#{instance_identifier}/resend")
              return Main.result_status('Invitation resent')
            else
              return entity_execute(
                api: @api_v5,
                entity: invitation_endpoint,
                command: invitation_command,
                items_key: invitation_endpoint,
                display_fields: %w[id public recipient_type recipient_name email_address]
              ) do |field, value|
                lookup_entity_by_field(api: @api_v5, entity: invitation_endpoint, field: field, value: value, query: {})['id']
              end
            end
          when :gateway
            require 'aspera/faspex_gw'
            parameters = value_create_modify(command: command, default: {}).symbolize_keys
            uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
            server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
            Aspera.assert(parameters.except(*WebServerSimple::PARAMS).empty?)
            server.mount(uri.path, Faspex4GWServlet, @api_v5, nil)
            server.start
            return Main.result_status('Gateway terminated')
          when :postprocessing
            require 'aspera/faspex_postproc' # cspell:disable-line
            parameters = value_create_modify(command: command, default: {}).symbolize_keys
            uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
            parameters[:root] = uri.path
            server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
            server.mount(uri.path, Faspex4PostProcServlet, parameters.except(*WebServerSimple::PARAMS))
            server.start
            return Main.result_status('Gateway terminated')
          end
        end
        SHARED_INBOX_MEMBER_LEVELS = %i[submit_only standard shared_inbox_admin].freeze
        private_constant :SHARED_INBOX_MEMBER_LEVELS
      end
    end
  end
end
