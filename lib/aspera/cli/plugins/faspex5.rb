# frozen_string_literal: true

# spellchecker: ignore workgroups,mypackages

require 'aspera/cli/basic_auth_plugin'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/nagios'
require 'aspera/environment'
require 'securerandom'
require 'ruby-progressbar'
require 'tty-spinner'

module Aspera
  module Cli
    module Plugins
      class Faspex5 < Aspera::Cli::BasicAuthPlugin
        RECIPIENT_TYPES = %w[user workgroup external_user distribution_list shared_inbox].freeze
        PACKAGE_TERMINATED = %w[completed failed].freeze
        API_DETECT = 'api/v5/configuration/ping'
        class << self
          def detect(base_url)
            api = Rest.new(base_url: base_url, redirect_max: 1)
            result = api.read(API_DETECT)
            if result[:http].code.start_with?('2') && result[:http].body.strip.empty?
              return {version: '5', url: result[:http].uri.to_s[0..-(API_DETECT.length + 2)]}
            end
            return nil
          end
        end

        TRANSFER_CONNECT = 'connect'

        def initialize(env)
          super(env)
          options.add_opt_simple(:client_id, 'OAuth client identifier')
          options.add_opt_simple(:client_secret, 'OAuth client secret')
          options.add_opt_simple(:redirect_uri, 'OAuth redirect URI for web authentication')
          options.add_opt_list(:auth, [:boot].concat(Oauth::STD_AUTH_TYPES), 'OAuth type of authentication')
          options.add_opt_simple(:private_key, 'OAuth JWT RSA private key PEM value (prefix file path with @file:)')
          options.add_opt_simple(:passphrase, 'RSA private key passphrase')
          options.add_opt_simple(:shared_folder, 'Shared folder source for package files')
          options.set_option(:auth, :jwt)
          options.parse_options!
        end

        def set_api
          @faspex5_api_base_url = options.get_option(:url, is_type: :mandatory).gsub(%r{/+$}, '')
          @faspex5_api_auth_url = "#{@faspex5_api_base_url}/auth"
          faspex5_api_v5_url = "#{@faspex5_api_base_url}/api/v5"
          case options.get_option(:auth, is_type: :mandatory)
          when :boot
            # the password here is the token copied directly from browser in developer mode
            @api_v5 = Rest.new({
              base_url: faspex5_api_v5_url,
              headers:  {'Authorization' => options.get_option(:password, is_type: :mandatory)}
            })
          when :web
            # opens a browser and ask user to auth using web
            @api_v5 = Rest.new({
              base_url: faspex5_api_v5_url,
              auth:     {
                type:         :oauth2,
                base_url:     @faspex5_api_auth_url,
                grant_method: :web,
                client_id:    options.get_option(:client_id, is_type: :mandatory),
                web:          {redirect_uri: options.get_option(:redirect_uri, is_type: :mandatory)}
              }})
          when :jwt
            app_client_id = options.get_option(:client_id, is_type: :mandatory)
            @api_v5 = Rest.new({
              base_url: faspex5_api_v5_url,
              auth:     {
                type:         :oauth2,
                base_url:     @faspex5_api_auth_url,
                grant_method: :jwt,
                client_id:    app_client_id,
                jwt:          {
                  payload:         {
                    iss: app_client_id,    # issuer
                    aud: app_client_id,    # audience TODO: ???
                    sub: "user:#{options.get_option(:username, is_type: :mandatory)}" # subject also "client:#{app_client_id}" + auth user/pass
                  },
                  # auth:                {type: :basic, options.get_option(:username,is_type: :mandatory), options.get_option(:password,is_type: :mandatory),
                  private_key_obj: OpenSSL::PKey::RSA.new(options.get_option(:private_key, is_type: :mandatory), options.get_option(:passphrase)),
                  headers:         {typ: 'JWT'}
                }
              }})
          end
        end

        def normalize_recipients(parameters)
          return unless parameters.key?('recipients')
          raise 'Field recipients must be an Array' unless parameters['recipients'].is_a?(Array)
          parameters['recipients'] = parameters['recipients'].map do |recipient_data|
            # if just a string, assume it is the name
            if recipient_data.is_a?(String)
              result = @api_v5.read('contacts', {q: recipient_data, context: 'packages', type: [Rest::ARRAY_PARAMS, *RECIPIENT_TYPES]})[:data]
              raise "No matching contact for #{recipient_data}" if result.empty?
              raise "Multiple matching contact for #{recipient_data} : #{result['contacts'].map{|i|i['name']}.join(', ')}" unless 1.eql?(result['total_count'])
              matched = result['contacts'].first
              recipient_data = {
                name:           matched['name'],
                recipient_type: matched['type']
              }
            end
            # result for mapping
            recipient_data
          end
        end

        def wait_for_complete_upload(id)
          parameters = options.get_option(:value)
          spinner = nil
          progress = nil
          while true
            status = @api_v5.read("packages/#{id}/upload_details")[:data]
            # user asked to not follow
            break unless parameters
            if status['upload_status'].eql?('submitted')
              if spinner.nil?
                spinner = TTY::Spinner.new('[:spinner] :title', format: :classic)
                spinner.start
              end
              spinner.update(title: status['upload_status'])
              spinner.spin
            elsif progress.nil?
              progress = ProgressBar.create(
                format:     '%a %B %p%% %r Mbps %e',
                rate_scale: lambda{|rate|rate / Environment::BYTES_PER_MEBIBIT},
                title:      'progress',
                total:      status['bytes_total'].to_i)
            else
              progress.progress = status['bytes_written'].to_i
            end
            break if PACKAGE_TERMINATED.include?(status['upload_status'])
            sleep(0.5)
          end
          status['id'] = id
          return status
        end

        def lookup_entity(entity_type, property, value)
          # TODO: what if too many, use paging ?
          all = @api_v5.read(entity_type)[:data][entity_type]
          found = all.find{|i|i[property].eql?(value)}
          raise "No #{entity_type} with #{property} = #{value}" if found.nil?
          return found
        end

        ACTIONS = %i[health version user bearer_token package shared_folders admin gateway postprocessing].freeze

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
          when :package
            command = options.get_next_command(%i[list show status delete send receive])
            case command
            when :list
              parameters = options.get_option(:value)
              return {
                type:   :object_list,
                data:   @api_v5.read('packages', parameters)[:data]['packages'],
                fields: %w[id title release_date total_bytes total_files created_time state]
              }
            when :show
              id = instance_identifier
              return {type: :single_object, data: @api_v5.read("packages/#{id}")[:data]}
            when :status
              status = wait_for_complete_upload(instance_identifier)
              return {type: :single_object, data: status}
            when :delete
              ids = instance_identifier
              ids = [ids] unless ids.is_a?(Array)
              raise "Identifier must be a single id or an array (#{ids.class}, #{ids.first.class})" unless ids.is_a?(Array) && ids.all?(String)
              # APU returns 204, empty on success
              @api_v5.call({operation: 'DELETE', subpath: 'packages', headers: {'Accept' => 'application/json'}, json_params: {ids: ids}})
              return Main.result_status('Package(s) deleted')
            when :send
              parameters = options.get_option(:value, is_type: :mandatory)
              raise CliBadArgument, 'Value must be Hash, refer to API' unless parameters.is_a?(Hash)
              normalize_recipients(parameters)
              package = @api_v5.create('packages', parameters)[:data]
              shared_folder = options.get_option(:shared_folder)
              if shared_folder.nil?
                # TODO: option to send from remote source or httpgw
                transfer_spec = @api_v5.call(
                  operation:   'POST',
                  subpath:     "packages/#{package['id']}/transfer_spec/upload",
                  headers:     {'Accept' => 'application/json'},
                  url_params:  {transfer_type: TRANSFER_CONNECT},
                  json_params: {paths: transfer.source_list}
                )[:data]
                transfer_spec.delete('authentication')
                return Main.result_transfer(transfer.start(transfer_spec))
              else
                if !shared_folder.to_i.to_s.eql?(shared_folder)
                  shared_folder = lookup_entity('shared_folders', 'name', shared_folder)['id']
                end
                transfer_request = {shared_folder_id: shared_folder, paths: transfer.source_list}
                # start remote transfer and get first status
                result = @api_v5.create("packages/#{package['id']}/remote_transfer", transfer_request)[:data]
                result['id'] = package['id']
                unless result['status'].eql?('completed')
                  formatter.display_status("Package #{package['id']}")
                  result = wait_for_complete_upload(package['id'])
                end
                return {type: :single_object, data: result}
              end
            when :receive
              pkg_type = 'received'
              pack_id = instance_identifier
              package_ids = [pack_id]
              skip_ids_data = []
              skip_ids_persistency = nil
              if options.get_option(:once_only, is_type: :mandatory)
                # read ids from persistency
                skip_ids_persistency = PersistencyActionOnce.new(
                  manager: @agents[:persistency],
                  data:    skip_ids_data,
                  id:      IdGenerator.from_list([
                    'faspex_recv',
                    options.get_option(:url, is_type: :mandatory),
                    options.get_option(:username, is_type: :mandatory),
                    pkg_type]))
              end
              if VAL_ALL.eql?(pack_id)
                # TODO: if packages have same name, they will overwrite
                parameters = options.get_option(:value)
                parameters ||= {'type' => 'received', 'subtype' => 'mypackages', 'limit' => 1000}
                raise CliBadArgument, 'value filter must be Hash (API GET)' unless parameters.is_a?(Hash)
                package_ids = @api_v5.read('packages', parameters)[:data]['packages'].map{|p|p['id']}
                package_ids.reject!{|i|skip_ids_data.include?(i)}
              end
              result_transfer = []
              package_ids.each do |pkg_id|
                param_file_list = {}
                begin
                  param_file_list['paths'] = transfer.source_list
                rescue Aspera::Cli::CliBadArgument
                  # paths is optional
                end
                # TODO: allow from sent as well ?
                transfer_spec = @api_v5.call(
                  operation:   'POST',
                  subpath:     "packages/#{pkg_id}/transfer_spec/download",
                  headers:     {'Accept' => 'application/json'},
                  url_params:  {transfer_type: TRANSFER_CONNECT, type: pkg_type},
                  json_params: param_file_list
                )[:data]
                transfer_spec.delete('authentication')
                statuses = transfer.start(transfer_spec)
                result_transfer.push({'package' => pkg_id, Main::STATUS_FIELD => statuses})
                # skip only if all sessions completed
                skip_ids_data.push(pkg_id) if TransferAgent.session_status(statuses).eql?(:success)
              end
              skip_ids_persistency&.save
              return Main.result_transfer_multiple(result_transfer)
            end # case package
          when :shared_folders
            all_shared_folders = @api_v5.read('shared_folders')[:data]['shared_folders']
            case options.get_next_command(%i[list browse])
            when :list
              return {type: :object_list, data: all_shared_folders}
            when :browse
              shared_folder_id = instance_identifier
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
            case options.get_next_command(%i[resource])
            when :resource
              res_type = options.get_next_command(%i[accounts contacts jobs workgroups shared_inboxes nodes oauth_clients registrations saml_configs metadata_profiles
                                                     email_notifications])
              res_path = list_key = res_type.to_s
              id_as_arg = false
              case res_type
              when :metadata_profiles
                res_path = 'configuration/metadata_profiles'
                list_key = 'profiles'
              when :email_notifications
                list_key = false
                id_as_arg = 'type'
              end
              display_fields =
                case res_type
                when :accounts then [:all_but, 'user_profile_data_attributes']
                when :oauth_clients then [:all_but, 'public_key']
                end
              adm_api = @api_v5
              if res_type.eql?(:oauth_clients)
                adm_api = Rest.new(@api_v5.params.merge({base_url: @faspex5_api_auth_url}))
              end
              return entity_action(adm_api, res_path, item_list_key: list_key, display_fields: display_fields, id_as_arg: id_as_arg)
            end
          when :gateway
            require 'aspera/faspex_gw'
            url = options.get_option(:value, is_type: :mandatory)
            uri = URI.parse(url)
            server = WebServerSimple.new(uri)
            server.mount(uri.path, Faspex4GWServlet, @api_v5, nil)
            trap('INT') { server.shutdown }
            formatter.display_status("Faspex 4 gateway listening on #{url}")
            Log.log.info("Listening on #{url}")
            # this is blocking until server exits
            server.start
            return Main.result_status('Gateway terminated')
          when :postprocessing
            require 'aspera/faspex_postproc'
            parameters = options.get_option(:value, is_type: :mandatory)
            raise 'parameters must be Hash' unless parameters.is_a?(Hash)
            parameters = parameters.symbolize_keys
            raise 'Missing key: url' unless parameters.key?(:url)
            uri = URI.parse(parameters[:url])
            parameters[:processing] ||= {}
            parameters[:processing][:root] = uri.path
            server = WebServerSimple.new(uri, certificate: parameters[:certificate])
            server.mount(uri.path, Faspex4PostProcServlet, parameters[:processing])
            trap('INT') { server.shutdown }
            formatter.display_status("Faspex 4 post processing listening on #{uri.port}")
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
