# frozen_string_literal: true

# cspell:ignore snid fnid bidi ssync asyncs rund asnodeadmin mkfile mklink asperabrowser asperabrowserurl watchfolders watchfolderd entsrv
require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/sync_actions'
require 'aspera/cli/special_values'
require 'aspera/transfer/spec'
require 'aspera/nagios'
require 'aspera/hash_ext'
require 'aspera/id_generator'
require 'aspera/api/node'
require 'aspera/oauth'
require 'aspera/node_simulator'
require 'aspera/rest_list'
require 'aspera/assert'
require 'base64'
require 'zlib'

module Aspera
  module Cli
    module Plugins
      class Node < BasicAuth
        include SyncActions

        # Processing of paths in arguments and results
        # Used only by Faspex4 to browse packages
        class NodePathPrefix
          def initialize(path)
            @root = path
          end

          # get next path argument from command line, and add prefix
          def add_to_path(path_arg)
            File.join(@root, path_arg)
          end

          # get remaining path arguments from command line, and add prefix
          def add_to_paths!(path_args)
            path_args.map!{ |p| add_to_path(p)}
          end

          def remove_in_object_list!(obj_list)
            obj_list.each do |item|
              item['path'] = item['path'].delete_prefix(@root) if item['path'].start_with?(@root)
            end
          end
        end

        application_name 'HSTS Node API'

        SESSION_TIME_FIELDS = %i[start end].freeze
        private_constant :SESSION_TIME_FIELDS

        # ssync sub-commands that accept query parameters
        SSYNC_WITH_PARAMS_ACTIONS = %i[bandwidth counters files].freeze
        private_constant :SSYNC_WITH_PARAMS_ACTIONS

        class << self
          # directory: node, container: shares
          FOLDER_TYPES = %w[directory container].freeze
          private_constant :FOLDER_TYPES

          # @return [Hash,NilClass]
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
              next unless base_url.match?(%r{^https?://})
              api = Rest.new(base_url: base_url)
              test_endpoint = 'ping'
              http = api.read(test_endpoint, ret: :resp)
              next unless http.body.eql?('')
              # also remove "/"
              url_end = -2 - test_endpoint.length
              return {
                url:     http.uri.to_s[0..url_end],
                version: 'requires authentication'
              }
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return
          end

          # Called by non-Node plugins (Ats, Cos, Aoc) to declare Node options on their
          # own options object. The DSL registry is walked so descriptions stay in one place.
          def declare_options(options)
            return if options.option_declared?(:root_id)
            command_registry.option_specs.each_value do |spec|
              next if options.option_declared?(spec.name)
              options.declare(
                spec.name,
                spec.description,
                short:    spec.short,
                allowed:  spec.allowed,
                default:  spec.default,
                handler:  spec.handler,
                schema:   spec.schema
              )
            end
            options.parse_options!
          end

          # Using /files/browse: is it a folder (node and shares)
          def gen3_entry_folder?(entry)
            FOLDER_TYPES.include?(entry['type'])
          end
        end

        # DSL option declarations — at class level, picked up by Base#initialize via ancestor chain.
        # Also exposed via Node.declare_options for non-Node plugins (Ats, Cos, Aoc).
        option :validator, 'Identifier of validator (optional for central)'
        option :asperabrowserurl, 'URL for simple aspera web ui', default: 'https://asperabrowser.mybluemix.net'
        option :node_api,        'Gen4: standard_ports: Use standard FASP ports (true) or get from node API (false). cache: Set to false to force actual file system read',
          allowed: Hash, handler: {o: Api::Node, m: :api_options}
        option :root_id,         'Gen4: File id of top folder when using access key (override AK root id)'
        option :dynamic_key,     'Private key PEM to use for dynamic key auth', handler: {o: Api::Node, m: :use_dynamic_key}

        # @param wizard  [Wizard] The wizard object
        # @param app_url [String] Tested URL
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
        COMMANDS_GEN3 = %i[search space mkdir mklink mkfile rename delete browse upload download cat sync transport spec]

        BASE_ACTIONS = %i[api_details].concat(COMMANDS_GEN3).freeze

        SPECIAL_ACTIONS = %i[health events info slash license].freeze

        # commands for : `execute_simple_common`: actions used commonly when a node is involved
        COMMON_ACTIONS = %i[access_keys].concat(BASE_ACTIONS).concat(SPECIAL_ACTIONS).freeze

        # actions available in v3 in gen4
        V3_IN_V4_ACTIONS = %i[transfer].concat(COMMON_ACTIONS).freeze

        private_constant :CENTRAL_SOAP_API_TEST, :SEARCH_REMOVE_FIELDS, :BASE_ACTIONS, :SPECIAL_ACTIONS, :V3_IN_V4_ACTIONS, :COMMON_ACTIONS

        # used in aoc
        NODE4_READ_ACTIONS = %i[bearer_token_node node_info browse find].freeze

        # commands for execute_command_gen4
        COMMANDS_GEN4 = %i[mkdir mklink mkfile rename delete upload download sync cat show modify permission thumbnail v3].concat(NODE4_READ_ACTIONS).freeze

        # commands supported in ATS for COS
        COMMANDS_COS = %i[upload download info access_keys api_details transfer].freeze
        COMMANDS_SHARES = (BASE_ACTIONS - %i[search]).freeze
        COMMANDS_FASPEX = COMMON_ACTIONS

        # `browse` display fields for gen4
        GEN4_LS_FIELDS = %w[name type recursive_size size modified_time access_level].freeze

        # @param api [Rest] an existing API object for the Node API
        # @param prefix_path [String,nil] for Faspex 4, allows browsing a package without full path in node (removes storage prefix)
        def initialize(context:, api: nil, prefix_path: nil)
          @node_path_prefix = prefix_path ? NodePathPrefix.new(prefix_path) : nil
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

        # Gen3 API
        def browse_gen3
          folders_to_process = options.get_next_argument('path', validation: String)
          folders_to_process = @node_path_prefix.add_to_path(folders_to_process) unless @node_path_prefix.nil?
          folders_to_process = [folders_to_process]
          query = options.get_option(:query) || {}
          # special parameter: max number of entries in result
          max_items = query.delete(RestList::MAX_ITEMS)
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
            loop do
              # example: send_result={'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}
              response = @api_node.create('files/browse', query)
              # 'file','symbolic_link'
              if !Node.gen3_entry_folder?(response['self']) || only_path
                @node_path_prefix&.remove_in_object_list!([response['self']])
                return Result::SingleObject.new(response['self'])
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
              RestParameters.instance.spinner_cb.call(all_items.count)
            end
            query.delete('skip')
          end
          @node_path_prefix&.remove_in_object_list!(all_items)
          return Result::ObjectList.new(all_items)
        ensure
          RestParameters.instance.spinner_cb.call(action: :success)
        end

        # Create async transfer spec request from direction and folders
        # @param sync_direction [Symbol] one of push pull bidi
        # @param local_path     [String] local folder to sync
        # @param remote_path    [String] remote folder to sync
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
            paths_to_delete = options.get_next_argument('file list', multiple: true)
            @node_path_prefix&.add_to_paths!(paths_to_delete)
            resp = @api_node.create('files/delete', {paths: paths_to_delete.map{ |i| {'path' => i.start_with?('/') ? i : "/#{i}"}}})
            return cli_result_from_paths_response(resp, 'file deleted')
          when :search
            search_root = options.get_next_argument('search root', validation: String)
            search_root = @node_path_prefix.add_to_path(search_root) unless @node_path_prefix.nil?
            parameters = {'path' => search_root}
            other_options = options.get_option(:query)
            parameters.merge!(other_options) unless other_options.nil?
            resp = @api_node.create('files/search', parameters)
            return Result::Empty.new if resp['items'].empty?
            fields = resp['items'].first.keys.reject{ |i| SEARCH_REMOVE_FIELDS.include?(i)}
            formatter.display_item_count(resp['item_count'], resp['total_count'])
            formatter.display_status("params: #{resp['parameters'].keys.map{ |k| "#{k}:#{resp['parameters'][k]}"}.join(',')}")
            @node_path_prefix&.remove_in_object_list!(resp['items'])
            return Result::ObjectList.new(resp['items'], fields: fields)
          when :space
            path_list = options.get_next_argument('folder path or ext.val. list', multiple: true)
            @node_path_prefix&.add_to_paths!(path_list)
            resp = @api_node.create('space', {'paths' => path_list.map{ |i| {path: i}}})
            @node_path_prefix&.remove_in_object_list!(resp['paths'])
            return Result::ObjectList.new(resp['paths'])
          when :mkdir
            path_list = options.get_next_argument('folder path or ext.val. list', multiple: true)
            @node_path_prefix&.add_to_paths!(path_list)
            resp = @api_node.create('files/create', {'paths' => path_list.map{ |i| {type: :directory, path: i}}})
            return cli_result_from_paths_response(resp, 'folder created')
          when :mklink
            target = options.get_next_argument('target', validation: String)
            target = @node_path_prefix.add_to_path(target) unless @node_path_prefix.nil?
            one_path = options.get_next_argument('link path', validation: String)
            one_path = @node_path_prefix.add_to_path(one_path) unless @node_path_prefix.nil?
            resp = @api_node.create('files/create', {'paths' => [{type: :symbolic_link, path: one_path, target: {path: target}}]})
            return cli_result_from_paths_response(resp, 'link created')
          when :mkfile
            one_path = options.get_next_argument('file path', validation: String)
            one_path = @node_path_prefix.add_to_path(one_path) unless @node_path_prefix.nil?
            contents64 = Base64.strict_encode64(options.get_next_argument('contents'))
            resp = @api_node.create('files/create', {'paths' => [{type: :file, path: one_path, contents: contents64}]})
            return cli_result_from_paths_response(resp, 'file created')
          when :rename
            # TODO: multiple ?
            path_base = options.get_next_argument('path_base', validation: String)
            path_base = @node_path_prefix.add_to_path(path_base) unless @node_path_prefix.nil?
            path_src = options.get_next_argument('path_src', validation: String)
            path_src = @node_path_prefix.add_to_path(path_src) unless @node_path_prefix.nil?
            path_dst = options.get_next_argument('path_dst', validation: String)
            path_dst = @node_path_prefix.add_to_path(path_dst) unless @node_path_prefix.nil?
            resp = @api_node.create('files/rename', {'paths' => [{'path' => path_base, 'source' => path_src, 'destination' => path_dst}]})
            return cli_result_from_paths_response(resp, 'entry moved')
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
            return Runner.result_transfer(transfer.start(transfer_spec))
          when :cat
            remote_path = options.get_next_argument('remote path', validation: String)
            remote_path = @node_path_prefix.add_to_path(remote_path) unless @node_path_prefix.nil?
            http = @api_node.read("files/#{URI.encode_www_form_component(remote_path)}/contents", ret: :resp)
            return Result::Text.new(http.body)
          when :transport
            return Result::SingleObject.new(@api_node.transport_params)
          when :spec
            return Result::SingleObject.new(@api_node.base_spec, fields: Formatter.all_but(Transfer::Spec::SPECIFIC))
          end
          Aspera.error_unreachable_line
        end

        # Allows to specify a file by its path or by its id on the node in command line
        # @return [NodeFileId] api and main file id for given path or id in next argument
        def apifid_from_next_arg(top_file_id)
          file_path = options.instance_identifier(description: 'path or %id:<id> or %id:') do |attribute, value|
            raise BadArgument, 'Only selection "id" is supported (file id)' unless attribute.eql?('id')
            # Directly return result for method
            return Api::NodeFileId.new(@api_node, value)
          end
          # There was no selector, so it is a path
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
            # Delegate to a new Node instance pointing at the resolved node API.
            # Since command_legacy was already consumed from the argument stream,
            # we dispatch it directly on the target instance.
            v3_node = Node.new(context: context, api: apifid.node_api)
            return v3_node.dispatch_v3_command(command_legacy)
          when :node_info, :bearer_token_node
            apifid = apifid_from_next_arg(top_file_id)
            result = {
              url:     apifid.node_api.base_url,
              root_id: apifid.file_id
            }
            case apifid.node_api.auth_params[:type]
            when :basic
              result[:username] = apifid.node_api.auth_params[:username]
              result[:password] = apifid.node_api.auth_params[:password]
            when :oauth2
              result[:username] = apifid.node_api.params[:headers][Api::Node::HEADER_X_ASPERA_ACCESS_KEY]
              result[:password] = apifid.node_api.oauth.authorization
            else Aspera.error_unexpected_value(apifid.node_api.auth_params[:type]){'Node API Auth type'}
            end
            return Result::SingleObject.new(result) if command_repo.eql?(:node_info)
            Log.dump(:result, result)
            raise BadArgument, "Cannot get bearer token if authenticating with secret (#{apifid.node_api.auth_params[:type]})" unless apifid.node_api.auth_params[:type].eql?(:oauth2)
            Aspera.assert(OAuth::Factory.bearer_auth?(result[:password]), 'Not using bearer token auth')
            return Result::Text.new(result[:password])
          when :browse
            apifid = apifid_from_next_arg(top_file_id)
            file_info = apifid.node_api.read("files/#{apifid.file_id}", headers: Api::Node.add_cache_control)
            # a single file
            return Result::ObjectList.new([file_info], fields: GEN4_LS_FIELDS) unless file_info['type'].eql?('folder')
            return Result::ObjectList.new(apifid.node_api.list_files(apifid.file_id, query: query_read_delete), fields: GEN4_LS_FIELDS)
          when :find
            apifid = apifid_from_next_arg(top_file_id)
            find_lambda = Api::Node.file_matcher_from_argument(options)
            return Result::ObjectList.new(@api_node.find_files(apifid.file_id, find_lambda), fields: ['path'])
          when :mkdir, :mklink, :mkfile
            containing_folder_path, new_item = Api::Node.split_folder(options.get_next_argument('path'))
            apifid = @api_node.resolve_api_fid(top_file_id, containing_folder_path, true)
            query = options.get_option(:query)
            check_exists = true
            payload = {name: new_item}
            if query
              check_exists = !query.delete('check').eql?(false)
              target = query.delete('target')
              if target
                target_apifid = @api_node.resolve_api_fid(top_file_id, target, true)
                payload[:target_id] = target_apifid.file_id
              end
              payload.merge!(query.symbolize_keys)
            end
            if check_exists
              folder_content = apifid.node_api.read("files/#{apifid.file_id}/files")
              link_name = ".#{new_item}.asp-lnk"
              found = folder_content.find{ |i| i['name'].eql?(new_item) || i['name'].eql?(link_name)}
              raise Cli::Error, "A #{found['type']} already exists with name #{new_item}" if found
            end
            case command_repo
            when :mkdir
              payload[:type] = :folder
            when :mklink
              payload[:type] = :link
              Aspera.assert(payload[:target_id], 'Missing target_id')
              Aspera.assert(payload[:target_node_id], 'Missing target_node_id')
            when :mkfile
              payload[:type] = :file
              payload[:contents] = Base64.strict_encode64(options.get_next_argument('contents'))
            end
            result = apifid.node_api.create("files/#{apifid.file_id}/files", payload)
            return Result::SingleObject.new(result)
          when :rename
            file_path = options.get_next_argument('source path')
            apifid = @api_node.resolve_api_fid(top_file_id, file_path)
            newname = options.get_next_argument('new name')
            result = apifid.node_api.update("files/#{apifid.file_id}", {name: newname})
            return Result::Status.new("renamed to #{newname}")
          when :delete
            return do_bulk_operation(command: command_repo, descr: 'path', values: String, id_result: 'path') do |l_path|
              apifid = if (m = Options.percent_selector(l_path))
                Aspera.assert_values(m[:field], ['id'], type: BadIdentifier)
                Api::NodeFileId.new(@api_node, m[:value])
              else
                @api_node.resolve_api_fid(top_file_id, l_path)
              end
              result = apifid.node_api.delete("files/#{apifid.file_id}")
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
              apifid.node_api.transfer_spec_gen4(apifid.file_id, ts_direction)
            end
          when :upload
            apifid = @api_node.resolve_api_fid(top_file_id, transfer.destination_folder(Transfer::Spec::DIRECTION_SEND), true)
            return Runner.result_transfer(transfer.start(apifid.node_api.transfer_spec_gen4(apifid.file_id, Transfer::Spec::DIRECTION_SEND)))
          when :download
            apifid, source_paths = @api_node.resolve_api_fid_paths(top_file_id, transfer.ts_source_paths)
            return Runner.result_transfer(transfer.start(apifid.node_api.transfer_spec_gen4(apifid.file_id, Transfer::Spec::DIRECTION_RECEIVE, {'paths'=>source_paths})))
          when :cat
            apifid = apifid_from_next_arg(top_file_id)
            http = apifid.node_api.read("files/#{apifid.file_id}/content", ret: :resp)
            return Result::Text.new(http.body)
          when :show
            apifid = apifid_from_next_arg(top_file_id)
            items = apifid.node_api.read("files/#{apifid.file_id}")
            return Result::SingleObject.new(items)
          when :modify
            apifid = apifid_from_next_arg(top_file_id)
            update_param = options.get_next_argument('update data', validation: Hash)
            apifid.node_api.update("files/#{apifid.file_id}", update_param)
            return Result::Status.new('Done')
          when :thumbnail
            apifid = apifid_from_next_arg(top_file_id)
            http = apifid.node_api.read("files/#{apifid.file_id}/preview", headers: {'Accept' => 'image/png'}, ret: :resp)
            return Result::Image.new(http.body)
          when :permission
            # :permission is now a DSL sub-tree; re-enter the registry at [:access_keys, :do, :permission]
            # passing apifid resolved from the next argument via setup_permission.
            apifid = apifid_from_next_arg(top_file_id)
            dispatch_from_registry(%i[access_keys do permission], {apifid: apifid})
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
          raise Cli::BadIdentifier.new('sync', value, field: field) if selected.nil?
          return selected['snid']
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
          raise Cli::BadIdentifier.new('ssync', value, field: field)
        end

        # --- DSL command declarations ---

        # Gen3 leaf commands
        command :search,      description: 'Search for files'
        command :space,       description: 'Show space information'
        command :mkdir,       description: 'Create a folder (Gen3)'
        command :mklink,      description: 'Create a symbolic link (Gen3)'
        command :mkfile,      description: 'Create a file (Gen3)'
        command :rename,      description: 'Rename a file or folder (Gen3)'
        command :delete,      description: 'Delete files or folders (Gen3)'
        command :browse,      description: 'Browse files (Gen3)'
        command :upload,      description: 'Upload files (Gen3)'
        command :download,    description: 'Download files (Gen3)'
        command :cat,         description: 'Show file contents (Gen3)'
        command :sync,        description: 'Synchronize folders (Gen3)'
        command :transport,   description: 'Show transport parameters'
        command :spec,        description: 'Show transfer spec base'
        # Other common leaf commands
        command :api_details, description: 'Show API details',
          handler: ->{Result::SingleObject.new({base_url: @api_node.base_url}.merge(@api_node.params))}
        command :health,      description: 'Check node health'
        command :events,      description: 'List events',
          handler: ->{Result::ObjectList.new(@api_node.read('events', query_read_delete), fields: ->(f){!f.start_with?('data')})}
        command :info,        description: 'Show node info',
          handler: ->{Result::SingleObject.new(@api_node.read('info'))}
        command :slash,       description: 'Show root info',
          handler: ->{Result::SingleObject.new(@api_node.read(''))}
        command :license,     description: 'Show license',
          handler: ->{Result::SingleObject.new(@api_node.read('license'))}
        # access_keys sub-tree
        command :access_keys, description: 'Manage access keys'
        commands_under(:access_keys) do
          command :do, description: 'Execute Gen4 command via access key', setup: :setup_access_key_do
          command :set_bearer_key, description: 'Set bearer key on access key'
          Operations::ALL.each{ |op| command(op, description: "#{op.capitalize} access key(s)")}
        end

        commands_under(%i[access_keys do]) do
          COMMANDS_GEN4.each do |cmd|
            command(cmd, description: "Gen4 #{cmd} command")
          end
        end
        commands_under(%i[access_keys do permission]) do
          command :list,   description: 'List permissions on a file'
          command :show,   description: 'Show a permission',
            handler: ->(apifid:, **){Result::SingleObject.new(apifid.node_api.read("permissions/#{options.instance_identifier}"))}
          command :create, description: 'Create a permission'
          command(:modify, description: 'Modify a permission', handler: lambda do |apifid:, **|
            apifid.node_api.update("permissions/#{options.instance_identifier}", value_create_modify(command: 'permission modify'))
            Result::Status.new('Updated')
          end)
          command :delete, description: 'Delete permission(s)'
        end
        # async (legacy /async)
        command :async, description: 'Manage async operations (legacy /async)'
        commands_under(:async) do
          command :list,      description: 'List async sync IDs'
          command :show,      description: 'Show async summary'
          command :delete,    description: 'Delete async'
          command :bandwidth, description: 'Show async bandwidth'
          command :files,     description: 'List async files'
          command :counters,  description: 'Show async counters'
        end
        # ssync (/asyncs)
        command :ssync, description: 'Manage sync operations (/asyncs)'
        commands_under(:ssync) do
          command :start,     description: 'Start a sync'
          command :stop,      description: 'Stop a sync'
          command :bandwidth, description: 'Show sync bandwidth'
          command :counters,  description: 'Show sync counters'
          command :files,     description: 'List sync files'
          command :state,     description: 'Show sync state'
          command :summary,   description: 'Show sync summary'
          Operations::ALL.reject{ |op| op == :modify}.each{ |op| command(op, description: "#{op.capitalize} ssync")}
        end
        # stream
        command :stream, description: 'Manage stream operations'
        commands_under(:stream) do
          command :list,   description: 'List streams'
          command :create, description: 'Create a stream'
          command :show,   description: 'Show a stream'
          command :modify, description: 'Modify a stream'
          command :cancel, description: 'Cancel a stream'
        end
        # transfer
        command :transfer, description: 'Manage transfer operations'
        commands_under(:transfer) do
          command :list,              description: 'List transfers'
          command :cancel,            description: 'Cancel a transfer'
          command :show,              description: 'Show a transfer'
          command :modify,            description: 'Modify a transfer'
          command :bandwidth_average, description: 'Show average bandwidth per period'
          command :sessions,          description: 'List transfer sessions'
        end
        # service
        command :service, description: 'Manage services'
        commands_under(:service) do
          command :list,   description: 'List services'
          command :create, description: 'Create a service'
          command :delete, description: 'Delete a service'
        end
        # watch_folder
        command :watch_folder, description: 'Manage watch folders', setup: :setup_watch_folder
        commands_under(:watch_folder) do
          command :create, description: 'Create a watch folder',
            handler: ->{Result::Status.new("#{@api_node.create('v3/watchfolders', value_create_modify(command: :create))['id']} created")}
          command :list,   description: 'List watch folders',
            handler: ->{Result::ValueList.new(@api_node.read('v3/watchfolders', query_read_delete)['ids'])}
          command :show,   description: 'Show a watch folder',
            handler: ->{Result::SingleObject.new(@api_node.read("v3/watchfolders/#{options.instance_identifier}"))}
          command :modify, description: 'Modify a watch folder'
          command :delete, description: 'Delete a watch folder'
          command :state,  description: 'Show watch folder state',
            handler: ->{Result::SingleObject.new(@api_node.read("v3/watchfolders/#{options.instance_identifier}/state"))}
        end
        # central
        command :central, description: 'Query Central service'
        commands_under(:central) do
          command :session, description: 'Query sessions'
          command :file,    description: 'Query files'
        end
        commands_under(%i[central session]){command :list, description: 'List sessions'}
        commands_under(%i[central file]) do
          command :list,   description: 'List file transfers'
          command :modify, description: 'Modify file transfer validation'
        end
        # Standalone leaf commands
        command :asperabrowser, description: 'Open Aspera browser'
        command :basic_token,   description: 'Generate basic auth token'
        command :bearer_token,  description: 'Generate bearer token'
        command :simulator,     description: 'Start node simulator'
        command :telemetry,     description: 'Report telemetry to external system'

        # --- Handler methods ---

        # Gen3 leaf commands: dispatch to execute_command_gen3
        COMMANDS_GEN3.each{ |cmd| define_method(:"handle_#{cmd}"){execute_command_gen3(cmd)}}
        def handle_health
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
              content_type: Mime::TEXT,
              body:         CENTRAL_SOAP_API_TEST,
              headers:      {'Content-Type' => 'text/xml;charset=UTF-8', 'SOAPAction' => 'FASPSessionNET-200911#GetSessionInfo'},
              ret:          :resp
            ).body
            nagios.add_ok('central', 'accessible by node')
          rescue StandardError => e
            nagios.add_critical('central', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        # watch_folder setup: inject required API header (avoids "Unable to convert 2016_09_14 configuration")
        def setup_watch_folder
          @api_node.params[:headers] ||= {}
          @api_node.params[:headers]['X-aspera-WF-version'] = '2017_10_23'
          {}
        end

        def handle_watch_folder_modify
          one_res_id = options.instance_identifier
          @api_node.update("v3/watchfolders/#{one_res_id}", value_create_modify(command: :watch_folder))
          Result::Status.new("#{one_res_id} updated")
        end

        def handle_watch_folder_delete
          one_res_id = options.instance_identifier
          @api_node.delete("v3/watchfolders/#{one_res_id}")
          Result::Status.new("#{one_res_id} deleted")
        end

        # access_keys > CRUD
        Operations::ALL.each do |op|
          define_method(:"handle_access_keys_#{op}") do
            entity_execute(api: @api_node, entity: 'access_keys', command: op) do |field, value|
              raise BadArgument, 'only selector: %id:self' unless field.eql?('id') && value.eql?('self')
              @api_node.read('access_keys/self')['id']
            end
          end
        end

        # access_keys > do — setup: resolve access key and root file id
        # @return [Hash] context hash containing :do_root_file_id
        def setup_access_key_do
          access_key_id = options.get_next_argument('access key id')
          root_file_id = options.get_option(:root_id)
          if root_file_id.nil?
            ak_info = @api_node.read("access_keys/#{access_key_id}")
            ak_secret = context.secret_finder.lookup(url: @api_node.base_url, username: ak_info['id'])
            if !access_key_id.eql?('self')
              Aspera.assert(ak_secret, type: Cli::MissingArgument){"Please provide secret for #{ak_info['id']} using option: secret or by setting a preset for #{ak_info['id']}@#{@api_node.base_url}."}
              @api_node.auth_params[:username] = ak_info['id']
              @api_node.auth_params[:password] = ak_secret
            end
            root_file_id = ak_info['root_file_id']
          end
          {do_root_file_id: root_file_id}
        end

        # access_keys > do > <gen4_cmd> — one handler per COMMANDS_GEN4
        COMMANDS_GEN4.each do |cmd|
          define_method(:"handle_access_keys_do_#{cmd}") do |do_root_file_id:|
            execute_command_gen4(cmd, do_root_file_id)
          end
        end

        # access_keys > do > permission > list/show/create/modify/delete
        def handle_access_keys_do_permission_list(apifid:, **)
          list_query = query_read_delete(default: Rest.php_style({'include' => %w[access_level permission_count]}))
          # Specify file to get permissions for unless not specified (then, get all permissions)
          list_query['file_id'] = apifid.file_id unless apifid.file_id.to_s.empty?
          list_query['inherited'] = false if list_query.key?('file_id') && !list_query.key?('inherited')
          Result::ObjectList.new(apifid.node_api.read_with_pages('permissions', list_query))
        end

        def handle_access_keys_do_permission_delete(apifid:, **)
          do_bulk_operation(command: :delete, values: :identifier) do |one_id|
            apifid.node_api.delete("permissions/#{one_id}")
            the_app = apifid.node_api.app_info
            the_app&.api&.permissions_send_event(event_data: {}, app_info: the_app, types: ['permission.deleted'])
            {'id' => one_id}
          end
        end

        def handle_access_keys_do_permission_create(apifid:, **)
          create_param = options.get_next_argument('creation data', validation: Hash)
          raise Cli::BadArgument, 'no file_id' if create_param.key?('file_id')
          create_param['file_id'] = apifid.file_id
          create_param['access_levels'] = Api::Node::ACCESS_LEVELS unless create_param.key?('access_levels')
          the_app = apifid.node_api.app_info
          the_app&.api&.permissions_set_create_params(perm_data: create_param, app_info: the_app)
          created_data = apifid.node_api.create('permissions', create_param)
          the_app&.api&.permissions_send_event(event_data: created_data, app_info: the_app)
          Result::SingleObject.new(created_data)
        end

        # access_keys > set_bearer_key
        def handle_access_keys_set_bearer_key
          access_key_id = options.get_next_argument('access key id')
          access_key_id = @api_node.read('access_keys/self')['id'] if access_key_id.eql?('self')
          bearer_key_pem = options.get_next_argument('public or private RSA key PEM value', validation: String)
          key = OpenSSL::PKey.read(bearer_key_pem)
          key = key.public_key if key.private?
          @api_node.update("access_keys/#{access_key_id}", {token_verification_key: key.to_pem})
          Result::Status.new('public key updated')
        end

        # async sub-commands: individual handlers
        def handle_async_list
          Result::ValueList.new(@api_node.read('async/list')['sync_ids'])
        end

        def handle_async_show
          async_id = options.instance_identifier{ |field, value| async_lookup(field, value)}
          async_ids = @api_node.read('async/list')['sync_ids']
          if async_id.eql?(SpecialValues::ALL)
            resp = @api_node.create('async/summary', {'syncs' => async_ids})['sync_summaries']
            return Result::Empty.new if resp.empty?
            return Result::ObjectList.new(resp, fields: %w[snid name local_dir remote_dir])
          end
          Integer(async_id)
          resp = @api_node.create('async/summary', {'syncs' => [async_id]})['sync_summaries']
          return Result::Empty.new if resp.empty?
          Result::SingleObject.new(resp.first)
        end

        def handle_async_delete
          async_id = options.instance_identifier{ |field, value| async_lookup(field, value)}
          async_ids = async_id.eql?(SpecialValues::ALL) ? @api_node.read('async/list')['sync_ids'] : [async_id]
          Result::SingleObject.new(@api_node.create('async/delete', {'syncs' => async_ids}))
        end

        def handle_async_bandwidth
          async_id = options.instance_identifier{ |field, value| async_lookup(field, value)}
          Integer(async_id)
          post_data = {'syncs' => [async_id], 'seconds' => 100}
          resp = @api_node.create('async/bandwidth', post_data)
          data = resp['bandwidth_data']
          return Result::Empty.new if data.empty?
          Result::ObjectList.new(data.first[async_id]['data'])
        end

        def handle_async_files
          async_id = options.instance_identifier{ |field, value| async_lookup(field, value)}
          Integer(async_id)
          post_data = {'syncs' => [async_id]}
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
              id:      IdGenerator.from_list('sync_files', options.get_option(:url, mandatory: true), options.get_option(:username, mandatory: true), async_id)
            )
            data.select!{ |l| l['fnid'].to_i > iteration_data.first} unless iteration_data.first.nil?
            iteration_data[0] = data.last['fnid'].to_i unless data.empty?
          end
          return Result::Empty.new if data.empty?
          skip_ids_persistency&.save
          Result::ObjectList.new(data)
        end

        def handle_async_counters
          async_id = options.instance_identifier{ |field, value| async_lookup(field, value)}
          Integer(async_id)
          resp = @api_node.create('async/counters', {'syncs' => [async_id]})['sync_counters'].first[async_id].last
          return Result::Empty.new if resp.nil?
          Result::SingleObject.new(resp)
        end

        # ssync CRUD
        Operations::ALL.reject{ |op| op == :modify}.each do |op|
          define_method(:"handle_ssync_#{op}") do
            entity_execute(api: @api_node, entity: :asyncs, command: op, items_key: 'ids'){ |f, v| ssync_lookup(f, v)}
          end
        end

        # ssync start/stop
        %i[start stop].each do |action|
          define_method(:"handle_ssync_#{action}") do
            asyncs_id = options.instance_identifier{ |f, v| ssync_lookup(f, v)}
            @api_node.call(operation: 'POST', subpath: "asyncs/#{asyncs_id}/#{action}", content_type: Mime::TEXT, body: '', ret: :resp).body
            Result::Status.new('Done')
          end
        end

        # ssync info sub-commands
        %i[bandwidth counters files state summary].each do |action|
          define_method(:"handle_ssync_#{action}") do
            asyncs_id = options.instance_identifier{ |f, v| ssync_lookup(f, v)}
            parameters = SSYNC_WITH_PARAMS_ACTIONS.include?(action) ? (options.get_option(:query) || {}) : nil
            Result::SingleObject.new(@api_node.read("asyncs/#{asyncs_id}/#{action}", parameters))
          end
        end

        # stream sub-commands
        def handle_stream_list
          Result::ObjectList.new(@api_node.read('ops/transfers', query_read_delete), fields: %w[id status])
        end

        def handle_stream_create
          Result::SingleObject.new(@api_node.create('streams', value_create_modify(command: :create)))
        end

        def handle_stream_show
          Result::SingleObject.new(@api_node.read("ops/transfers/#{options.get_next_argument('transfer id')}"))
        end

        def handle_stream_modify
          Result::SingleObject.new(@api_node.update("streams/#{options.get_next_argument('transfer id')}", value_create_modify(command: :modify)))
        end

        def handle_stream_cancel
          Result::SingleObject.new(@api_node.cancel("streams/#{options.get_next_argument('transfer id')}"))
        end

        # transfer sub-commands
        def handle_transfer_list
          transfer_filter = query_read_delete(default: {})
          iteration_persistency = nil
          if options.get_option(:once_only, mandatory: true)
            iteration_persistency = PersistencyActionOnce.new(
              manager: persistency,
              data:    [],
              id:      IdGenerator.from_list('node_transfers', options.get_option(:url, mandatory: true), options.get_option(:username, mandatory: true))
            )
            if transfer_filter.delete('reset')
              iteration_persistency.data.clear
              iteration_persistency.save
              return Result::Status.new('Persistency reset')
            end
          else
            Aspera.assert(!transfer_filter.key?('reset'), 'reset only with once_only', type: Cli::BadArgument)
          end
          transfers_data = @api_node.read_with_paging('ops/transfers', transfer_filter, iteration: iteration_persistency&.data)
          iteration_persistency&.save
          Result::ObjectList.new(transfers_data, fields: %w[id status start_spec.direction start_spec.remote_user start_spec.remote_host start_spec.destination_path])
        end

        def handle_transfer_sessions
          transfers_data = @api_node.read('ops/transfers', query_read_delete)
          sessions = transfers_data.flat_map{ |t| t['sessions']}
          sessions.each do |session|
            SESSION_TIME_FIELDS.each do |what|
              session["#{what}_time"] = session["#{what}_time_usec"] ? Time.at(session["#{what}_time_usec"] / 1_000_000.0).utc.iso8601(0) : nil
            end
          end
          Result::ObjectList.new(sessions, fields: %w[id status start_time end_time target_rate_kbps])
        end

        def handle_transfer_cancel
          @api_node.cancel("ops/transfers/#{options.instance_identifier}")
          Result::Status.new('Cancelled')
        end

        def handle_transfer_show
          Result::SingleObject.new(@api_node.read("ops/transfers/#{options.instance_identifier}"))
        end

        def handle_transfer_modify
          @api_node.update("ops/transfers/#{options.instance_identifier}", options.get_next_argument('update value', validation: Hash))
          Result::Status.new('Modified')
        end

        def handle_transfer_bandwidth_average
          transfers_data = @api_node.read('ops/transfers', query_read_delete)
          bandwidth_period = {}
          dir_info = %i[avg_kbps sessions].freeze
          transfers_data.each do |t|
            next if t['avg_rate_kbps'].zero?
            bandwidth_period[t['start_time_usec']] = 0
            bandwidth_period[t['end_time_usec']] = 0
          end
          result = []
          all_dates = bandwidth_period.keys.sort
          all_dates.each_with_index do |start_date, index|
            end_date = all_dates[index + 1]
            break if end_date.nil?
            period_bandwidth = Transfer::Spec::DIRECTION_ENUM_VALUES.map(&:to_sym).to_h do |dir|
              [dir, dir_info.to_h{ |k2| [k2, 0]}]
            end
            transfers_data.each do |t|
              next if t['avg_rate_kbps'].zero?
              next if t['start_time_usec'] >= end_date || t['end_time_usec'] <= start_date
              info = period_bandwidth[t['start_spec']['direction'].to_sym]
              info[:avg_kbps] += t['avg_rate_kbps']
              info[:sessions] += 1
            end
            next if Transfer::Spec::DIRECTION_ENUM_VALUES.map(&:to_sym).all?{ |dir| period_bandwidth[dir][:sessions].zero?}
            result.push({start: Time.at(start_date / 1_000_000), end: Time.at(end_date / 1_000_000)}.merge(period_bandwidth))
          end
          Result::ObjectList.new(result)
        end

        # service sub-commands
        def handle_service_list
          Result::ObjectList.new(@api_node.read('rund/services')['services'])
        end

        def handle_service_create
          resp = @api_node.create('rund/services', options.get_next_argument('creation data', validation: Hash))
          Result::Status.new("#{resp['id']} created")
        end

        def handle_service_delete
          service_id = options.instance_identifier
          @api_node.delete("rund/services/#{service_id}")
          Result::Status.new("#{service_id} deleted")
        end

        # central: shared helper
        def central_validation
          validator_id = options.get_option(:validator)
          validator_id ? {'validator_id' => validator_id} : nil
        end

        # central > session > list
        def handle_central_session_list
          validation = central_validation
          request_data = options.get_next_argument('request data', mandatory: false, validation: Hash, default: {})
          request_data.deep_merge!({'validation' => validation}) unless validation.nil?
          resp = @api_node.create('services/rest/transfers/v1/sessions', request_data)
          Result::ObjectList.new(resp['session_info_result']['session_info'], fields: %w[session_uuid status transport direction bytes_transferred])
        end

        # central > file > list
        def handle_central_file_list
          validation = central_validation
          request_data = options.get_next_argument('request data', mandatory: false, validation: Hash, default: {})
          request_data.deep_merge!({'validation' => validation}) unless validation.nil?
          resp = @api_node.create('services/rest/transfers/v1/files', request_data)
          resp = JSON.parse(resp) if resp.is_a?(String)
          Log.dump(:resp, resp)
          Result::ObjectList.new(resp['file_transfer_info_result']['file_transfer_info'], fields: %w[session_uuid file_id status path])
        end

        # central > file > modify
        def handle_central_file_modify
          validation = central_validation
          request_data = options.get_next_argument('request data', mandatory: false, validation: Hash, default: {})
          request_data.deep_merge!(validation) unless validation.nil?
          @api_node.update('services/rest/transfers/v1/files', request_data)
          Result::Status.new('updated')
        end

        def handle_asperabrowser
          browse_params = {
            'nodeUser' => options.get_option(:username, mandatory: true),
            'nodePW'   => options.get_option(:password, mandatory: true),
            'nodeURL'  => options.get_option(:url, mandatory: true)
          }
          # encode parameters so that it looks good in url
          encoded_params = Base64.strict_encode64(Zlib::Deflate.deflate(JSON.generate(browse_params))).gsub(/=+$/, '').tr('+/', '-_').reverse
          Environment.instance.open_uri("#{options.get_option(:asperabrowserurl)}?goto=#{encoded_params}")
          return Result::Status.new('done')
        end

        def handle_basic_token
          return Result::Text.new(Rest.basic_authorization(options.get_option(:username, mandatory: true), options.get_option(:password, mandatory: true)))
        end

        def handle_bearer_token
          private_key = OpenSSL::PKey::RSA.new(options.get_next_argument('private RSA key PEM value', validation: String))
          token_info = options.get_next_argument('user and group identification', validation: Hash)
          access_key = options.get_option(:username, mandatory: true)
          return Result::Text.new(Api::Node.bearer_token(payload: token_info, access_key: access_key, private_key: private_key))
        end

        def handle_simulator
          require 'aspera/node_simulator'
          parameters = value_create_modify(command: :simulator, default: {}).symbolize_keys
          uri = URI.parse(parameters.delete(:url){WebServerSimple::DEFAULT_URL})
          server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
          server.mount(uri.path, NodeSimulatorServlet, parameters.except(*WebServerSimple::PARAMS), NodeSimulator.new)
          server.start
          return Result::Status.new('Simulator terminated')
        end

        def handle_telemetry
          parameters = value_create_modify(command: :telemetry, default: {}).symbolize_keys
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
            transfers_data = @api_node.read_with_paging('ops/transfers', {active_only: true})
            datapoint[:asInt] = transfers_data.length
            datapoint[:timeUnixNano] = timestamp.to_i * 1_000_000_000 + timestamp.nsec
            Log.log.info("#{datapoint[:asInt]} active transfers")
            # https://www.ibm.com/docs/en/instana-observability/current?topic=instana-backend
            otel_api.create('metrics', metrics)
            break if interval.eql?(0.0)
            sleep([0.0, interval - (Time.now - timestamp)].max)
          end
        end

        # Dispatch a command that has already been read from the argument stream.
        # Used when a new Node instance is created and the command was already consumed
        # (e.g., :v3 delegation, shares, cos, faspex).
        # Re-enters the DSL registry for sub-trees, or calls directly for leaf commands.
        # @param command [Symbol] command already consumed from the argument stream
        # @return [Object] CLI result
        def dispatch_v3_command(command)
          case command
          when *COMMANDS_GEN3
            # Gen3 leaf: execute directly
            execute_command_gen3(command)
          when :health, :events, :info, :slash, :license, :api_details
            # Common leaf commands — delegate to the named handler directly
            send(:"handle_#{command}")
          when :access_keys, :transfer
            # Sub-trees: re-enter DSL registry at the matching path so the
            # next argument is consumed normally by the dispatcher.
            dispatch_from_registry([command], {})
          else
            Aspera.error_unexpected_value(command){'v3 command'}
          end
        end

        private

        # Response has key `paths`.
        # From those, check if there is an error
        # @return [Array<Hash>] list of hashes with 2 keys: `path` and `result`
        def response_to_result(response, success_msg)
          errors = []
          obj_list = []
          response['paths'].each do |p|
            result = success_msg
            if p.key?('error')
              Log.log.error{"#{p['error']['user_message']} : #{p['path']}"}
              result = p['error']['user_message']
              errors.push([p['path'], p['error']['user_message']])
            end
            obj_list.push({'path' => p['path'], 'result' => result})
          end
          # one error make all fail
          raise errors.map{ |i| "#{i.first}: #{i.last}"}.join(', ') unless errors.empty?
          obj_list
        end

        # Translates paths results into CLI result, and removes prefix
        def cli_result_from_paths_response(response, success_msg)
          obj_list = response_to_result(response, success_msg)
          @node_path_prefix&.remove_in_object_list!(obj_list)
          return Result::ObjectList.new(obj_list, fields: %w[path result])
        end
      end
    end
  end
end
