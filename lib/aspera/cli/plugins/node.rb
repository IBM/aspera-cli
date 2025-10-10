# frozen_string_literal: true

# cspell:ignore snid fnid bidi ssync asyncs rund asnodeadmin mkfile mklink asperabrowser asperabrowserurl watchfolders watchfolderd entsrv
require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/sync_actions'
require 'aspera/cli/special_values'
require 'aspera/transfer/spec'
require 'aspera/nagios'
require 'aspera/hash_ext'
require 'aspera/id_generator'
require 'aspera/api/node'
require 'aspera/api/aoc'
require 'aspera/oauth'
require 'aspera/node_simulator'
require 'aspera/assert'
require 'base64'
require 'zlib'

module Aspera
  module Cli
    module Plugins
      class Node < Cli::BasicAuthPlugin
        include SyncActions

        class << self
          # directory: node, container: shares
          FOLDER_TYPES = %w[directory container].freeze
          private_constant :FOLDER_TYPES

          def application_name
            'HSTS Node API'
          end

          def detect(address_or_url)
            urls = if address_or_url.match?(%r{^[a-z]{1,6}://})
              [address_or_url]
            else
              [
                "https://#{address_or_url}",
                "https://#{address_or_url}:9092",
                "http://#{address_or_url}:9091"
              ]
            end
            error = nil
            urls.each do |base_url|
              next unless base_url.match?('https?://')
              api = Rest.new(base_url: base_url)
              test_endpoint = 'ping'
              result = api.call(operation: 'GET', subpath: test_endpoint)
              next unless result[:http].body.eql?('')
              # also remove "/"
              url_end = -2 - test_endpoint.length
              return {
                url:     result[:http].uri.to_s[0..url_end],
                version: 'requires authentication'
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return
          end

          def declare_options(options)
            return if @options_declared
            @options_declared = true
            @dynamic_key = nil
            options.declare(:validator, 'Identifier of validator (optional for central)')
            options.declare(:asperabrowserurl, 'URL for simple aspera web ui', default: 'https://asperabrowser.mybluemix.net')
            options.declare(
              :default_ports, 'Gen4: Use standard FASP ports (true) or get from node API (false)', values: :bool, default: :yes,
              handler: {o: Api::Node, m: :use_standard_ports}
            )
            options.declare(
              :node_cache, 'Gen4: Set to no to force actual file system read', values: :bool,
              handler: {o: Api::Node, m: :use_node_cache}
            )
            options.declare(:root_id, 'Gen4: File id of top folder when using access key (override AK root id)')
            options.declare(:dynamic_key, 'Private key PEM to use for dynamic key auth', handler: {o: Api::Node, m: :use_dynamic_key})
            SyncActions.declare_options(options)
            options.parse_options!
          end

          # Using /files/browse: is it a folder (node and shares)
          def gen3_entry_folder?(entry)
            FOLDER_TYPES.include?(entry['type'])
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [Wizard] The wizard object
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          return {
            preset_value: {
              url:      app_url,
              username: options.get_option(:username, mandatory: true),
              password: options.get_option(:password, mandatory: true)
            },
            test_args:    'info'
          }
        end

        # spellchecker: disable
        # SOAP API call to test central API
        CENTRAL_SOAP_API_TEST = '<?xml version="1.0" encoding="UTF-8"?>' \
          '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="urn:Aspera:XML:FASPSessionNET:2009/11:Types">' \
          '<soapenv:Header></soapenv:Header>' \
          '<soapenv:Body><typ:GetSessionInfoRequest><SessionFilter><SessionStatus>running</SessionStatus></SessionFilter></typ:GetSessionInfoRequest></soapenv:Body>' \
          '</soapenv:Envelope>'
        # spellchecker: enable

        # Fields removed in result of search
        SEARCH_REMOVE_FIELDS = %w[basename permissions].freeze

        # Actions in execute_command_gen3
        COMMANDS_GEN3 = %i[search space mkdir mklink mkfile rename delete browse upload download cat sync transport]

        BASE_ACTIONS = %i[api_details].concat(COMMANDS_GEN3).freeze

        SPECIAL_ACTIONS = %i[health events info slash license].freeze

        # actions available in v3 in gen4
        V3_IN_V4_ACTIONS = %i[access_keys].concat(BASE_ACTIONS).concat(SPECIAL_ACTIONS).freeze

        # actions used commonly when a node is involved
        COMMON_ACTIONS = %i[access_keys].concat(BASE_ACTIONS).concat(SPECIAL_ACTIONS).freeze

        private_constant :CENTRAL_SOAP_API_TEST, :SEARCH_REMOVE_FIELDS, :BASE_ACTIONS, :SPECIAL_ACTIONS, :V3_IN_V4_ACTIONS, :COMMON_ACTIONS

        # used in aoc
        NODE4_READ_ACTIONS = %i[bearer_token_node node_info browse find].freeze

        # commands for execute_command_gen4
        COMMANDS_GEN4 = %i[mkdir mklink mkfile rename delete upload download sync cat show modify permission thumbnail v3].concat(NODE4_READ_ACTIONS).freeze

        # commands supported in ATS for COS
        COMMANDS_COS = %i[upload download info access_keys api_details transfer].freeze
        COMMANDS_SHARES = (BASE_ACTIONS - %i[search]).freeze
        COMMANDS_FASPEX = COMMON_ACTIONS

        GEN4_LS_FIELDS = %w[name type recursive_size size modified_time access_level].freeze

        # @param api [Rest] an existing API object for the Node API
        # @param prefix_path [String,nil] for Faspex 4, allows browsing a package
        def initialize(context:, api: nil, prefix_path: nil)
          @prefix_path = prefix_path
          super(context: context, basic_options: api.nil?)
          Node.declare_options(options)
          return if context.only_manual?
          @api_node =
            if !api.nil?
              # this can be Api::Node or Rest (Shares)
              api
            elsif OAuth::Factory.bearer_auth?(options.get_option(:password, mandatory: true))
              # info is provided like node_info of aoc
              Api::Node.new(
                base_url: options.get_option(:url, mandatory: true),
                headers:  Api::Node.bearer_headers(options.get_option(:password, mandatory: true))
              )
            else
              # this is normal case
              Api::Node.new(
                base_url: options.get_option(:url, mandatory: true),
                auth:     {
                  type:     :basic,
                  username: options.get_option(:username, mandatory: true),
                  password: options.get_option(:password, mandatory: true)
                }
              )
            end
        end

        # reduce the path from a result on given named column
        def c_result_remove_prefix_path(result, column)
          return result if @prefix_path.nil?
          case result[:type]
          when :object_list
            result[:data].each do |item|
              item[column] = item[column][@prefix_path.length..-1] if item[column].start_with?(@prefix_path)
            end
          when :single_object
            item = result[:data]
            item[column] = item[column][@prefix_path.length..-1] if item[column].start_with?(@prefix_path)
          end
          return result
        end

        # translates paths results into CLI result, and removes prefix
        def c_result_translate_rem_prefix(response, type, success_msg)
          errors = []
          final_result = {type: :object_list, data: [], fields: [type, 'result']}
          response['paths'].each do |p|
            result = success_msg
            if p.key?('error')
              Log.log.error{"#{p['error']['user_message']} : #{p['path']}"}
              result = p['error']['user_message']
              errors.push([p['path'], p['error']['user_message']])
            end
            final_result[:data].push({type => p['path'], 'result' => result})
          end
          # one error make all fail
          raise errors.map{ |i| "#{i.first}: #{i.last}"}.join(', ') unless errors.empty?
          return c_result_remove_prefix_path(final_result, type)
        end

        # Gen3 API
        def browse_gen3
          folders_to_process = [get_one_argument_with_prefix('path')]
          query = options.get_option(:query, default: {})
          # special parameter: max number of entries in result
          max_items = query.delete(MAX_ITEMS)
          # special parameter: recursive browsing
          recursive = query.delete('recursive')
          # special parameter: only return one entry for the path, even if folder
          only_path = query.delete('self')
          # allow user to specify a single call, and not recursive
          single_call = query.key?('skip')
          # API default is 100, so use 1000 for default
          query['count'] ||= 1000
          raise Cli::BadArgument, 'options `recursive` and `skip` cannot be used together' if recursive && single_call
          all_items = []
          until folders_to_process.empty?
            path = folders_to_process.shift
            query['path'] = path
            offset = 0
            total_count = nil
            result = nil
            loop do
              # example: send_result={'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}
              response = @api_node.create('files/browse', query)
              # 'file','symbolic_link'
              if !Node.gen3_entry_folder?(response['self']) || only_path
                result = {type: :single_object, data: response['self']}
                break
              end
              items = response['items']
              total_count ||= response['total_count']
              all_items.concat(items)
              if single_call
                formatter.display_item_count(response['item_count'], total_count)
                break
              end
              folders_to_process.concat(items.select{ |i| Node.gen3_entry_folder?(i)}.map{ |i| i['path']}) if recursive
              if !max_items.nil? && (all_items.count >= max_items)
                all_items = all_items.slice(0, max_items) if all_items.count > max_items
                break
              end
              break if all_items.count >= total_count
              offset += items.count
              query['skip'] = offset
              formatter.long_operation_running(all_items.count)
            end
            query.delete('skip')
          end
          result ||= {type: :object_list, data: all_items}
          formatter.long_operation_terminated
          return c_result_remove_prefix_path(result, 'path')
        end

        # Create async transfer spec request from direction and folders
        # @param sync_direction one of push pull bidi
        # @param local_path local folder to sync
        # @param remote_path remote folder to sync
        def sync_spec_request(sync_direction, local_path, remote_path)
          case sync_direction
          when :push then {
            type:  :sync_upload,
            paths: [{
              source:      local_path,
              destination: remote_path
            }]
          }
          when :pull then {
            type:  :sync_download,
            paths: [{
              source:      remote_path,
              destination: local_path
            }]
          }
          when :bidi then {
            type:  :sync,
            paths: [{
              source:      local_path,
              destination: remote_path
            }]
          }
          else Aspera.error_unexpected_value(sync_direction)
          end
        end

        # Commands based on Gen3 API for file and folder
        def execute_command_gen3(command)
          case command
          when :delete
            # TODO: add query for recursive
            paths_to_delete = get_all_arguments_with_prefix('file list')
            resp = @api_node.create('files/delete', {paths: paths_to_delete.map{ |i| {'path' => i.start_with?('/') ? i : "/#{i}"}}})
            return c_result_translate_rem_prefix(resp, 'file', 'deleted')
          when :search
            search_root = get_one_argument_with_prefix('search root')
            parameters = {'path' => search_root}
            other_options = options.get_option(:query)
            parameters.merge!(other_options) unless other_options.nil?
            resp = @api_node.create('files/search', parameters)
            result = {type: :object_list, data: resp['items']}
            return Main.result_empty if result[:data].empty?
            result[:fields] = result[:data].first.keys.reject{ |i| SEARCH_REMOVE_FIELDS.include?(i)}
            formatter.display_item_count(resp['item_count'], resp['total_count'])
            formatter.display_status("params: #{resp['parameters'].keys.map{ |k| "#{k}:#{resp['parameters'][k]}"}.join(',')}")
            return c_result_remove_prefix_path(result, 'path')
          when :space
            path_list = get_all_arguments_with_prefix('folder path or ext.val. list')
            resp = @api_node.create('space', {'paths' => path_list.map{ |i| {path: i}}})
            result = {type: :object_list, data: resp['paths']}
            # return c_result_translate_rem_prefix(resp,'folder','created',@prefix_path)
            return c_result_remove_prefix_path(result, 'path')
          when :mkdir
            path_list = get_all_arguments_with_prefix('folder path or ext.val. list')
            resp = @api_node.create('files/create', {'paths' => path_list.map{ |i| {type: :directory, path: i}}})
            return c_result_translate_rem_prefix(resp, 'folder', 'created')
          when :mklink
            target = get_one_argument_with_prefix('target')
            one_path = get_one_argument_with_prefix('link path')
            resp = @api_node.create('files/create', {'paths' => [{type: :symbolic_link, path: one_path, target: {path: target}}]})
            return c_result_translate_rem_prefix(resp, 'folder', 'created')
          when :mkfile
            one_path = get_one_argument_with_prefix('file path')
            contents64 = Base64.strict_encode64(options.get_next_argument('contents'))
            resp = @api_node.create('files/create', {'paths' => [{type: :file, path: one_path, contents: contents64}]})
            return c_result_translate_rem_prefix(resp, 'folder', 'created')
          when :rename
            # TODO: multiple ?
            path_base = get_one_argument_with_prefix('path_base')
            path_src = get_one_argument_with_prefix('path_src')
            path_dst = get_one_argument_with_prefix('path_dst')
            resp = @api_node.create('files/rename', {'paths' => [{'path' => path_base, 'source' => path_src, 'destination' => path_dst}]})
            return c_result_translate_rem_prefix(resp, 'entry', 'moved')
          when :browse
            return browse_gen3
          when :sync
            return execute_sync_action do |sync_direction, local_path, remote_path|
              # Gen3 API
              # empty transfer spec for authorization request
              request_transfer_spec = sync_spec_request(sync_direction, local_path, remote_path)
              # add fixed parameters if any (for COS)
              @api_node.add_tspec_info(request_transfer_spec) if @api_node.respond_to?(:add_tspec_info)
              # prepare payload for single request
              setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
              # only one request, so only one answer
              transfer_spec = @api_node.create('files/sync_setup', setup_payload)['transfer_specs'].first['transfer_spec']
              # API returns null tag... but async does not like it
              transfer_spec.delete_if{ |_k, v| v.nil?}
              # delete this part, as the returned value contains only destination, and not sources
              # transfer_spec.delete('paths') if command.eql?(:upload)
              Log.dump(:ts, transfer_spec)
              transfer_spec
            end
          when :upload, :download
            # empty transfer spec for authorization request
            request_transfer_spec = {}
            # set requested paths depending on direction
            request_transfer_spec[:paths] = if command.eql?(:download)
              transfer.ts_source_paths
            else
              [{destination: transfer.destination_folder(Transfer::Spec::DIRECTION_SEND)}]
            end
            # add fixed parameters if any (for COS)
            @api_node.add_tspec_info(request_transfer_spec) if @api_node.respond_to?(:add_tspec_info)
            Api::Node.add_public_key(request_transfer_spec)
            # prepare payload for single request
            setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
            # only one request, so only one answer
            transfer_spec = @api_node.create("files/#{command}_setup", setup_payload)['transfer_specs'].first['transfer_spec']
            Api::Node.add_private_key(transfer_spec)
            # delete this part, as the returned value contains only destination, and not sources
            transfer_spec.delete('paths') if command.eql?(:upload)
            return Main.result_transfer(transfer.start(transfer_spec))
          when :cat
            remote_path = get_one_argument_with_prefix('remote path')
            File.basename(remote_path)
            result = @api_node.call(
              operation: 'GET',
              subpath: "files/#{URI.encode_www_form_component(remote_path)}/contents"
            )
            return Main.result_text(result[:http].body)
          when :transport
            return Main.result_single_object(@api_node.transport_params)
          end
          Aspera.error_unreachable_line
        end

        # common API to node and Shares
        def execute_simple_common(command)
          case command
          when *COMMANDS_GEN3
            execute_command_gen3(command)
          when :access_keys
            ak_command = options.get_next_command(%i[do set_bearer_key].concat(Plugin::ALL_OPS))
            case ak_command
            when *Plugin::ALL_OPS
              return entity_execute(
                api: @api_node,
                entity: 'access_keys',
                command: ak_command
              ) do |field, value|
                       raise BadArgument, 'only selector: %id:self' unless field.eql?('id') && value.eql?('self')
                       @api_node.read('access_keys/self')['id']
                     end
            when :do
              access_key_id = options.get_next_argument('access key id')
              root_file_id = options.get_option(:root_id)
              if root_file_id.nil?
                ak_info = @api_node.read("access_keys/#{access_key_id}")
                # change API credentials if different access key
                if !access_key_id.eql?('self')
                  @api_node.auth_params[:username] = ak_info['id']
                  @api_node.auth_params[:password] = config.lookup_secret(url: @api_node.base_url, username: ak_info['id'], mandatory: true)
                end
                root_file_id = ak_info['root_file_id']
              end
              command_repo = options.get_next_command(COMMANDS_GEN4)
              return execute_command_gen4(command_repo, root_file_id)
            when :set_bearer_key
              access_key_id = options.get_next_argument('access key id')
              access_key_id = @api_node.read('access_keys/self')['id'] if access_key_id.eql?('self')
              bearer_key_pem = options.get_next_argument('public or private RSA key PEM value', validation: String)
              key = OpenSSL::PKey.read(bearer_key_pem)
              key = key.public_key if key.private?
              bearer_key_pem = key.to_pem
              @api_node.update("access_keys/#{access_key_id}", {token_verification_key: bearer_key_pem})
              return Main.result_status('public key updated')
            end
          when :health
            nagios = Nagios.new
            begin
              info = @api_node.read('info')
              nagios.add_ok('node api', 'accessible')
              nagios.check_time_offset(info['current_time'], 'node api')
              nagios.check_product_version('node api', 'entsrv', info['version'])
            rescue StandardError => e
              nagios.add_critical('node api', e.to_s)
            end
            begin
              @api_node.call(
                operation:    'POST',
                subpath:      'services/soap/Transfer-201210',
                content_type: Rest::MIME_TEXT,
                body:         CENTRAL_SOAP_API_TEST,
                headers:      {'Content-Type' => 'text/xml;charset=UTF-8', 'SOAPAction' => 'FASPSessionNET-200911#GetSessionInfo'}
              )[:http].body
              nagios.add_ok('central', 'accessible by node')
            rescue StandardError => e
              nagios.add_critical('central', e.to_s)
            end
            return nagios.result
          when :events
            events = @api_node.read('events', query_read_delete)
            return Main.result_object_list(events, fields: ->(f){!f.start_with?('data')})
          when :info
            nd_info = @api_node.read('info')
            return Main.result_single_object(nd_info)
          when :slash
            nd_info = @api_node.read('')
            return Main.result_single_object(nd_info)
          when :license
            # requires: asnodeadmin -mu <node user> --acl-add=internal --internal
            node_license = @api_node.read('license')
            Log.log.error('server must have: asnodeadmin -mu <node user> --acl-add=internal --internal') if node_license['failure'].is_a?(String) && node_license['failure'].include?('ACL')
            return Main.result_single_object(node_license)
          when :api_details
            return Main.result_single_object({base_url: @api_node.base_url}.merge(@api_node.params))
          end
        end

        # Allows to specify a file by its path or by its id on the node in command line
        # @return [Hash] api and main file id for given path or id in next argument
        def apifid_from_next_arg(top_file_id)
          file_path = instance_identifier(description: 'path or %id:<id> or %id:') do |attribute, value|
            raise BadArgument, 'Only selection "id" is supported (file id)' unless attribute.eql?('id')
            # directly return result for method
            return {api: @api_node, file_id: value}
          end
          # there was no selector, so it is a path
          return @api_node.resolve_api_fid(top_file_id, file_path)
        end

        def execute_command_gen4(command_repo, top_file_id)
          override_file_id = options.get_option(:root_id)
          top_file_id = override_file_id unless override_file_id.nil?
          raise Cli::Error, 'Specify root file id with option root_id' if top_file_id.nil?
          case command_repo
          when :v3
            # NOTE: other common actions are unauthorized with user scope
            command_legacy = options.get_next_command(V3_IN_V4_ACTIONS)
            # TODO: shall we support all methods here ? what if there is a link ?
            apifid = @api_node.resolve_api_fid(top_file_id, '')
            return Node.new(context: context, api: apifid[:api]).execute_action(command_legacy)
          when :node_info, :bearer_token_node
            apifid = apifid_from_next_arg(top_file_id)
            result = {
              url:     apifid[:api].base_url,
              root_id: apifid[:file_id]
            }
            Aspera.assert_values(apifid[:api].auth_params[:type], %i[basic oauth2])
            case apifid[:api].auth_params[:type]
            when :basic
              result[:username] = apifid[:api].auth_params[:username]
              result[:password] = apifid[:api].auth_params[:password]
            when :oauth2
              result[:username] = apifid[:api].params[:headers][Api::Node::HEADER_X_ASPERA_ACCESS_KEY]
              result[:password] = apifid[:api].oauth.authorization
            else Aspera.error_unreachable_line
            end
            return Main.result_single_object(result) if command_repo.eql?(:node_info)
            # check format of bearer token
            OAuth::Factory.bearer_token(result[:password])
            return Main.result_text(result[:password])
          when :browse
            apifid = apifid_from_next_arg(top_file_id)
            file_info = apifid[:api].read("files/#{apifid[:file_id]}", **Api::Node.cache_control)
            unless file_info['type'].eql?('folder')
              # a single file
              return Main.result_object_list([file_info], fields: GEN4_LS_FIELDS)
            end
            return Main.result_object_list(apifid[:api].list_files(apifid[:file_id], query: query_read_delete), fields: GEN4_LS_FIELDS)
          when :find
            apifid = apifid_from_next_arg(top_file_id)
            find_lambda = Api::Node.file_matcher_from_argument(options)
            return Main.result_object_list(@api_node.find_files(apifid[:file_id], find_lambda), fields: ['path'])
          when :mkdir, :mklink, :mkfile
            containing_folder_path, new_item = Api::Node.split_folder(options.get_next_argument('path'))
            apifid = @api_node.resolve_api_fid(top_file_id, containing_folder_path, true)
            query = options.get_option(:query, mandatory: false)
            check_exists = true
            payload = {name: new_item}
            if query
              check_exists = !query.delete('check').eql?(false)
              target = query.delete('target')
              if target
                target_apifid = @api_node.resolve_api_fid(top_file_id, target, true)
                payload[:target_id] = target_apifid[:file_id]
              end
              payload.merge!(query.symbolize_keys)
            end
            if check_exists
              folder_content = apifid[:api].read("files/#{apifid[:file_id]}/files")
              link_name = ".#{new_item}.asp-lnk"
              found = folder_content.find{ |i| i['name'].eql?(new_item) || i['name'].eql?(link_name)}
              raise "A #{found['type']} already exists with name #{new_item}" if found
            end
            case command_repo
            when :mkdir
              payload[:type] = :folder
            when :mklink
              payload[:type] = :link
              Aspera.assert(payload[:target_id]){'Missing target_id'}
              Aspera.assert(payload[:target_node_id]){'Missing target_node_id'}
            when :mkfile
              payload[:type] = :file
              payload[:contents] = Base64.strict_encode64(options.get_next_argument('contents'))
            end
            result = apifid[:api].create("files/#{apifid[:file_id]}/files", payload)
            return Main.result_single_object(result)
          when :rename
            file_path = options.get_next_argument('source path')
            apifid = @api_node.resolve_api_fid(top_file_id, file_path)
            newname = options.get_next_argument('new name')
            result = apifid[:api].update("files/#{apifid[:file_id]}", {name: newname})
            return Main.result_status("renamed to #{newname}")
          when :delete
            return do_bulk_operation(command: command_repo, descr: 'path', values: String, id_result: 'path') do |l_path|
              apifid = if (m = l_path.match(REGEX_LOOKUP_ID_BY_FIELD))
                {
                  api:     @api_node,
                  file_id: m[2]
                }
              else
                @api_node.resolve_api_fid(top_file_id, l_path)
              end
              result = apifid[:api].delete("files/#{apifid[:file_id]}")
              {'path' => l_path}
            end
          when :sync
            return execute_sync_action do |sync_direction, _local_path, remote_path|
              # Gen4 API
              Aspera.assert_values(sync_direction, %i[push pull bidi])
              ts_direction = case sync_direction
              when :push, :bidi then Transfer::Spec::DIRECTION_SEND
              when :pull then Transfer::Spec::DIRECTION_RECEIVE
              else Aspera.error_unreachable_line
              end
              # remote is specified by option: `to_folder`
              apifid = @api_node.resolve_api_fid(top_file_id, remote_path)
              apifid[:api].transfer_spec_gen4(apifid[:file_id], ts_direction)
            end
          when :upload
            apifid = @api_node.resolve_api_fid(top_file_id, transfer.destination_folder(Transfer::Spec::DIRECTION_SEND), true)
            return Main.result_transfer(transfer.start(apifid[:api].transfer_spec_gen4(apifid[:file_id], Transfer::Spec::DIRECTION_SEND)))
          when :download
            apifid, source_paths = @api_node.resolve_api_fid_paths(top_file_id, transfer.ts_source_paths)
            return Main.result_transfer(transfer.start(apifid[:api].transfer_spec_gen4(apifid[:file_id], Transfer::Spec::DIRECTION_RECEIVE, {'paths'=>source_paths})))
          when :cat
            apifid = apifid_from_next_arg(top_file_id)
            result = apifid[:api].call(
              operation: 'GET',
              subpath: "files/#{apifid[:file_id]}/content"
            )
            return Main.result_text(result[:http].body)
          when :show
            apifid = apifid_from_next_arg(top_file_id)
            items = apifid[:api].read("files/#{apifid[:file_id]}")
            return Main.result_single_object(items)
          when :modify
            apifid = apifid_from_next_arg(top_file_id)
            update_param = options.get_next_argument('update data', validation: Hash)
            apifid[:api].update("files/#{apifid[:file_id]}", update_param)
            return Main.result_status('Done')
          when :thumbnail
            apifid = apifid_from_next_arg(top_file_id)
            result = apifid[:api].call(
              operation: 'GET',
              subpath: "files/#{apifid[:file_id]}/preview",
              headers: {'Accept' => 'image/png'}
            )
            return Main.result_image(result[:http].body)
          when :permission
            apifid = apifid_from_next_arg(top_file_id)
            command_perm = options.get_next_command(%i[list show create delete])
            case command_perm
            when :list
              list_query = query_read_delete(default: Rest.php_style({'include' => %w[access_level permission_count]}))
              # specify file to get permissions for unless not specified
              list_query['file_id'] = apifid[:file_id] unless apifid[:file_id].to_s.empty?
              list_query['inherited'] = false if list_query.key?('file_id') && !list_query.key?('inherited')
              # NOTE: supports per_page and page and header X-Total-Count
              items = apifid[:api].read('permissions', list_query)
              return Main.result_object_list(items)
            when :show
              perm_id = instance_identifier
              return Main.result_single_object(apifid[:api].read("permissions/#{perm_id}"))
            when :delete
              return do_bulk_operation(command: command_perm, values: :identifier) do |one_id|
                apifid[:api].delete("permissions/#{one_id}")
                # notify application of deletion
                the_app = apifid[:api].app_info
                the_app&.[](:api)&.permissions_send_event(event_data: {}, app_info: the_app, types: ['permission.deleted'])
                {'id' => one_id}
              end
            when :create
              create_param = options.get_next_argument('creation data', validation: Hash)
              raise Cli::BadArgument, 'no file_id' if create_param.key?('file_id')
              create_param['file_id'] = apifid[:file_id]
              create_param['access_levels'] = Api::Node::ACCESS_LEVELS unless create_param.key?('access_levels')
              # add application specific tags (AoC)
              the_app = apifid[:api].app_info
              the_app&.[](:api)&.permissions_set_create_params(perm_data: create_param, app_info: the_app)
              # create permission
              created_data = apifid[:api].create('permissions', create_param)
              # notify application of creation
              the_app&.[](:api)&.permissions_send_event(event_data: created_data, app_info: the_app)
              return Main.result_single_object(created_data)
            else Aspera.error_unreachable_line
            end
          else Aspera.error_unreachable_line
          end
          Aspera.error_unreachable_line
        end

        # Search /async by name
        # @param field [String] name of the field to search
        # @param value [String] value of the field to search
        # @return [Integer] id of the sync
        # @raise [Cli::BadArgument] if no such sync, or not by name
        def async_lookup(field, value)
          raise Cli::BadArgument, "Only search by name is supported (#{field})" unless field.eql?('name')
          async_ids = @api_node.read('async/list')['sync_ids']
          summaries = @api_node.create('async/summary', {'syncs' => async_ids})['sync_summaries']
          selected = summaries.find{ |s| s['name'].eql?(value)}
          raise Cli::BadIdentifier.new('sync', "#{field}=#{value}") if selected.nil?
          return selected['snid']
        end

        # Node API: /async (stats only)
        def execute_async
          command = options.get_next_command(%i[list delete files show counters bandwidth])
          unless command.eql?(:list)
            async_id = instance_identifier{ |field, value| async_lookup(field, value)}
            if async_id.eql?(SpecialValues::ALL)
              raise Cli::BadArgument, 'ALL only for show and delete' unless %i[show delete].include?(command)
              async_ids = @api_node.read('async/list')['sync_ids']
            else
              Integer(async_id) # must be integer
              async_ids = [async_id]
            end
            post_data = {'syncs' => async_ids}
          end
          case command
          when :list
            resp = @api_node.read('async/list')['sync_ids']
            return Main.result_value_list(resp)
          when :show
            resp = @api_node.create('async/summary', post_data)['sync_summaries']
            return Main.result_empty if resp.empty?
            return Main.result_object_list(resp, fields: %w[snid name local_dir remote_dir]) if async_id.eql?(SpecialValues::ALL)
            return Main.result_single_object(resp.first)
          when :delete
            resp = @api_node.create('async/delete', post_data)
            return Main.result_single_object(resp)
          when :bandwidth
            post_data['seconds'] = 100 # TODO: as parameter with --query
            resp = @api_node.create('async/bandwidth', post_data)
            data = resp['bandwidth_data']
            return Main.result_empty if data.empty?
            data = data.first[async_id]['data']
            return Main.result_object_list(data)
          when :files
            # count int
            # filename str
            # skip int
            # status int
            filter = options.get_option(:query)
            post_data.merge!(filter) unless filter.nil?
            resp = @api_node.create('async/files', post_data)
            data = resp['sync_files']
            data = data.first[async_id] unless data.empty?
            iteration_data = []
            skip_ids_persistency = nil
            if options.get_option(:once_only, mandatory: true)
              skip_ids_persistency = PersistencyActionOnce.new(
                manager: persistency,
                data:    iteration_data,
                id:      IdGenerator.from_list([
                  'sync_files',
                  options.get_option(:url, mandatory: true),
                  options.get_option(:username, mandatory: true),
                  async_id
                ])
              )
              data.select!{ |l| l['fnid'].to_i > iteration_data.first} unless iteration_data.first.nil?
              iteration_data[0] = data.last['fnid'].to_i unless data.empty?
            end
            return Main.result_empty if data.empty?
            skip_ids_persistency&.save
            return Main.result_object_list(data)
          when :counters
            resp = @api_node.create('async/counters', post_data)['sync_counters'].first[async_id].last
            return Main.result_empty if resp.nil?
            return Main.result_single_object(resp)
          end
        end

        # Search /asyncs by name
        # @param field [String] name of the field to search
        # @param value [String] value of the field to search
        # @return [Integer] id of the sync
        # @raise [Cli::BadArgument] if no such sync, or not by name
        def ssync_lookup(field, value)
          raise Cli::BadArgument, "Only search by name is supported (#{field})" unless field.eql?('name')
          @api_node.read('asyncs')['ids'].each do |id|
            sync_info = @api_node.read("asyncs/#{id}")['configuration']
            # name is unique, so we can return
            return id if sync_info[field].eql?(value)
          end
          raise Cli::BadIdentifier.new('ssync', "#{field}=#{value}")
        end

        WATCH_FOLDER_MUL = %i[create list].freeze
        WATCH_FOLDER_SING = %i[show modify delete state].freeze
        private_constant :WATCH_FOLDER_MUL, :WATCH_FOLDER_SING

        def watch_folder_action
          res_class_path = 'v3/watchfolders'
          command = options.get_next_command(WATCH_FOLDER_MUL + WATCH_FOLDER_SING)
          if WATCH_FOLDER_SING.include?(command)
            one_res_id = instance_identifier
            one_res_path = "#{res_class_path}/#{one_res_id}"
          end
          # hum, to avoid: Unable to convert 2016_09_14 configuration
          @api_node.params[:headers] ||= {}
          @api_node.params[:headers]['X-aspera-WF-version'] = '2017_10_23'
          case command
          when :create
            resp = @api_node.create(res_class_path, value_create_modify(command: command))
            return Main.result_status("#{resp['id']} created")
          when :list
            resp = @api_node.read(res_class_path, query_read_delete)
            return Main.result_value_list(resp['ids'])
          when :show
            return Main.result_single_object(@api_node.read(one_res_path))
          when :modify
            @api_node.update(one_res_path, options.get_option(:query, mandatory: true))
            return Main.result_status("#{one_res_id} updated")
          when :delete
            @api_node.delete(one_res_path)
            return Main.result_status("#{one_res_id} deleted")
          when :state
            return Main.result_single_object(@api_node.read("#{one_res_path}/state"))
          end
        end

        ACTIONS = %i[
          async
          ssync
          stream
          transfer
          service
          watch_folder
          central
          asperabrowser
          basic_token
          bearer_token
          simulator
          telemetry
        ].concat(COMMON_ACTIONS).freeze

        def execute_action(command = nil)
          command ||= options.get_next_command(ACTIONS)
          case command
          when *COMMON_ACTIONS then return execute_simple_common(command)
          when :async then return execute_async # former API
          when :ssync
            # Node API: /asyncs (newer)
            sync_command = options.get_next_command(%i[start stop bandwidth counters files state summary] + Plugin::ALL_OPS - %i[modify])
            case sync_command
            when *Plugin::ALL_OPS
              return entity_execute(
                api: @api_node,
                entity: :asyncs,
                command: sync_command,
                items_key: 'ids'
              ){ |field, value| ssync_lookup(field, value)}
            else
              asyncs_id = instance_identifier{ |field, value| ssync_lookup(field, value)}
              if %i[start stop].include?(sync_command)
                @api_node.call(
                  operation:    'POST',
                  subpath:      "asyncs/#{asyncs_id}/#{sync_command}",
                  content_type: Rest::MIME_TEXT,
                  body:         ''
                )[:http].body
                return Main.result_status('Done')
              end
              parameters = nil
              parameters = options.get_option(:query, default: {}) if %i[bandwidth counters files].include?(sync_command)
              return Main.result_single_object(@api_node.read("asyncs/#{asyncs_id}/#{sync_command}", parameters))
            end
          when :stream
            command = options.get_next_command(%i[list create show modify cancel])
            case command
            when :list
              resp = @api_node.read('ops/transfers', query_read_delete)
              return Main.result_object_list(resp, fields: %w[id status]) # TODO: useful?
            when :create
              resp = @api_node.create('streams', value_create_modify(command: command))
              return Main.result_single_object(resp)
            when :show
              resp = @api_node.read("ops/transfers/#{options.get_next_argument('transfer id')}")
              return Main.result_single_object(resp)
            when :modify
              resp = @api_node.update("streams/#{options.get_next_argument('transfer id')}", value_create_modify(command: command))
              return Main.result_single_object(resp)
            when :cancel
              resp = @api_node.cancel("streams/#{options.get_next_argument('transfer id')}")
              return Main.result_single_object(resp)
            else Aspera.error_unexpected_value(command)
            end
          when :transfer
            command = options.get_next_command(%i[list cancel show modify bandwidth_average sessions])
            case command
            when :list
              transfer_filter = query_read_delete(default: {})
              iteration_persistency = nil
              if options.get_option(:once_only, mandatory: true)
                iteration_persistency = PersistencyActionOnce.new(
                  manager: persistency,
                  data:    [],
                  id:      IdGenerator.from_list([
                    'node_transfers',
                    options.get_option(:url, mandatory: true),
                    options.get_option(:username, mandatory: true)
                  ])
                )
                if transfer_filter.delete('reset')
                  iteration_persistency.data.clear
                  iteration_persistency.save
                  return Main.result_status('Persistency reset')
                end
              end
              raise Cli::BadArgument, 'reset only with once_only' if transfer_filter.key?('reset') && iteration_persistency.nil?
              max_items = transfer_filter.delete(MAX_ITEMS)
              transfers_data = call_with_iteration(api: @api_node, operation: 'GET', subpath: 'ops/transfers', max: max_items, query: transfer_filter, iteration: iteration_persistency&.data)
              iteration_persistency&.save
              return Main.result_object_list(transfers_data, fields: %w[id status start_spec.direction start_spec.remote_user start_spec.remote_host start_spec.destination_path])
            when :sessions
              transfers_data = @api_node.read('ops/transfers', query_read_delete)
              sessions = transfers_data.map{ |t| t['sessions']}.flatten
              sessions.each do |session|
                session['start_time'] = Time.at(session['start_time_usec'] / 1_000_000.0).utc.iso8601(0)
                session['end_time'] = Time.at(session['end_time_usec'] / 1_000_000.0).utc.iso8601(0)
              end
              return Main.result_object_list(sessions, fields: %w[id status start_time end_time target_rate_kbps])
            when :cancel
              resp = @api_node.cancel("ops/transfers/#{instance_identifier}")
              return Main.result_single_object(resp)
            when :show
              resp = @api_node.read("ops/transfers/#{instance_identifier}")
              return Main.result_single_object(resp)
            when :modify
              resp = @api_node.update("ops/transfers/#{instance_identifier}", options.get_next_argument('update value', validation: Hash))
              return Main.result_single_object(resp)
            when :bandwidth_average
              transfers_data = @api_node.read('ops/transfers', query_read_delete)
              # collect all key dates
              bandwidth_period = {}
              dir_info = %i[avg_kbps sessions].freeze
              transfers_data.each do |transfer|
                session = transfer
                # transfer['sessions'].each do |session|
                next if session['avg_rate_kbps'].zero?
                bandwidth_period[session['start_time_usec']] = 0
                bandwidth_period[session['end_time_usec']] = 0
                # end
              end
              result = []
              # all dates sorted numerically
              all_dates = bandwidth_period.keys.sort
              all_dates.each_with_index do |start_date, index|
                end_date = all_dates[index + 1]
                # do not process last one
                break if end_date.nil?
                # init data for this period
                period_bandwidth = Transfer::Spec::DIRECTION_ENUM_VALUES.map(&:to_sym).each_with_object({}) do |direction, h|
                  h[direction] = dir_info.each_with_object({}) do |k2, h2|
                    h2[k2] = 0
                  end
                end
                # find all transfers that were active at this time
                transfers_data.each do |transfer|
                  session = transfer
                  # transfer['sessions'].each do |session|
                  # skip if not information for this period
                  next if session['avg_rate_kbps'].zero?
                  # skip if not in this period
                  next if session['start_time_usec'] >= end_date || session['end_time_usec'] <= start_date
                  info = period_bandwidth[transfer['start_spec']['direction'].to_sym]
                  info[:avg_kbps] += session['avg_rate_kbps']
                  info[:sessions] += 1
                  # end
                end
                next if Transfer::Spec::DIRECTION_ENUM_VALUES.map(&:to_sym).all? do |dir|
                  period_bandwidth[dir][:sessions].zero?
                end
                result.push({start: Time.at(start_date / 1_000_000), end: Time.at(end_date / 1_000_000)}.merge(period_bandwidth))
              end
              return Main.result_object_list(result)
            else Aspera.error_unexpected_value(command)
            end
          when :service
            command = options.get_next_command(%i[list create delete])
            service_id = instance_identifier if [:delete].include?(command)
            case command
            when :list
              resp = @api_node.read('rund/services')
              return Main.result_object_list(resp['services'])
            when :create
              # @json:'{"type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
              params = options.get_next_argument('creation data', validation: Hash)
              resp = @api_node.create('rund/services', params)
              return Main.result_status("#{resp['id']} created")
            when :delete
              @api_node.delete("rund/services/#{service_id}")
              return Main.result_status("#{service_id} deleted")
            end
          when :watch_folder
            return watch_folder_action
          when :central
            command = options.get_next_command(%i[session file])
            validator_id = options.get_option(:validator)
            validation = {'validator_id' => validator_id} unless validator_id.nil?
            request_data = options.get_option(:query, default: {})
            case command
            when :session
              command = options.get_next_command([:list])
              case command
              when :list
                request_data = options.get_next_argument('request data', mandatory: false, validation: Hash, default: {})
                request_data.deep_merge!({'validation' => validation}) unless validation.nil?
                resp = @api_node.create('services/rest/transfers/v1/sessions', request_data)
                return Main.result_object_list(resp['session_info_result']['session_info'], fields: %w[session_uuid status transport direction bytes_transferred])
              end
            when :file
              command = options.get_next_command(%i[list modify])
              case command
              when :list
                request_data = options.get_next_argument('request data', mandatory: false, validation: Hash, default: {})
                request_data.deep_merge!({'validation' => validation}) unless validation.nil?
                resp = @api_node.create('services/rest/transfers/v1/files', request_data)
                resp = JSON.parse(resp) if resp.is_a?(String)
                Log.dump(:resp, resp)
                return Main.result_object_list(resp['file_transfer_info_result']['file_transfer_info'], fields: %w[session_uuid file_id status path])
              when :modify
                request_data = options.get_next_argument('request data', mandatory: false, validation: Hash, default: {})
                request_data.deep_merge!(validation) unless validation.nil?
                @api_node.update('services/rest/transfers/v1/files', request_data)
                return Main.result_status('updated')
              end
            end
          when :asperabrowser
            browse_params = {
              'nodeUser' => options.get_option(:username, mandatory: true),
              'nodePW'   => options.get_option(:password, mandatory: true),
              'nodeURL'  => options.get_option(:url, mandatory: true)
            }
            # encode parameters so that it looks good in url
            encoded_params = Base64.strict_encode64(Zlib::Deflate.deflate(JSON.generate(browse_params))).gsub(/=+$/, '').tr('+/', '-_').reverse
            Environment.instance.open_uri("#{options.get_option(:asperabrowserurl)}?goto=#{encoded_params}")
            return Main.result_status('done')
          when :basic_token
            return Main.result_text(Rest.basic_authorization(options.get_option(:username, mandatory: true), options.get_option(:password, mandatory: true)))
          when :bearer_token
            private_key = OpenSSL::PKey::RSA.new(options.get_next_argument('private RSA key PEM value', validation: String))
            token_info = options.get_next_argument('user and group identification', validation: Hash)
            access_key = options.get_option(:username, mandatory: true)
            return Main.result_text(Api::Node.bearer_token(payload: token_info, access_key: access_key, private_key: private_key))
          when :simulator
            require 'aspera/node_simulator'
            parameters = value_create_modify(command: command, default: {}).symbolize_keys
            uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
            server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
            server.mount(uri.path, NodeSimulatorServlet, parameters.except(*WebServerSimple::PARAMS), NodeSimulator.new)
            server.start
            return Main.result_status('Simulator terminated')
          when :telemetry
            parameters = value_create_modify(command: command, default: {}).symbolize_keys
            %i[url key].each do |psym|
              raise Cli::BadArgument, "Missing parameter: #{psym}" unless parameters.key?(psym)
            end
            require 'socket'
            parameters[:interval] = 10 unless parameters.key?(:interval)
            parameters[:hostname] = Socket.gethostname unless parameters.key?(:hostname)
            interval = parameters[:interval].to_f
            raise Cli::BadArgument, 'Interval must be a positive number in seconds' if interval <= 0
            otel_api = Rest.new(
              base_url: "#{parameters[:url]}/v1",
              headers: {
                # 'Authorization'  => "apiToken #{parameters[:key]}",
                'x-instana-key'  => parameters[:key],
                'x-instana-host' => parameters[:hostname]
              }
            )
            datapoint = {
              attributes:   [
                {
                  key:   'server.name',
                  value: {
                    stringValue: 'HSTS1'
                  }
                }
              ],
              asInt:        nil,
              timeUnixNano: nil
            }
            # https://opentelemetry.io/docs/specs/otel/metrics/data-model/#gauge
            metrics = {
              resourceMetrics: [
                {
                  resource:     {
                    attributes: [
                      {
                        key:   'service.name',
                        value: {
                          stringValue: 'IBMAspera'
                        }
                      }
                    ]
                  },
                  scopeMetrics: [
                    {
                      metrics: [
                        {
                          name:        'active.transfers',
                          description: 'Number of active transfers',
                          unit:        '1',
                          gauge:       {
                            dataPoints: [
                              datapoint
                            ]
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            loop do
              timestamp = Time.now
              transfers_data = call_with_iteration(api: @api_node, operation: 'GET', subpath: 'ops/transfers', query: {active_only: true})
              datapoint[:asInt] = transfers_data.length
              datapoint[:timeUnixNano] = timestamp.to_i * 1_000_000_000 + timestamp.nsec
              Log.log.info("#{datapoint[:asInt]} active transfers")
              # https://www.ibm.com/docs/en/instana-observability/current?topic=instana-backend
              otel_api.create('metrics', metrics)
              break if interval.eql?(0.0)
              sleep([0.0, interval - (Time.now - timestamp)].max)
            end
          end
          Aspera.error_unreachable_line
        end

        private

        # get remaining path arguments from command line, and add prefix
        def get_all_arguments_with_prefix(name)
          path_args = options.get_next_argument(name, multiple: true)
          return path_args if @prefix_path.nil?
          return path_args.map{ |p| File.join(@prefix_path, p)}
        end

        # get next path argument from command line, and add prefix
        def get_one_argument_with_prefix(name)
          path_arg = options.get_next_argument(name, validation: String)
          return path_arg if @prefix_path.nil?
          return File.join(@prefix_path, path_arg)
        end

        # Executes the provided API call in loop
        # @param api       [Rest]    the API to call
        # @param iteration [Array]   a single element array with the iteration token or nil
        # @param max       [Integer] maximum number of items to return, or nil for no limit
        # @param query     [Hash]    query parameters to use for the API call
        # @param call_args [Hash]    additional arguments to pass to the API call
        # @return [Array] list of items returned by the API call
        def call_with_iteration(api:, iteration: nil, max: nil, query: nil, **call_args)
          Aspera.assert_type(iteration, Array, NilClass){'iteration'}
          Aspera.assert_type(query, Hash, NilClass){'query'}
          query_token = query&.dup || {}
          item_list = []
          query_token[:iteration_token] = iteration[0] unless iteration.nil?
          loop do
            result = api.call(**call_args, query: query_token)
            Aspera.assert_type(result[:data], Array){"Expected data to be an Array, got: #{result[:data].class}"}
            # no data
            break if result[:data].empty?
            # get next iteration token from link
            next_iteration_token = nil
            link_info = result[:http]['Link']
            unless link_info.nil?
              m = link_info.match(/<([^>]+)>/)
              Aspera.assert(m){"Cannot parse iteration in Link: #{link_info}"}
              next_iteration_token = CGI.parse(URI.parse(m[1]).query)['iteration_token']&.first
            end
            # same as last iteration: stop
            break if next_iteration_token&.eql?(query_token[:iteration_token])
            query_token[:iteration_token] = next_iteration_token
            item_list.concat(result[:data])
            if max&.<=(item_list.length)
              item_list = item_list.slice(0, max)
              break
            end
            break if next_iteration_token.nil?
          end
          # save iteration token if needed
          iteration[0] = query_token[:iteration_token] unless iteration.nil?
          item_list
        end
      end
    end
  end
end
