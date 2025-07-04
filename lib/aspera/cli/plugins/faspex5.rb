# frozen_string_literal: true

# spellchecker: ignore workgroups mypackages passcode

require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/extended_value'
require 'aspera/cli/special_values'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/nagios'
require 'aspera/environment'
require 'aspera/assert'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      class Faspex5 < Cli::BasicAuthPlugin
        RECIPIENT_TYPES = %w[user workgroup external_user distribution_list shared_inbox].freeze
        PACKAGE_TERMINATED = %w[completed failed].freeze
        # list of supported mailbox types (to list packages)
        API_LIST_MAILBOX_TYPES = %w[inbox inbox_history inbox_all inbox_all_history outbox outbox_history pending pending_history all].freeze
        PACKAGE_SEND_FROM_REMOTE_SOURCE = 'remote_source'
        # Faspex API v5: get transfer spec for connect
        TRANSFER_CONNECT = 'connect'
        ADMIN_RESOURCES = %i[
          accounts distribution_lists contacts jobs workgroups shared_inboxes nodes oauth_clients registrations saml_configs
          metadata_profiles email_notifications alternate_addresses webhooks
        ].freeze
        # states for jobs not in final state
        JOB_RUNNING = %w[queued working].freeze
        PATH_STANDARD_ROOT = '/aspera/faspex'
        PATH_API_V5 = 'api/v5'
        # endpoint for authentication API
        PATH_AUTH = 'auth'
        PATH_HEALTH = 'configuration/ping'
        PATH_API_DETECT = "#{PATH_API_V5}/#{PATH_HEALTH}"
        PER_PAGE_DEFAULT = 100
        # OAuth methods supported
        STD_AUTH_TYPES = %i[web jwt boot].freeze
        HEADER_ITERATION_TOKEN = 'X-Aspera-Next-Iteration-Token'
        HEADER_FASPEX_VERSION = 'X-IBM-Aspera'
        private_constant(*%i[JOB_RUNNING RECIPIENT_TYPES PACKAGE_TERMINATED PATH_HEALTH API_LIST_MAILBOX_TYPES PACKAGE_SEND_FROM_REMOTE_SOURCE PER_PAGE_DEFAULT
                             STD_AUTH_TYPES HEADER_ITERATION_TOKEN HEADER_FASPEX_VERSION])
        class << self
          def application_name
            'Faspex'
          end

          def detect(address_or_url)
            # add scheme if missing
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{PATH_STANDARD_ROOT}") unless address_or_url.end_with?(PATH_STANDARD_ROOT)
            error = nil
            urls.each do |base_url|
              # Faspex is always HTTPS
              next unless base_url.start_with?('https://')
              api = Rest.new(base_url: base_url, redirect_max: 1)
              response = api.call(operation: 'GET', subpath: PATH_API_DETECT)[:http]
              next unless response.code.start_with?('2') && response.body.strip.empty?
              # end is at -1, and subtract 1 for "/"
              url_length = -2 - PATH_API_DETECT.length
              # take redirect if any
              return {
                version: response[HEADER_FASPEX_VERSION] || '5',
                url:     response.uri.to_s[0..url_length]
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return nil
          end

          # @param object [Plugin] An instance of this class
          # @param private_key_path [String] path to private key
          # @param pub_key_pem [String] PEM of public key
          # @return [Hash] :preset_value, :test_args
          def wizard(object:, private_key_path:, pub_key_pem:)
            options = object.options
            formatter = object.formatter
            instance_url = options.get_option(:url, mandatory: true)
            wiz_username = options.get_option(:username, mandatory: true)
            raise "Username shall be an email in Faspex: #{wiz_username}" if !(wiz_username =~ /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
            if options.get_option(:client_id).nil? || options.get_option(:client_secret).nil?
              formatter.display_status('Ask the ascli client id and secret to your Administrator.'.red)
              formatter.display_status("Admin should login to: #{instance_url}")
              Environment.instance.open_uri(instance_url)
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

          # @return true if the URL is a public link
          def public_link?(url)
            url.include?('?context=')
          end
        end

        def initialize(**env)
          super
          options.declare(:client_id, 'OAuth client identifier')
          options.declare(:client_secret, 'OAuth client secret')
          options.declare(:redirect_uri, 'OAuth redirect URI for web authentication')
          options.declare(:auth, 'OAuth type of authentication', values: STD_AUTH_TYPES, default: :jwt)
          options.declare(:private_key, 'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.declare(:passphrase, 'OAuth JWT RSA private key passphrase')
          options.declare(:box, "Package inbox, either shared inbox name or one of: #{API_LIST_MAILBOX_TYPES.join(', ')} or #{SpecialValues::ALL}", default: 'inbox')
          options.declare(:shared_folder, 'Send package with files from shared folder')
          options.declare(:group_type, 'Type of shared box', values: %i[shared_inboxes workgroups], default: :shared_inboxes)
          options.parse_options!
          @pub_link_context = nil
        end

        def set_api
          # get endpoint, remove unnecessary trailing slashes
          @faspex5_api_base_url = options.get_option(:url, mandatory: true).gsub(%r{/+$}, '')
          auth_type = self.class.public_link?(@faspex5_api_base_url) ? :public_link : options.get_option(:auth, mandatory: true)
          case auth_type
          when :public_link
            # resolve any redirect
            @faspex5_api_base_url = Rest.new(base_url: @faspex5_api_base_url, redirect_max: 3).call(operation: 'GET')[:http].uri.to_s
            encoded_context = Rest.query_to_h(URI.parse(@faspex5_api_base_url).query)['context']
            raise 'Bad faspex5 public link, missing context in query' if encoded_context.nil?
            # public link information (allowed usage)
            @pub_link_context = JSON.parse(Base64.decode64(encoded_context))
            Log.log.trace1{Log.dump(:@pub_link_context, @pub_link_context)}
            # ok, we have the additional parameters, get the base url
            @faspex5_api_base_url = @faspex5_api_base_url.gsub(%r{/public/.*}, '').gsub(/\?.*/, '')
            @api_v5 = Rest.new(
              base_url: "#{@faspex5_api_base_url}/#{PATH_API_V5}",
              headers:  {'Passcode' => @pub_link_context['passcode']}
            )
          when :boot
            # the password here is the token copied directly from browser in developer mode
            @api_v5 = Rest.new(
              base_url: "#{@faspex5_api_base_url}/#{PATH_API_V5}",
              headers:  {'Authorization' => options.get_option(:password, mandatory: true)}
            )
          when :web
            # opens a browser and ask user to auth using web
            @api_v5 = Rest.new(
              base_url: "#{@faspex5_api_base_url}/#{PATH_API_V5}",
              auth:     {
                type:         :oauth2,
                base_url:     "#{@faspex5_api_base_url}/#{PATH_AUTH}",
                grant_method: :web,
                client_id:    options.get_option(:client_id, mandatory: true),
                redirect_uri: options.get_option(:redirect_uri, mandatory: true)
              })
          when :jwt
            app_client_id = options.get_option(:client_id, mandatory: true)
            @api_v5 = Rest.new(
              base_url: "#{@faspex5_api_base_url}/#{PATH_API_V5}",
              auth:     {
                type:            :oauth2,
                grant_method:    :jwt,
                base_url:        "#{@faspex5_api_base_url}/#{PATH_AUTH}",
                client_id:       app_client_id,
                payload:         {
                  iss: app_client_id, # issuer
                  aud: app_client_id, # audience (this field is not clear...)
                  sub: "user:#{options.get_option(:username, mandatory: true)}" # subject is a user
                },
                private_key_obj: OpenSSL::PKey::RSA.new(options.get_option(:private_key, mandatory: true), options.get_option(:passphrase)),
                headers:         {typ: 'JWT'}
              })
          else Aspera.error_unexpected_value(auth_type)
          end
          # in case user wants to use HTTPGW tell transfer agent how to get address
          transfer.httpgw_url_cb = lambda{@api_v5.read('account')['gateway_url']}
        end

        # if recipient is just an email, then convert to expected API hash : name and type
        def normalize_recipients(parameters)
          return unless parameters.key?('recipients')
          Aspera.assert_type(parameters['recipients'], Array){'recipients'}
          recipient_types = RECIPIENT_TYPES
          if parameters.key?('recipient_types')
            recipient_types = parameters['recipient_types']
            parameters.delete('recipient_types')
            recipient_types = [recipient_types] unless recipient_types.is_a?(Array)
          end
          parameters['recipients'].map! do |recipient_data|
            # if just a string, make a general lookup and build expected name/type hash
            if recipient_data.is_a?(String)
              matched = @api_v5.lookup_by_name('contacts', recipient_data, query: {context: 'packages', type: Rest.array_params(recipient_types)})
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
            status = @api_v5.read("packages/#{id}/upload_details")
            status['id'] = id
            # user asked to not follow
            return status if status_list.nil?
            if status['upload_status'].eql?('submitted')
              config.progress_bar&.event(:pre_start, session_id: nil, info: status['upload_status'])
            elsif !total_sent
              config.progress_bar&.event(:session_start, session_id: id)
              config.progress_bar&.event(:session_size, session_id: id, info: status['bytes_total'].to_i)
              total_sent = true
            else
              config.progress_bar&.event(:transfer, session_id: id, info: status['bytes_written'].to_i)
            end
            if status_list.include?(status['upload_status'])
              config.progress_bar&.event(:end, session_id: id)
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
            break unless JOB_RUNNING.include?(result['status'])
            formatter.long_operation_running(result['status'])
            sleep(0.5)
          end
          formatter.long_operation_terminated
          return result
        end

        # Get a (full or partial) list of all entities of a given type with query: offset/limit
        # @param type [String] the type of entity to list (just a name)
        # @param query [Hash,nil] additional query parameters
        # @param real_path [String] real path if it's n ot just the type
        # @param item_list_key [String] key in the result to get the list of items
        def list_entities(type:, real_path: nil, item_list_key: nil, query: nil)
          Log.log.trace1{"list_entities t=#{type} p=#{real_path} k=#{item_list_key} q=#{query}"}
          type = type.to_s if type.is_a?(Symbol)
          query = {} if query.nil?
          Aspera.assert_type(type, String)
          Aspera.assert_type(query, Hash)
          item_list_key = type if item_list_key.nil?
          real_path = type if real_path.nil?
          result = []
          offset = 0
          max_items = query.delete(MAX_ITEMS)
          remain_pages = query.delete(MAX_PAGES)
          # merge default parameters, by default 100 per page
          query = {'limit'=> PER_PAGE_DEFAULT}.merge(query)
          loop do
            query['offset'] = offset
            page_result = @api_v5.read(real_path, query)
            Aspera.assert_type(page_result[item_list_key], Array)
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
            formatter.long_operation_running
          end
          formatter.long_operation_terminated
          return result
        end

        # lookup an entity id from its name
        # @param type [String] the type of entity to lookup, by default it is the path, and it is also the field name in result
        # @param value [String] the value to lookup
        # @param field [String] the field to match, by default it is 'name'
        # @param real_path [String] real path if it's not just the type (override type)
        # @param item_list_key [String] key in the result to get the list of items (override type)
        # @param query [Hash] additional query parameters
        def lookup_entity_by_field(type:, value:, field: 'name', real_path: nil, item_list_key: nil, query: :default)
          if query.eql?(:default)
            Aspera.assert(field.eql?('name')){'Default query is on name only'}
            query = {'q'=> value}
          end
          found = list_entities(type: type, real_path: real_path, query: query, item_list_key: item_list_key).select{ |i| i[field].eql?(value)}
          case found.length
          when 0 then raise "No #{type} with #{field} = #{value}"
          when 1 then return found.first
          else raise "Found #{found.length} #{real_path} with #{field} = #{value}"
          end
        end

        # list all packages with optional filter
        def list_packages_with_filter(query: {})
          filter = options.get_next_argument('filter', mandatory: false, validation: Proc, default: ->(_x){true})
          # translate box name to API prefix (with ending slash)
          box = options.get_option(:box)
          real_path =
            case box
            when SpecialValues::ALL then 'packages' # only admin can list all packages globally
            when *API_LIST_MAILBOX_TYPES then "#{box}/packages"
            else
              group_type = options.get_option(:group_type)
              "#{group_type}/#{lookup_entity_by_field(type: group_type, value: box)['id']}/packages"
            end
          return list_entities(
            type: 'packages',
            query:  query_read_delete(default: query),
            real_path: real_path).select(&filter)
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
              ]))
          end
          packages = []
          case package_ids
          when SpecialValues::INIT
            Aspera.assert(skip_ids_persistency){'Only with option once_only'}
            skip_ids_persistency.data.clear.concat(list_packages_with_filter.map{ |p| p['id']})
            skip_ids_persistency.save
            return Main.result_status("Initialized skip for #{skip_ids_persistency.data.count} package(s)")
          when SpecialValues::ALL
            # TODO: if packages have same name, they will overwrite ?
            packages = list_packages_with_filter(query: {'status' => 'completed'})
            Log.log.trace1{Log.dump(:package_ids, packages.map{ |p| p['id']})}
            Log.log.trace1{Log.dump(:skip_ids, skip_ids_persistency.data)}
            packages.reject!{ |p| skip_ids_persistency.data.include?(p['id'])} if skip_ids_persistency
            Log.log.trace1{Log.dump(:package_ids, packages.map{ |p| p['id']})}
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
              if recursive
                folders_to_process.concat(response[:data]['items'].select{ |i| i['type'].eql?('directory')}.map{ |i| i['path']})
              end
              if use_paging
                iteration_token = response[:http][HEADER_ITERATION_TOKEN]
                break if iteration_token.nil? || iteration_token.empty?
                query['iteration_token'] = iteration_token
              else
                if total_count.nil?
                  total_count = response[:data]['total_count']
                end
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
              @pub_link_context&.key?('package_id') ? @pub_link_context['package_id'] : instance_identifier
            end
          case command
          when :show
            return Main.result_single_object(@api_v5.read("packages/#{package_id}"))
          when :browse
            location = case options.get_option(:box)
            when 'inbox' then 'received'
            when 'outbox' then 'sent'
            else raise 'Browse only available for inbox and outbox'
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
            if @pub_link_context&.key?('recipient_type') && !parameters.key?('recipients')
              parameters['recipients'] = [{
                name:           @pub_link_context['name'],
                recipient_type: @pub_link_context['recipient_type']
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
                query:        {transfer_type: TRANSFER_CONNECT},
                content_type: Rest::MIME_JSON,
                body:         {paths: transfer.source_list},
                headers:      {'Accept' => Rest::MIME_JSON}
              )[:data]
              # well, we asked a TS for connect, but we actually want a generic one
              transfer_spec.delete('authentication')
              return Main.result_transfer(transfer.start(transfer_spec))
            else
              # send from remote shared folder
              if (m = shared_folder.match(REGEX_LOOKUP_ID_BY_FIELD))
                shared_folder = lookup_entity_by_field(
                  type: 'shared_folders',
                  field: m[1],
                  value: ExtendedValue.instance.evaluate(m[2]))['id']
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
            return {
              type:   :object_list,
              data:   list_packages_with_filter,
              fields: %w[id title release_date total_bytes total_files created_time state]
            }
          end
        end

        def execute_resource(res_type)
          list_key = res_path = res_type.to_s
          id_as_arg = false
          display_fields = nil
          adm_api = @api_v5
          res_id_query = :default
          delete_style = nil
          available_commands = [].concat(Plugin::ALL_OPS)
          case res_type
          when :metadata_profiles
            res_path = 'configuration/metadata_profiles'
            list_key = 'profiles'
          when :alternate_addresses
            res_path = 'configuration/alternate_addresses'
          when :distribution_lists
            res_path = 'account/distribution_lists'
            list_key = 'distribution_lists'
            delete_style = 'ids'
          when :email_notifications
            list_key = false
            id_as_arg = 'type'
          when :accounts
            display_fields = Formatter.all_but('user_profile_data_attributes')
            available_commands.push(:reset_password)
          when :oauth_clients
            display_fields = Formatter.all_but('public_key')
            adm_api = Rest.new(**@api_v5.params, base_url: "#{@faspex5_api_base_url}/#{PATH_AUTH}")
          when :shared_inboxes, :workgroups
            available_commands.push(:members, :saml_groups, :invite_external_collaborator)
            res_id_query = {'all': true}
          when :nodes
            available_commands.push(:shared_folders, :browse)
          end
          res_command = options.get_next_command(available_commands)
          case res_command
          when *Plugin::ALL_OPS
            return entity_command(
              res_command, adm_api, res_path, item_list_key: list_key, display_fields: display_fields, id_as_arg: id_as_arg,
              delete_style: delete_style) do |field, value|
                     lookup_entity_by_field(
                       type: res_type, value: value, field: field, real_path: res_path, item_list_key: list_key, query: res_id_query)['id']
                   end
          when :shared_folders
            node_id = instance_identifier do |field, value|
              lookup_entity_by_field(type: res_type, field: field, value: value)['id']
            end
            sh_path = "#{res_path}/#{node_id}/shared_folders"
            sh_command = options.get_next_command([:user].concat(Plugin::ALL_OPS))
            case sh_command
            when *Plugin::ALL_OPS
              return entity_command(sh_command, adm_api, sh_path, item_list_key: 'shared_folders') do |field, value|
                       lookup_entity_by_field(type: 'shared_folders', real_path: sh_path, field: field, value: value)['id']
                     end
            when :user
              sh_id = instance_identifier do |field, value|
                lookup_entity_by_field(type: 'shared_folders', real_path: sh_path, field: field, value: value)['id']
              end
              user_path = "#{sh_path}/#{sh_id}/custom_access_users"
              return entity_action(adm_api, user_path, item_list_key: 'users') do |field, value|
                       lookup_entity_by_field(type: 'users', real_path: user_path, field: field, value: value)['id']
                     end

            end
          when :browse
            node_id = instance_identifier do |field, value|
              lookup_entity_by_field(
                type: res_type, value: value, field: field, real_path: res_path, item_list_key: list_key, query: res_id_query)['id']
            end
            return browse_folder("#{res_path}/#{node_id}/browse")
          when :invite_external_collaborator
            shared_inbox_id = instance_identifier{ |field, value| lookup_entity_by_field(type: res_type.to_s, field: field, value: value, query: res_id_query)['id']}
            creation_payload = value_create_modify(command: res_command, type: [Hash, String])
            creation_payload = {'email_address' => creation_payload} if creation_payload.is_a?(String)
            res_path = "#{res_type}/#{shared_inbox_id}/external_collaborator"
            result = adm_api.create(res_path, creation_payload)
            formatter.display_status(result['message'])
            result = lookup_entity_by_field(
              type: 'members',
              real_path: "#{res_type}/#{shared_inbox_id}/members",
              value: creation_payload['email_address'],
              query: {})
            return Main.result_single_object(result)
          when :members, :saml_groups
            res_id = instance_identifier{ |field, value| lookup_entity_by_field(type: res_type.to_s, field: field, value: value, query: res_id_query)['id']}
            res_prefix = "#{res_type}/#{res_id}"
            res_path = "#{res_prefix}/#{res_command}"
            list_key = res_command.to_s
            list_key = 'groups' if res_command.eql?(:saml_groups)
            sub_command = options.get_next_command(%i[create list modify delete])
            if sub_command.eql?(:create) && res_command.eql?(:members)
              # first arg is one user name or list of users
              users = options.get_next_argument('user id, %name:, or Array')
              users = [users] unless users.is_a?(Array)
              users = users.map do |user|
                if (m = user.match(REGEX_LOOKUP_ID_BY_FIELD))
                  lookup_entity_by_field(
                    type: 'accounts',
                    field: m[1],
                    value: ExtendedValue.instance.evaluate(m[2]),
                    query: {type: Rest.array_params(%w{local_user saml_user self_registered_user external_user})})['id']
                else
                  # it's the user id (not member id...)
                  user
                end
              end
              access = options.get_next_argument('level', mandatory: false, accept_list: %i[submit_only standard shared_inbox_admin], default: :standard)
              options.unshift_next_argument({user: users.map{ |u| {id: u, access: access}}})
            end
            return entity_command(sub_command, adm_api, res_path, item_list_key: list_key) do |field, value|
                     lookup_entity_by_field(
                       type: 'accounts',
                       field: field,
                       value: value,
                       query: {type: Rest.array_params(%w{local_user saml_user self_registered_user external_user})})['id']
                   end
          when :reset_password
            contact_id = instance_identifier{ |field, value| lookup_entity_by_field(type: res_type.to_s, field: field, value: value, query: res_id_query)['id']}
            adm_api.create("#{res_type}/#{contact_id}/reset_password", {})
            return Main.result_status('password reset, user shall check email')
          end
          Aspera.error_unreachable_line
        end

        def execute_admin
          command = options.get_next_command(%i[configuration smtp resource events clean_deleted].concat(ADMIN_RESOURCES).freeze)
          case command
          when :resource
            # resource will be deprecated
            Log.log.warn('resource command is deprecated (4.18), directly use the specific command instead')
            return execute_resource(options.get_next_command(ADMIN_RESOURCES))
          when *ADMIN_RESOURCES
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
              return Main.result_object_list(
                list_entities(type: 'application_events', query: query_read_delete),
                fields: %w[event_type created_at application user.name])
            when :webhook
              return Main.result_object_list(
                list_entities(type: 'all_webhooks_events', query: query_read_delete, item_list_key: 'events'))
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
          set_api unless command.eql?(:postprocessing)
          case command
          when :version
            return Main.result_single_object(@api_v5.read('version'))
          when :health
            nagios = Nagios.new
            begin
              result = Rest.new(base_url: @faspex5_api_base_url).read('health')
              result.each do |k, v|
                nagios.add_ok(k, v.to_s)
              end
            rescue StandardError => e
              nagios.add_critical('faspex api', e.to_s)
            end
            return nagios.result
          when :user
            case options.get_next_command(%i[account profile])
            when :account
              return Main.result_single_object(@api_v5.read('account'))
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
            invitation_command = options.get_next_command(%i[resend].concat(Plugin::ALL_OPS))
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
              return entity_command(
                invitation_command, @api_v5, invitation_endpoint, item_list_key: invitation_endpoint,
                display_fields: %w[id public recipient_type recipient_name email_address]) do |field, value|
                  lookup_entity_by_field(type: invitation_endpoint, field: field, value: value, query: {})['id']
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
      end
    end
  end
end
