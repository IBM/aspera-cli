# frozen_string_literal: true

# spellchecker: ignore workgroups mypackages passcode

require 'aspera/cli/plugins/oauth'
require 'aspera/cli/extended_value'
require 'aspera/transfer/result'
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
        application_name 'Faspex v5'

        class << self
          # @return [Hash,NilClass]
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
              response = api.read(Api::Faspex::PATH_API_DETECT, ret: :resp)
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
        # @param app_url [String] Tested URL
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
              url:         app_url,
              username:    wiz_username,
              auth:        :jwt.to_s,
              private_key: "@file:#{private_key_path}",
              params:      {
                client_id:     client_id,
                client_secret: client_secret
              }
            },
            test_args:    'user profile show'
          }
        end

        option :box,           description: "Package inbox, either shared inbox name or one of: #{Api::Faspex::API_LIST_MAILBOX_TYPES.join(', ')} or #{SpecialValues::ALL}", default: 'inbox_all'
        option :shared_folder, description: 'Send package with files from shared folder'
        option :group_type,    description: 'Type of shared box', allowed: %i[shared_inboxes workgroups], default: :shared_inboxes

        def initialize(**_)
          super
          options.parse_options!
          # [Aspera::Api::Faspex]
          @api_v5 = nil
        end

        # if recipient is just an email, then convert to expected API hash : name and type
        def normalize_recipients(parameters, type)
          type = type.to_s
          return unless parameters.key?(type)
          Aspera.assert_type(parameters[type], Array){type}
          recipient_types = Api::Faspex::RECIPIENT_TYPES
          if parameters.key?('recipient_types')
            recipient_types = parameters['recipient_types']
            parameters.delete('recipient_types')
            recipient_types = [recipient_types] unless recipient_types.is_a?(Array)
          end
          parameters[type].map! do |recipient_data|
            # If just a string, make a general lookup and build expected name/type hash
            if recipient_data.is_a?(String)
              matched = @api_v5.lookup_with_q('contacts', value: recipient_data, query: Rest.php_style({context: 'packages', type: recipient_types}))
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
              progress_bar&.event(:sessions_init, session_id: nil, info: status['upload_status'])
            elsif !total_sent
              progress_bar&.event(:session_start, session_id: id)
              progress_bar&.event(:session_size, session_id: id, info: status['bytes_total'].to_i)
              total_sent = true
            else
              progress_bar&.event(:transfer, session_id: id, info: status['bytes_written'].to_i)
            end
            if status_list.include?(status['upload_status'])
              progress_bar&.event(:session_end, session_id: id)
              progress_bar&.event(:end)
              return status
            end
            sleep(1.0)
          end
        end

        # @param job_id [String] job identifier
        # @return [Hash] result of API call for job status
        def wait_for_job(job_id)
          result = nil
          loop do
            result = @api_v5.read("jobs/#{job_id}", {type: :formatted})
            break unless Api::Faspex::JOB_RUNNING.include?(result['status'])
            RestParameters.instance.spinner_cb.call(result['status'])
            sleep(0.5)
          end
          RestParameters.instance.spinner_cb.call(action: :success)
          return result
        end

        # list all packages with optional filter
        def list_packages_with_filter(query: {})
          filter = options.get_next_argument('filter', mandatory: false, validation: Proc, default: ->(_x){true})
          box = options.get_option(:box)
          # Translate box name to API prefix (with ending slash)
          entity =
            case box
            when SpecialValues::ALL then 'packages' # only admin can list all packages globally
            when *Api::Faspex::API_LIST_MAILBOX_TYPES then "#{box}/packages"
            else
              group_type = options.get_option(:group_type)
              "#{group_type}/#{@api_v5.lookup_entity_by_field(entity: group_type, value: box)['id']}/packages"
            end
          list, total = @api_v5.list_entities_limit_offset_total_count(entity: entity, query: query_read_delete(default: query))
          return list.select(&filter), total
        end

        # Build query to get package recipients based on package info in case of shared inbox or workgroup recipient
        # @param package_id [String] the package id to get info from
        def recipient_query(package_id)
          package_info = @api_v5.read("packages/#{package_id}")
          base_query = {}
          base_query['recipient_workgroup_id'] = package_info['recipients'].first['id'] if WORKGROUP_TYPES.include?(package_info['recipients'].first['recipient_type'])
          base_query['recipient_user_id'] = package_info['recipients'].first['id'] if package_info['recipients'].first['recipient_type'].eql?('user')
          base_query
        end

        def package_receive(package_ids)
          # prepare persistency if needed
          skip_ids_persistency = nil
          if options.get_option(:once_only, mandatory: true)
            # read ids from persistency
            skip_ids_persistency = PersistencyActionOnce.new(
              manager: persistency,
              data:    [],
              id:      IdGenerator.from_list(
                'faspex_recv',
                options.get_option(:url, mandatory: true),
                options.get_option(:username, mandatory: true),
                options.get_option(:box, mandatory: true)
              )
            )
          end
          packages = []
          case package_ids
          when SpecialValues::INIT
            Aspera.assert(skip_ids_persistency, 'Only with option once_only')
            skip_ids_persistency.data.clear.concat(list_packages_with_filter.first.map{ |p| p['id']})
            skip_ids_persistency.save
            return Result::Status.new("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
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
            Aspera.assert_array_all(package_ids, String){'Package id(s)'}
            # packages = package_ids.map{|pkg_id|@api_v5.read("packages/#{pkg_id}")}
            packages = package_ids.map{ |pkg_id| {'id'=>pkg_id}}
          end
          result_transfer = []
          param_file_list = {}
          begin
            param_file_list['paths'] = transfer.ts_source_paths
          rescue Cli::MissingArgument
            # paths is optional
          end
          box = options.get_option(:box)
          download_params = {
            type:          Api::Faspex.box_type(box),
            transfer_type: Api::Faspex::TRANSFER_CONNECT
          }
          # download_params[:recipient_workgroup_id] = @api_v5.lookup_entity_by_field(entity: options.get_option(:group_type), value: box)['id'] if !Api::Faspex::API_LIST_MAILBOX_TYPES.include?(box) && box != SpecialValues::ALL
          packages.each do |package|
            pkg_id = package['id']
            formatter.display_status("Receiving package #{pkg_id}")
            # TODO: allow from sent as well ?
            transfer_spec = @api_v5.call(
              operation:    'POST',
              subpath:      "packages/#{pkg_id}/transfer_spec/download",
              query:        download_params.merge(recipient_query(pkg_id)),
              content_type: Mime::JSON,
              body:         param_file_list,
              headers:      {'Accept' => Mime::JSON}
            )
            # delete flag for Connect Client
            transfer_spec.delete('authentication')
            statuses = transfer.start(transfer_spec)
            result_transfer.push({'package' => pkg_id, Runner::STATUS_FIELD => statuses})
            # skip only if all sessions completed
            if statuses.is_a?(Transfer::Result::Success) && skip_ids_persistency
              skip_ids_persistency.data.push(pkg_id)
              skip_ids_persistency.save
            end
          end
          return Runner.result_transfer_multiple(result_transfer)
        end

        def package_send(parameters)
          # autofill recipient for public url
          if @api_v5.pub_link_context&.key?('recipient_type') && !parameters.key?('recipients')
            parameters['recipients'] = [{
              name:           @api_v5.pub_link_context['name'],
              recipient_type: @api_v5.pub_link_context['recipient_type']
            }]
          end
          PACKAGE_RECIPIENT_TYPES.each{ |type| normalize_recipients(parameters, type)}
          # User specified content prot in tspec, but faspex requires in package creation
          # `transfer_spec/upload` will set `content_protection`
          if transfer.user_transfer_spec['content_protection'] && !parameters.key?('ear_enabled')
            transfer.user_transfer_spec.delete('content_protection')
            parameters['ear_enabled'] = true
          end
          package = @api_v5.create('packages', parameters)
          shared_folder = options.get_option(:shared_folder)
          if shared_folder.nil?
            # send from local files
            transfer_spec = @api_v5.create(
              "packages/#{package['id']}/transfer_spec/upload",
              {paths: transfer.source_list},
              query: {transfer_type: Api::Faspex::TRANSFER_CONNECT}
            )
            # well, we asked a TS for connect, but we actually want a generic one
            transfer_spec.delete('authentication')
            return Runner.result_transfer(transfer.start(transfer_spec))
          else
            # send from remote shared folder
            if (m = Parser.percent_selector(shared_folder))
              shared_folder = @api_v5.lookup_entity_by_field(
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
            return Result::SingleObject.new(result)
          end
        end

        # Browse a folder
        # @param browse_endpoint [String] the endpoint to browse
        # @param folder_path     [String] starting path (default: '/')
        def browse_folder(browse_endpoint, base_query = {}, folder_path: '/')
          folders_to_process = [folder_path]
          query = base_query.merge(query_read_delete(default: {}))
          filters = query.delete('filters'){{}}
          Aspera.assert_type(filters, Hash)
          filters['basenames'] ||= []
          Aspera.assert_type(filters, Hash){'filters'}
          max_items = query.delete(RestList::MAX_ITEMS)
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
              data, http = @api_v5.call(
                operation:    'POST',
                subpath:      browse_endpoint,
                query:        query,
                content_type: Mime::JSON,
                body:         {'path' => path, 'filters' => filters},
                headers:      {'Accept' => Mime::JSON},
                ret:          :both
              )
              all_items.concat(data['items'])
              if !max_items.nil? && (all_items.count >= max_items)
                all_items = all_items.slice(0, max_items) if all_items.count > max_items
                break
              end
              folders_to_process.concat(data['items'].select{ |i| i['type'].eql?('directory')}.map{ |i| i['path']}) if recursive
              if use_paging
                iteration_token = http[Api::Faspex::HEADER_X_NEXT_ITER_TOKEN]
                break if iteration_token.nil? || iteration_token.empty?
                query['iteration_token'] = iteration_token
              else
                total_count = data['total_count'] if total_count.nil?
                break if data['item_count'].eql?(0)
                query['offset'] += data['item_count']
              end
              RestParameters.instance.spinner_cb.call(all_items.count)
            end
            query.delete('iteration_token')
          end
          RestParameters.instance.spinner_cb.call(action: :success)
          return Result::ObjectList.new(all_items, total: total_count)
        end

        # Per-resource configuration for admin CRUD sub-trees.
        # Keys mirror entity_execute kwargs; extra_commands lists additional leaf commands.
        # @return [Hash{Symbol => Hash}]
        RESOURCE_CONFIG = {
          accounts:            {
            display_fields:        ->{Formatter.all_but('user_profile_data_attributes')},
            extra_commands:        [:reset_password],
            instance_arg_commands: {reset_password: {arguments: [{name: :contact_id, type: :identifier, lookup: :lookup_accounts_id}]}}
          },
          alternate_addresses: {entity: 'configuration/alternate_addresses'},
          distribution_lists:  {entity: 'account/distribution_lists', delete_style: 'ids'},
          email_notifications: {id_as_arg: 'type'},
          file_processing:     {
            commands:     %i[next modify],
            schema:       ->{Schema::Registry.req_body(Schema::Registry::FASPEX, 'file_processing.put')},
            is_singleton: true
          },
          jobs:                {display_fields: %w[id job_name job_type status]},
          metadata_profiles:   {entity: 'configuration/metadata_profiles', items_key: 'profiles'},
          nodes:               {
            extra_commands:        %i[browse],
            instance_arg_commands: {
              browse: {
                arguments: [{name: :node_id, type: :identifier, lookup: :lookup_node_id},
                            {name: :folder_path, type: String, mandatory: false, default: '/'}]
              }
            }
          },
          oauth_clients:       {
            display_fields: ->{Formatter.all_but('public_key')},
            api:            ->{Api::Faspex.new(root: Api::Faspex::PATH_AUTH, **Oauth.kwargs_from_options(options))},
            list_query:     {'expand': true, 'no_api_path': true, 'client_types[]': 'public'}
          },
          shared_inboxes:      {res_id_query: {'all': true}},
          workgroups:          {res_id_query: {'all': true}}
        }.freeze
        private_constant :RESOURCE_CONFIG

        # Resolve a RESOURCE_CONFIG value that may be a Proc (evaluated in instance context).
        def resource_config_value(cfg, key)
          v = cfg[key]
          v.is_a?(Proc) ? instance_exec(&v) : v
        end

        # Build exec_args hash for entity_execute from RESOURCE_CONFIG for the given resource.
        def res_exec_args(res_sym)
          cfg = RESOURCE_CONFIG.fetch(res_sym, {})
          {
            api:            resource_config_value(cfg, :api) || @api_v5,
            entity:         resource_config_value(cfg, :entity) || res_sym.to_s,
            items_key:      resource_config_value(cfg, :items_key),
            delete_style:   resource_config_value(cfg, :delete_style),
            id_as_arg:      resource_config_value(cfg, :id_as_arg) || false,
            display_fields: resource_config_value(cfg, :display_fields),
            list_query:     resource_config_value(cfg, :list_query),
            is_singleton:   resource_config_value(cfg, :is_singleton) || false,
            schema:         resource_config_value(cfg, :schema)
          }.compact
        end

        # Lookup methods for arguments: + lookup: on specific nodes

        # admin > nodes — lookup node id by field/value
        def lookup_node_id(field, value, **)
          @api_v5.lookup_entity_by_field(entity: 'nodes', field: field, value: value)['id']
        end

        # admin > shared_inboxes — lookup id by field/value
        def lookup_shared_inboxes_id(field, value, **)
          @api_v5.lookup_entity_by_field(entity: 'shared_inboxes', field: field, value: value, query: {'all': true})['id']
        end

        # admin > workgroups — lookup id by field/value
        def lookup_workgroups_id(field, value, **)
          @api_v5.lookup_entity_by_field(entity: 'workgroups', field: field, value: value, query: {'all': true})['id']
        end

        # admin > accounts — lookup id by field/value (used for reset_password arguments:)
        def lookup_accounts_id(field, value, **)
          res_lookup_id(:accounts, field, value)
        end

        # Lookup id for a RESOURCE_CONFIG resource by field/value.
        def res_lookup_id(res_sym, field, value)
          cfg = RESOURCE_CONFIG.fetch(res_sym, {})
          entity      = resource_config_value(cfg, :entity) || res_sym.to_s
          items_key   = resource_config_value(cfg, :items_key)
          res_id_query = resource_config_value(cfg, :res_id_query) || :default
          @api_v5.lookup_entity_by_field(entity: entity, value: value, field: field, items_key: items_key, query: res_id_query)['id']
        end

        # --- DSL ---

        # Commands that need @api_v5 carry setup: :setup_api_v5.
        # :health and :postprocessing work without authentication, so they have no setup.
        command :health,         description: 'Check Faspex 5 health'
        command :version,        description: 'Show Faspex 5 version',             setup: :setup_api_v5, action: ->{Result::SingleObject.new(@api_v5.read('version'))}
        command :bearer_token,   description: 'Show OAuth bearer token',           setup: :setup_api_v5, action: ->{Result::Text.new(@api_v5.oauth.authorization)}
        command :packages, description: 'Manage packages', setup: :setup_api_v5
        commands_under(:packages) do
          command :list,   description: 'List packages'
          command :send,   description: 'Send a package',
            arguments: [{name: :data, type: Hash, schema: Schema::Registry.req_body(Schema::Registry::FASPEX, 'packages.post')}],
            action: ->(data:, **){package_send(data)}
          command :show,   description: 'Show a package', setup: :setup_package_id,
            action: ->(package_id:, **){Result::SingleObject.new(@api_v5.read("packages/#{package_id}"))}
          command :browse, description: 'Browse package files', setup: :setup_package_id,
            arguments: [{name: :folder_path, type: String, mandatory: false, default: '/'}],
            action: ->(folder_path:, package_id:, **){browse_folder("packages/#{package_id}/files/#{Api::Faspex.box_type(options.get_option(:box))}", recipient_query(package_id), folder_path: folder_path)}
          command(
            :status, description: 'Wait for package status', setup: :setup_package_id,
            arguments: [{name: :status_list, type: Array, mandatory: false, default: nil}],
            action: ->(status_list:, package_id:, **){Result::SingleObject.new(wait_package_status(package_id, status_list: status_list))}
          )
          command :delete, description: 'Delete package(s)', setup: :setup_package_id
          command :receive, description: 'Receive a package', setup: :setup_package_id, action: ->(package_id:, **){package_receive(package_id)}
          command(:file_processing, description: 'Show file processing status', setup: :setup_package_id, action: lambda do |package_id:, **|
            result, count = @api_v5.list_entities_limit_offset_total_count(entity: "packages/#{package_id}/file_statuses", items_key: 'files')
            Result::ObjectList.new(result, total: count)
          end)
        end
        command :admin,          description: 'Administer Faspex 5',               setup: :setup_api_v5
        command :user,           description: 'Manage current user',               setup: :setup_api_v5
        command :shared_folders, description: 'Browse shared folders',             setup: :setup_api_v5
        command :gateway,        description: 'Start Faspex 4 gateway emulation',  setup: :setup_api_v5,
          arguments: [{name: :parameters, type: Hash, mandatory: false, default: {}}]
        command :postprocessing, description: 'Start Faspex 4 post-processing server',
          arguments: [{name: :parameters, type: Hash, mandatory: false, default: {}}]
        command :invitations,    description: 'Manage invitations', setup: :setup_api_v5

        commands_under(:invitations) do
          command :create, description: 'Create an invitation',
            arguments: [{name: :input_data, type: Hash, bulk: true}]
          command :resend, description: 'Resend an invitation',
            arguments: [{name: :invitation_id, type: :identifier}]
          Operations::ALL.reject{ |op| op == :create}.each do |op|
            command(op, description: "#{op.capitalize} invitation(s)")
          end
        end

        commands_under(:user) do
          command :account, description: 'Show account information', action: ->{Result::SingleObject.new(@api_v5.read('account', query_read_delete))}
          command :profile, description: 'Manage user profile'
        end

        commands_under(%i[user profile]) do
          command :show, description: 'Show user profile', action: ->{Result::SingleObject.new(@api_v5.read('account/preferences'))}
          command(
            :modify, description: 'Modify user profile',
            arguments: [{name: :properties, type: Hash}],
            action: lambda do |properties:, **|
              @api_v5.update('account/preferences', properties)
              Result::Status.new('modified')
            end
          )
        end

        commands_under(:shared_folders) do
          command :list,   description: 'List shared folders', action: ->{Result::ObjectList.new(@api_v5.read('shared_folders')['shared_folders'])}
          command :browse, description: 'Browse a shared folder',
            arguments: [{name: :shared_folder_id, type: :identifier, lookup: :lookup_shared_folder_id},
                        {name: :folder_path, type: String, mandatory: false, default: '/'}]
        end

        # admin sub-tree: fixed commands + all ADMIN_RESOURCES with their sub-commands
        commands_under(:admin) do
          command :configuration, description: 'Manage Faspex 5 configuration'
          command :smtp,          description: 'Manage SMTP configuration'
          command :events,        description: 'List events'
          command :clean_deleted, description: 'Clean deleted packages',
            arguments: [{name: :input_data, type: Hash, mandatory: false, default: {}}]
          Api::Faspex::ADMIN_RESOURCES.each do |res|
            cfg          = RESOURCE_CONFIG.fetch(res, {})
            extra        = cfg[:extra_commands] || []
            cmds         = cfg[:commands] || (Operations::ALL + extra)
            ia_cmds      = cfg[:instance_arg_commands] || {}
            is_singleton = cfg[:is_singleton] || false
            schema_val   = cfg[:schema]
            command(res, description: "Manage #{res.to_s.tr('_', ' ')}")
            commands_under([:admin, res]) do
              cmds.each do |c|
                ia = ia_cmds[c] || {}
                extra_args =
                  if !is_singleton && c.eql?(:create)
                    [{name: :input_data, type: Hash, bulk: true, schema: schema_val}]
                  elsif c.eql?(:modify)
                    [{name: :input_data, type: Hash, schema: schema_val}]
                  else
                    []
                  end
                # Merge arguments: from ia (e.g. identifier spec) with extra_args for this operation
                merged_args = Array(ia[:arguments]) + extra_args
                spec_kwargs = merged_args.empty? ? ia.except(:arguments) : ia.except(:arguments).merge(arguments: merged_args)
                command(c, description: c.to_s.tr('_', ' ').capitalize, **spec_kwargs)
              end
            end
          end
        end

        commands_under(%i[admin nodes]) do
          command :shared_folders, description: 'Manage shared folders',
            arguments: [{name: :node_id, type: :identifier, lookup: :lookup_node_id}],
            setup: :setup_admin_nodes_shared_folders
        end

        # admin > nodes > shared_folders sub-tree
        commands_under(%i[admin nodes shared_folders]) do
          Operations::ALL.each{ |c| command(c, description: c.to_s.tr('_', ' ').capitalize)}
          command :user, description: 'Custom access users',
            arguments: [{name: :sf_id, type: :identifier, lookup: :lookup_sf_id}],
            setup: :setup_admin_nodes_shared_folders_user
        end

        # admin > nodes > shared_folders > user sub-tree (custom access users)
        commands_under(%i[admin nodes shared_folders user]) do
          Operations::ALL.each{ |c| command(c, description: c.to_s.tr('_', ' ').capitalize)}
        end

        MEMBER_SUBS = %i[members saml_groups].freeze
        CRUD_NO_SHOW = %i[create list modify delete].freeze
        CRUD_NO_LIST = %i[create modify delete show].freeze

        # admin > shared_inboxes|workgroups > members|saml_groups|invite_external_collaborator:
        # res_id consumed via arguments:(:identifier) + lookup:, builds res_instance_path for all children
        %i[shared_inboxes workgroups].each do |res|
          MEMBER_SUBS.each do |sub|
            commands_under([:admin, res]) do
              command sub, description: sub.to_s.tr('_', ' ').capitalize,
                arguments: [{name: :res_id, type: :identifier, lookup: :"lookup_#{res}_id"}],
                setup: :"setup_admin_#{res}_instance"
            end
            commands_under([:admin, res, sub]) do
              CRUD_NO_SHOW.each do |c|
                args = if c.eql?(:create) && sub.eql?(:members)
                  {arguments: [{name: :users, bulk: true}, {name: :access, mandatory: false, default: :standard}]}
                else
                  {}
                end
                command(c, description: c.to_s.capitalize, **args)
              end
            end
          end
          commands_under([:admin, res]) do
            command :invite_external_collaborator, description: 'Invite external collaborator',
              arguments: [{name: :res_id, type: :identifier, lookup: :"lookup_#{res}_id"},
                          {name: :input_data, type: Hash}]
          end
        end

        commands_under(%i[admin configuration]) do
          command :show, description: 'Show configuration', action: ->{Result::SingleObject.new(@api_v5.read('configuration'))}
          command(
            :modify, description: 'Modify configuration',
            arguments: [{name: :input_data, type: Hash}],
            action: ->(input_data:, **){Result::SingleObject.new(@api_v5.update('configuration', input_data))}
          )
        end

        commands_under(%i[admin smtp]) do
          command :show, description: 'Show SMTP configuration', action: ->{Result::SingleObject.new(@api_v5.read('configuration/smtp'))}
          command(
            :create, description: 'Create SMTP configuration',
            arguments: [{name: :input_data, type: Hash}],
            action: ->(input_data:, **){Result::SingleObject.new(@api_v5.create('configuration/smtp', input_data))}
          )
          command(
            :modify, description: 'Modify SMTP configuration',
            arguments: [{name: :input_data, type: Hash}],
            action: ->(input_data:, **){Result::SingleObject.new(@api_v5.update('configuration/smtp', input_data))}
          )
          command(:delete, description: 'Delete SMTP configuration', action: lambda do
            @api_v5.delete('configuration/smtp')
            Result::Status.new('SMTP configuration deleted')
          end)
          command :test, description: 'Test SMTP configuration',
            arguments: [{name: :test_data, type: nil}]
        end

        commands_under(%i[admin events]) do
          command(:application, description: 'List application events', action: lambda do
            list, total = @api_v5.list_entities_limit_offset_total_count(entity: 'application_events', query: query_read_delete)
            Result::ObjectList.new(list, total: total, fields: %w[event_type created_at application user.name])
          end)
          command(:webhook, description: 'List webhook events', action: lambda do
            list, total = @api_v5.list_entities_limit_offset_total_count(entity: 'all_webhooks_events', query: query_read_delete, items_key: 'events')
            Result::ObjectList.new(list, total: total)
          end)
        end

        # admin > clean_deleted handler (leaf, no sub-commands)
        define_action_method(%i[admin clean_deleted]) do |input_data: {}, **|
          input_data = @api_v5.read('configuration').slice('days_before_deleting_package_records') if input_data.empty?
          Result::SingleObject.new(@api_v5.create('internal/packages/clean_deleted', input_data))
        end

        # admin > <resource> > list
        Api::Faspex::ADMIN_RESOURCES.each do |res|
          define_action_method([:admin, res, :list]) do
            args = res_exec_args(res)
            # Special case: email_notifications list returns a fixed value list
            next Result::ValueList.new(Api::Faspex::EMAIL_NOTIF_LIST, name: 'email_id') if res.eql?(:email_notifications)
            data, total = args[:api].list_entities_limit_offset_total_count(
              entity: args[:entity], items_key: args[:items_key], query: query_read_delete(default: args[:list_query])
            )
            Result::ObjectList.new(data, total: total, fields: args[:display_fields])
          end
        end

        # admin > <resource> > create / modify / delete / show
        Api::Faspex::ADMIN_RESOURCES.each do |res|
          CRUD_NO_LIST.each do |op|
            define_action_method([:admin, res, op]) do |input_data: nil, res_id: nil, **|
              args = res_exec_args(res)
              is_bulk = options.get_option(:bulk)
              items = input_data
              items = [items] if items && !items.is_a?(Array)
              entity_execute(command: op, input_data: items, res_id: res_id, is_bulk: is_bulk, bfail: options.get_option(:bfail), **args){ |f, v| res_lookup_id(res, f, v)}
            end
          end
        end

        def action_admin_smtp_test(test_data:, **)
          test_data = {test_email_recipient: test_data} if test_data.is_a?(String)
          creation = @api_v5.create('configuration/smtp/test', test_data)
          result = wait_for_job(creation['job_id'])
          begin
            result['serialized_args'] = JSON.parse(result['serialized_args'])
          rescue JSON::ParserError
            # keep as string if not valid JSON
          end
          Result::SingleObject.new(result)
        end

        # admin > accounts > reset_password
        def action_admin_accounts_reset_password(contact_id:, **)
          @api_v5.create("accounts/#{contact_id}/reset_password", {})
          Result::Status.new('password reset, user shall check email')
        end

        # admin > file_processing > next
        def action_admin_file_processing_next
          args = res_exec_args(:file_processing)
          result, count = @api_v5.list_entities_limit_offset_total_count(entity: args[:entity], operation: 'POST', items_key: 'files')
          Result::ObjectList.new(result, total: count)
        end

        # admin > nodes > browse
        def action_admin_nodes_browse(folder_path:, node_id:, **)
          browse_folder("nodes/#{node_id}/browse", {}, folder_path: folder_path)
        end

        # admin > nodes > shared_folders — node_id: already in ctx via arguments: on the :shared_folders command
        def setup_admin_nodes_shared_folders(node_id:, **)
          {sf_entity: "nodes/#{node_id}/shared_folders"}
        end

        # Lookup shared folder id by field/value within a node's shared_folders entity.
        # Used as lookup: on the :user command under admin > nodes > shared_folders.
        # sf_entity is available in ctx because setup_admin_nodes_shared_folders ran first (Phase A of parent).
        def lookup_sf_id(field, value, sf_entity:, **)
          @api_v5.lookup_entity_by_field(entity: sf_entity, items_key: 'shared_folders', field: field, value: value)['id']
        end

        # admin > nodes > shared_folders > create/modify/delete/show/list
        Operations::ALL.each do |op|
          define_action_method([:admin, :nodes, :shared_folders, op]) do |sf_entity:, **|
            entity_execute(api: @api_v5, entity: sf_entity, items_key: 'shared_folders', command: op){ |f, v| @api_v5.lookup_entity_by_field(entity: sf_entity, items_key: 'shared_folders', field: f, value: v)['id']}
          end
        end

        # admin > nodes > shared_folders > user — sf_id: already in ctx via arguments: on the :user command
        def setup_admin_nodes_shared_folders_user(sf_entity:, sf_id:, **)
          {user_path: "#{sf_entity}/#{sf_id}/custom_access_users"}
        end

        # admin > nodes > shared_folders > user > create/modify/delete/show/list (custom access users)
        Operations::ALL.each do |op|
          define_action_method([:admin, :nodes, :shared_folders, :user, op]) do |user_path:, **|
            entity_execute(api: @api_v5, entity: user_path, items_key: 'users', command: op){ |f, v| @api_v5.lookup_entity_by_field(entity: user_path, items_key: 'users', field: f, value: v)['id']}
          end
        end

        # admin > shared_inboxes|workgroups — res_id: already in ctx via arguments: on the :members|:saml_groups command
        %i[shared_inboxes workgroups].each do |res|
          define_method(:"setup_admin_#{res}_instance") do |res_id:, **|
            {res_instance_path: "#{res}/#{res_id}"}
          end
        end

        # Resolve user ids for shared_inbox/workgroup members/create, handling percent selectors.
        # @param users [Array] raw user ids or percent-selector strings
        # @return [Array<String>] resolved user ids
        def resolve_member_user_ids(users)
          users = [users] unless users.is_a?(Array)
          users.map do |user|
            if (m = Parser.percent_selector(user))
              @api_v5.lookup_entity_by_field(entity: 'accounts', field: m[:field], value: m[:value], query: Rest.php_style({type: ACCOUNT_TYPES}))['id']
            else
              user
            end
          end
        end

        # admin > shared_inboxes|workgroups > members|saml_groups > create/list/modify/delete
        %i[shared_inboxes workgroups].each do |res|
          MEMBER_SUBS.each do |sub|
            CRUD_NO_SHOW.each do |op|
              if op.eql?(:create) && sub.eql?(:members)
                define_action_method([:admin, res, sub, op]) do |users:, access:, res_instance_path:, **|
                  res_path = "#{res_instance_path}/#{sub}"
                  list_key = sub.eql?(:saml_groups) ? 'groups' : sub.to_s
                  resolved = resolve_member_user_ids(users)
                  input_data = [{user: resolved.map{ |u| {id: u, access: access}}}]
                  entity_execute(api: @api_v5, entity: res_path, command: op, input_data: input_data, items_key: list_key) do |f, v|
                    @api_v5.lookup_entity_by_field(entity: res_path, field: f, value: v, query: Rest.php_style({type: %w[user]}))['user_id']
                  end
                end
              else
                define_action_method([:admin, res, sub, op]) do |res_instance_path:, **|
                  res_path = "#{res_instance_path}/#{sub}"
                  list_key = sub.eql?(:saml_groups) ? 'groups' : sub.to_s
                  entity_execute(api: @api_v5, entity: res_path, command: op, items_key: list_key) do |f, v|
                    @api_v5.lookup_entity_by_field(entity: res_path, field: f, value: v, query: Rest.php_style({type: %w[user]}))['user_id']
                  end
                end
              end
            end
          end
        end

        # admin > shared_inboxes|workgroups > invite_external_collaborator
        %i[shared_inboxes workgroups].each do |res|
          define_action_method([:admin, res, :invite_external_collaborator]) do |input_data:, res_id:, **|
            res_instance_path = "#{res}/#{res_id}"
            result = @api_v5.create("#{res_instance_path}/external_collaborator", input_data)
            formatter.display_status(result['message'])
            Result::SingleObject.new(@api_v5.lookup_entity_by_field(entity: "#{res_instance_path}/members", items_key: 'members', value: input_data['email_address'], query: {}))
          end
        end

        # --- root setup ---

        # Build @api_v5 for all commands that need it (all except :health and :postprocessing).
        # @return [Hash] empty ctx (state stored in @api_v5)
        def setup_api_v5(**)
          return {} if @api_v5
          @api_v5 = Api::Faspex.new(**Oauth.kwargs_from_options(options))
          # in case user wants to use HTTPGW tell transfer agent how to get address
          transfer.httpgw_url_cb = lambda{@api_v5.read('account')['gateway_url']}
          {}
        end

        # Setup for package sub-commands that need an id: resolves package_id from pub_link or argument.
        # @return [Hash] ctx key: package_id
        def setup_package_id(**)
          package_id = @api_v5.pub_link_context&.key?('package_id') ? @api_v5.pub_link_context['package_id'] : options.instance_identifier
          {package_id: package_id}
        end

        def action_packages_list
          list, total = list_packages_with_filter
          fields = %w[id title status sender.name recipients.0.name release_date total_bytes total_files]
          fields.delete('recipients.0.name') if %w[inbox inbox_history].include?(options.get_option(:box))
          fields.delete('sender.name') if %w[outbox outbox_history].include?(options.get_option(:box))
          Result::ObjectList.new(list, total: total, fields: fields)
        end

        def action_packages_delete(package_id:, **)
          ids = package_id.is_a?(Array) ? package_id : [package_id]
          Aspera.assert_array_all(ids, String){'Package id(s)'}
          # API returns 204, empty on success
          @api_v5.call(
            operation:    'DELETE',
            subpath:      'packages',
            content_type: Mime::JSON,
            body:         {ids: ids},
            headers:      {'Accept' => Mime::JSON}
          )
          Result::Status.new('Package(s) deleted')
        end

        # --- handlers ---

        def action_health
          nagios = Nagios.new
          begin
            data, http = Rest.new(base_url: options.get_option(:url, mandatory: true))
              .read('health', ret: :both)
            data.each do |k, v|
              nagios.add_ok(k, v.to_s)
            end
            nagios.add_ok('version', http['X-IBM-Aspera']) if http['X-IBM-Aspera']
          rescue StandardError => e
            nagios.add_critical('core', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        # Lookup a shared folder id by field/value.
        # Called via lookup: :lookup_shared_folder_id on the shared_folders > browse command.
        def lookup_shared_folder_id(field, value, **)
          all = @api_v5.read('shared_folders')['shared_folders']
          matches = all.select{ |i| i[field].eql?(value)}
          Aspera.assert(!matches.empty?){"no match for #{field} = #{value}"}
          Aspera.assert(matches.length == 1){"multiple matches for #{field} = #{value}"}
          matches.first['id']
        end

        def action_shared_folders_browse(folder_path:, shared_folder_id:, **)
          all_shared_folders = @api_v5.read('shared_folders')['shared_folders']
          node = all_shared_folders.find{ |i| i['id'].eql?(shared_folder_id)}
          Aspera.assert(!node.nil?){"No such shared folder id #{shared_folder_id}"}
          browse_folder("nodes/#{node['node_id']}/shared_folders/#{shared_folder_id}/browse", {}, folder_path: folder_path)
        end

        # invitations sub-handlers

        def action_invitations_resend(invitation_id:, **)
          @api_v5.create("invitations/#{invitation_id}/resend", nil)
          Result::Status.new('Invitation resent')
        end

        def action_invitations_create(input_data:, **)
          is_bulk = options.get_option(:bulk)
          Result.bulk(input_data, is_bulk: is_bulk, command: :create, bfail: options.get_option(:bfail)) do |params|
            endpoint = params.key?('recipient_name') ? 'public_invitations' : 'invitations'
            @api_v5.create(endpoint, params)
          end
        end

        # CRUD handlers for invitations (list, show, modify, delete)
        Operations::ALL.reject{ |op| op == :create}.each do |op|
          define_action_method([:invitations, op]) do
            entity_execute(
              api: @api_v5,
              entity: 'invitations',
              command: op,
              items_key: 'invitations',
              display_fields: %w[id public recipient_type recipient_name email_address]
            ) do |field, value|
              @api_v5.lookup_entity_by_field(entity: 'invitations', field: field, value: value, query: {})['id']
            end
          end
        end

        def action_gateway(parameters: {}, **)
          require 'aspera/faspex_gw'
          parameters = parameters.symbolize_keys
          uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
          server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
          Aspera.assert(parameters.except(*WebServerSimple::PARAMS).empty?){"unexpected parameters: #{parameters.except(*WebServerSimple::PARAMS).keys}"}
          server.mount(uri.path, Faspex4GWServlet, @api_v5, nil)
          server.start
          Result::Status.new('Gateway terminated')
        end

        def action_postprocessing(parameters: {}, **)
          require 'aspera/faspex_postproc' # cspell:disable-line
          parameters = parameters.symbolize_keys
          uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
          parameters[:root] = uri.path
          server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
          server.mount(uri.path, Faspex4PostProcServlet, parameters.except(*WebServerSimple::PARAMS))
          server.start
          Result::Status.new('Gateway terminated')
        end
        SHARED_INBOX_MEMBER_LEVELS = %i[submit_only standard shared_inbox_admin].freeze
        ACCOUNT_TYPES = %w{local_user saml_user self_registered_user external_user}.freeze
        WORKGROUP_TYPES = %w{workgroup shared_inbox}.freeze
        CONTACT_TYPES = (WORKGROUP_TYPES + %w{distribution_list user external_user}).freeze
        PACKAGE_RECIPIENT_TYPES = %i{recipients private_recipients notified_on_upload notified_on_download notified_on_receipt}
        private_constant :SHARED_INBOX_MEMBER_LEVELS, :ACCOUNT_TYPES, :CONTACT_TYPES, :PACKAGE_RECIPIENT_TYPES,
          :MEMBER_SUBS, :CRUD_NO_SHOW, :CRUD_NO_LIST
      end
    end
  end
end
