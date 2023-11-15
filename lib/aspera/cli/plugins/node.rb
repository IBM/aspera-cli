# frozen_string_literal: true

# cspell:ignore snid fnid bidi ssync asyncs rund asnodeadmin mkfile mklink asperabrowser asperabrowserurl watchfolders watchfolderd entsrv
require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/sync_actions'
require 'aspera/fasp/transfer_spec'
require 'aspera/nagios'
require 'aspera/hash_ext'
require 'aspera/id_generator'
require 'aspera/node'
require 'aspera/aoc'
require 'aspera/sync'
require 'aspera/oauth'
require 'base64'
require 'zlib'

module Aspera
  module Cli
    module Plugins
      class Node < Aspera::Cli::BasicAuthPlugin
        include SyncActions
        class << self
          @@node_options_declared = false # rubocop:disable Style/ClassVars
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

            urls.each do |base_url|
              next unless base_url.match?('https?://')
              api = Rest.new(base_url: base_url)
              test_endpoint = 'ping'
              result = api.call(operation: 'GET', subpath: test_endpoint)
              next unless result[:http].body.eql?('')
              url_length = -2 - test_endpoint.length
              return {
                url: result[:http].uri.to_s[0..url_length]
              }
            rescue StandardError => e
              Log.log.debug{"detect error: #{e}"}
            end
            return nil
          end

          def wizard(object:, private_key_path: nil, pub_key_pem: nil)
            options = object.options
            return {
              preset_value: {
                url:      options.get_option(:url, mandatory: true),
                username: options.get_option(:username, mandatory: true),
                password: options.get_option(:password, mandatory: true)
              },
              test_args:    'info'
            }
          end

          def declare_options(options, force: false)
            return if @@node_options_declared && !force
            @@node_options_declared = true # rubocop:disable Style/ClassVars
            options.declare(:validator, 'Identifier of validator (optional for central)')
            options.declare(:asperabrowserurl, 'URL for simple aspera web ui', default: 'https://asperabrowser.mybluemix.net')
            options.declare(:sync_name, 'Sync name')
            options.declare(
              :default_ports, 'Use standard FASP ports or get from node api (gen4)', values: :bool, default: :yes,
              handler: {o: Aspera::Node, m: :use_standard_ports})
            options.declare(:root_id, 'File id of top folder if using bearer tokens')
            SyncActions.declare_options(options)
            options.parse_options!
          end
        end

        # spellchecker: disable
        # SOAP API call to test central API
        CENTRAL_SOAP_API_TEST = '<?xml version="1.0" encoding="UTF-8"?>' \
          '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="urn:Aspera:XML:FASPSessionNET:2009/11:Types">' \
          '<soapenv:Header></soapenv:Header>' \
          '<soapenv:Body><typ:GetSessionInfoRequest><SessionFilter><SessionStatus>running</SessionStatus></SessionFilter></typ:GetSessionInfoRequest></soapenv:Body>' \
          '</soapenv:Envelope>'
        # spellchecker: enable

        # fields removed in result of search
        SEARCH_REMOVE_FIELDS = %w[basename permissions].freeze

        # actions in execute_command_gen3
        COMMANDS_GEN3 = %i[search space mkdir mklink mkfile rename delete browse upload download http_node_download sync]

        BASE_ACTIONS = %i[api_details].concat(COMMANDS_GEN3).freeze

        SPECIAL_ACTIONS = %i[health events info slash license].freeze

        # actions available in v3 in gen4
        V3_IN_V4_ACTIONS = %i[access_keys].concat(BASE_ACTIONS).concat(SPECIAL_ACTIONS).freeze

        # actions used commonly when a node is involved
        COMMON_ACTIONS = %i[access_keys].concat(BASE_ACTIONS).concat(SPECIAL_ACTIONS).freeze

        private_constant(*%i[CENTRAL_SOAP_API_TEST SEARCH_REMOVE_FIELDS BASE_ACTIONS SPECIAL_ACTIONS V3_IN_V4_ACTIONS COMMON_ACTIONS])

        # used in aoc
        NODE4_READ_ACTIONS = %i[bearer_token_node node_info browse find].freeze

        # commands for execute_command_gen4
        COMMANDS_GEN4 = %i[mkdir rename delete upload download sync http_node_download show modify permission thumbnail v3].concat(NODE4_READ_ACTIONS).freeze

        COMMANDS_COS = %i[upload download info access_keys api_details transfer].freeze
        COMMANDS_SHARES = (BASE_ACTIONS - %i[search]).freeze
        COMMANDS_FASPEX = COMMON_ACTIONS

        def initialize(env, api: nil)
          super(env)
          Node.declare_options(options, force: env[:all_manuals])
          @api_node =
            if !api.nil? || env[:all_manuals]
              # this can be Aspera::Node or Aspera::Rest (shares)
              api
            elsif Oauth.bearer?(options.get_option(:password, mandatory: true))
              # info is provided like node_info of aoc
              Aspera::Node.new(params: {
                base_url: options.get_option(:url, mandatory: true),
                headers:  Aspera::Node.bearer_headers(options.get_option(:password, mandatory: true))
              })
            else
              # this is normal case
              Aspera::Node.new(params: {
                base_url: options.get_option(:url, mandatory: true),
                auth:     {
                  type:     :basic,
                  username: options.get_option(:username, mandatory: true),
                  password: options.get_option(:password, mandatory: true)
                }})
            end
        end

        # reduce the path from a result on given named column
        def c_result_remove_prefix_path(result, column, path_prefix)
          if !path_prefix.nil?
            case result[:type]
            when :object_list
              result[:data].each do |item|
                item[column] = item[column][path_prefix.length..-1] if item[column].start_with?(path_prefix)
              end
            when :single_object
              item = result[:data]
              item[column] = item[column][path_prefix.length..-1] if item[column].start_with?(path_prefix)
            end
          end
          return result
        end

        # translates paths results into CLI result, and removes prefix
        def c_result_translate_rem_prefix(response, type, success_msg, path_prefix)
          errors = []
          final_result = { data: [], type: :object_list, fields: [type, 'result']}
          JSON.parse(response[:http].body)['paths'].each do |p|
            result = success_msg
            if p.key?('error')
              Log.log.error{"#{p['error']['user_message']} : #{p['path']}"}
              result = 'ERROR: ' + p['error']['user_message']
              errors.push([p['path'], p['error']['user_message']])
            end
            final_result[:data].push({type => p['path'], 'result' => result})
          end
          # one error make all fail
          unless errors.empty?
            raise errors.map{|i|"#{i.first}: #{i.last}"}.join(', ')
          end
          return c_result_remove_prefix_path(final_result, type, path_prefix)
        end

        # get path arguments from command line, and add prefix
        def get_next_arg_add_prefix(path_prefix, name, number=:single)
          path_or_list = options.get_next_argument(name, expected: number)
          return path_or_list if path_prefix.nil?
          return File.join(path_prefix, path_or_list) if path_or_list.is_a?(String)
          return path_or_list.map {|p| File.join(path_prefix, p)} if path_or_list.is_a?(Array)
          raise StandardError, 'expect: nil, String or Array'
        end

        # file and folder related commands
        def execute_command_gen3(command, prefix_path)
          case command
          when :delete
            paths_to_delete = get_next_arg_add_prefix(prefix_path, 'file list', :multiple)
            resp = @api_node.create('files/delete', { paths: paths_to_delete.map{|i| {'path' => i.start_with?('/') ? i : '/' + i} }})
            return c_result_translate_rem_prefix(resp, 'file', 'deleted', prefix_path)
          when :search
            search_root = get_next_arg_add_prefix(prefix_path, 'search root')
            parameters = {'path' => search_root}
            other_options = query_option
            parameters.merge!(other_options) unless other_options.nil?
            resp = @api_node.create('files/search', parameters)
            result = { type: :object_list, data: resp[:data]['items']}
            return Main.result_empty if result[:data].empty?
            result[:fields] = result[:data].first.keys.reject{|i|SEARCH_REMOVE_FIELDS.include?(i)}
            formatter.display_item_count(resp[:data]['item_count'], resp[:data]['total_count'])
            formatter.display_status("params: #{resp[:data]['parameters'].keys.map{|k|"#{k}:#{resp[:data]['parameters'][k]}"}.join(',')}")
            return c_result_remove_prefix_path(result, 'path', prefix_path)
          when :space
            path_list = get_next_arg_add_prefix(prefix_path, 'folder path or ext.val. list')
            path_list = [path_list] unless path_list.is_a?(Array)
            resp = @api_node.create('space', { 'paths' => path_list.map {|i| { path: i} } })
            result = { data: resp[:data]['paths'], type: :object_list}
            # return c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
            return c_result_remove_prefix_path(result, 'path', prefix_path)
          when :mkdir
            path_list = get_next_arg_add_prefix(prefix_path, 'folder path or ext.val. list')
            path_list = [path_list] unless path_list.is_a?(Array)
            resp = @api_node.create('files/create', { 'paths' => [{ type: :directory, path: path_list }] })
            return c_result_translate_rem_prefix(resp, 'folder', 'created', prefix_path)
          when :mklink
            target = get_next_arg_add_prefix(prefix_path, 'target')
            path_list = get_next_arg_add_prefix(prefix_path, 'link path')
            resp = @api_node.create('files/create', { 'paths' => [{ type: :symbolic_link, path: path_list, target: { path: target} }] })
            return c_result_translate_rem_prefix(resp, 'folder', 'created', prefix_path)
          when :mkfile
            path_list = get_next_arg_add_prefix(prefix_path, 'file path')
            contents64 = Base64.strict_encode64(options.get_next_argument('contents'))
            resp = @api_node.create('files/create', { 'paths' => [{ type: :file, path: path_list, contents: contents64 }] })
            return c_result_translate_rem_prefix(resp, 'folder', 'created', prefix_path)
          when :rename
            path_base = get_next_arg_add_prefix(prefix_path, 'path_base')
            path_src = get_next_arg_add_prefix(prefix_path, 'path_src')
            path_dst = get_next_arg_add_prefix(prefix_path, 'path_dst')
            resp = @api_node.create('files/rename', { 'paths' => [{ 'path' => path_base, 'source' => path_src, 'destination' => path_dst }] })
            return c_result_translate_rem_prefix(resp, 'entry', 'moved', prefix_path)
          when :browse
            query = { path: get_next_arg_add_prefix(prefix_path, 'path')}
            additional_query = options.get_option(:query)
            query.merge!(additional_query) unless additional_query.nil?
            send_result = @api_node.create('files/browse', query)[:data]
            # example: send_result={'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}
            # if there is no items
            case send_result['self']['type']
            when 'directory', 'container' # directory: node, container: shares
              result = { data: send_result['items'], type: :object_list }
              formatter.display_item_count(send_result['item_count'], send_result['total_count'])
            else # 'file','symbolic_link'
              result = { data: send_result['self'], type: :single_object}
            end
            return c_result_remove_prefix_path(result, 'path', prefix_path)
          when :sync
            return execute_sync_action do |sync_direction, local_path, remote_path|
              # Gen3 API
              # empty transfer spec for authorization request
              request_transfer_spec = {
                type:  case sync_direction
                       when :push then :sync_upload
                       when :pull then :sync_download
                       when :bidi then :sync
                       end,
                paths: [{
                  source:      remote_path,
                  destination: local_path
                }]
              }
              # add fixed parameters if any (for COS)
              @api_node.add_tspec_info(request_transfer_spec) if @api_node.respond_to?(:add_tspec_info)
              # prepare payload for single request
              setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
              # only one request, so only one answer
              transfer_spec = @api_node.create('files/sync_setup', setup_payload)[:data]['transfer_specs'].first['transfer_spec']
              # API returns null tag... but async does not like it
              transfer_spec.delete_if{ |_k, v| v.nil? }
              # delete this part, as the returned value contains only destination, and not sources
              # transfer_spec.delete('paths') if command.eql?(:upload)
              Log.log.debug{Log.dump(:ts, transfer_spec)}
              transfer_spec
            end
          when :upload, :download
            # empty transfer spec for authorization request
            request_transfer_spec = {}
            # set requested paths depending on direction
            request_transfer_spec[:paths] = if command.eql?(:download)
              transfer.ts_source_paths
            else
              [{ destination: transfer.destination_folder(Fasp::TransferSpec::DIRECTION_SEND) }]
            end
            # add fixed parameters if any (for COS)
            @api_node.add_tspec_info(request_transfer_spec) if @api_node.respond_to?(:add_tspec_info)
            # prepare payload for single request
            setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
            # only one request, so only one answer
            transfer_spec = @api_node.create("files/#{command}_setup", setup_payload)[:data]['transfer_specs'].first['transfer_spec']
            # delete this part, as the returned value contains only destination, and not sources
            transfer_spec.delete('paths') if command.eql?(:upload)
            return Main.result_transfer(transfer.start(transfer_spec))
          when :http_node_download
            remote_path = get_next_arg_add_prefix(prefix_path, 'remote path')
            file_name = File.basename(remote_path)
            @api_node.call(
              operation: 'GET',
              subpath: "files/#{URI.encode_www_form_component(remote_path)}/contents",
              save_to_file: File.join(transfer.destination_folder(Fasp::TransferSpec::DIRECTION_RECEIVE), file_name))
            return Main.result_status("downloaded: #{file_name}")
          end
          raise 'INTERNAL ERROR'
        end

        # common API to node and Shares
        # prefix_path is used to list remote sources in Faspex
        def execute_simple_common(command, prefix_path)
          case command
          when *COMMANDS_GEN3
            execute_command_gen3(command, prefix_path)
          when :access_keys
            ak_command = options.get_next_command(%i[do set_bearer_key].concat(Plugin::ALL_OPS))
            case ak_command
            when *Plugin::ALL_OPS
              return entity_command(ak_command, @api_node, 'access_keys') do |field, value|
                       raise 'only selector: %id:self' unless field.eql?('id') && value.eql?('self')
                       @api_node.read('access_keys/self')[:data]['id']
                     end
            when :do
              access_key_id = options.get_next_argument('access key id')
              root_file_id = options.get_option(:root_id)
              if root_file_id.nil?
                ak_info = @api_node.read("access_keys/#{access_key_id}")[:data]
                # change API credentials if different access key
                if !access_key_id.eql?('self')
                  @api_node.params[:auth][:username] = ak_info['id']
                  @api_node.params[:auth][:password] = config.lookup_secret(url: @api_node.params[:base_url], username: ak_info['id'], mandatory: true)
                end
                root_file_id = ak_info['root_file_id']
              end
              command_repo = options.get_next_command(COMMANDS_GEN4)
              return execute_command_gen4(command_repo, root_file_id)
            when :set_bearer_key
              access_key_id = options.get_next_argument('access key id')
              access_key_id = @api_node.read('access_keys/self')[:data]['id'] if access_key_id.eql?('self')
              bearer_key_pem = options.get_next_argument('public or private RSA key PEM value', type: String)
              key = OpenSSL::PKey.read(bearer_key_pem)
              key = key.public_key if key.private?
              bearer_key_pem = key.to_pem
              @api_node.update("access_keys/#{access_key_id}", {token_verification_key: bearer_key_pem})
              return Main.result_status('public key updated')
            end
          when :health
            nagios = Nagios.new
            begin
              info = @api_node.read('info')[:data]
              nagios.add_ok('node api', 'accessible')
              nagios.check_time_offset(info['current_time'], 'node api')
              nagios.check_product_version('node api', 'entsrv', info['version'])
            rescue StandardError => e
              nagios.add_critical('node api', e.to_s)
            end
            begin
              @api_node.call(
                operation: 'POST',
                subpath: 'services/soap/Transfer-201210',
                headers: {'Content-Type' => 'text/xml;charset=UTF-8', 'SOAPAction' => 'FASPSessionNET-200911#GetSessionInfo'},
                text_body_params: CENTRAL_SOAP_API_TEST)[:http].body
              nagios.add_ok('central', 'accessible by node')
            rescue StandardError => e
              nagios.add_critical('central', e.to_s)
            end
            return nagios.result
          when :events
            events = @api_node.read('events', query_read_delete)[:data]
            return { type: :object_list, data: events}
          when :info
            nd_info = @api_node.read('info')[:data]
            return { type: :single_object, data: nd_info}
          when :slash
            nd_info = @api_node.read('')[:data]
            return { type: :single_object, data: nd_info}
          when :license
            # requires: asnodeadmin -mu <node user> --acl-add=internal --internal
            node_license = @api_node.read('license')[:data]
            if node_license['failure'].is_a?(String) && node_license['failure'].include?('ACL')
              Log.log.error('server must have: asnodeadmin -mu <node user> --acl-add=internal --internal')
            end
            return { type: :single_object, data: node_license}
          when :api_details
            return { type: :single_object, data: @api_node.params }
          end
        end

        # @return [Hash] api and main file id for given path or id
        # Allows to specify a file by its path or by its id on the node
        def apifid_from_next_arg(top_file_id)
          file_path = instance_identifier(description: 'path or %id:<id>') do |attribute, value|
            raise 'Only selection "id" is supported (file id)' unless attribute.eql?('id')
            # directly return result for method
            return {api: @api_node, file_id: value}
          end
          # there was no selector, so it is a path
          return @api_node.resolve_api_fid(top_file_id, file_path)
        end

        def execute_command_gen4(command_repo, top_file_id)
          case command_repo
          when :v3
            # NOTE: other common actions are unauthorized with user scope
            command_legacy = options.get_next_command(V3_IN_V4_ACTIONS)
            # TODO: shall we support all methods here ? what if there is a link ?
            apifid = @api_node.resolve_api_fid(top_file_id, '')
            return Node.new(@agents, api: apifid[:api]).execute_action(command_legacy)
          when :node_info, :bearer_token_node
            apifid = @api_node.resolve_api_fid(top_file_id, options.get_next_argument('path'))
            result = {
              url:     apifid[:api].params[:base_url],
              root_id: apifid[:file_id]
            }
            raise 'No auth for node' if apifid[:api].params[:auth].nil?
            case apifid[:api].params[:auth][:type]
            when :basic
              result[:username] = apifid[:api].params[:auth][:username]
              result[:password] = apifid[:api].params[:auth][:password]
            when :oauth2
              result[:username] = apifid[:api].params[:headers][Aspera::Node::HEADER_X_ASPERA_ACCESS_KEY]
              result[:password] = apifid[:api].oauth_token
            else raise 'internal error: unknown auth type'
            end
            return {type: :single_object, data: result} if command_repo.eql?(:node_info)
            # check format of bearer token
            Oauth.bearer_extract(result[:password])
            return Main.result_status(result[:password])
          when :browse
            apifid = @api_node.resolve_api_fid(top_file_id, options.get_next_argument('path'))
            file_info = apifid[:api].read("files/#{apifid[:file_id]}")[:data]
            if file_info['type'].eql?('folder')
              result = apifid[:api].read("files/#{apifid[:file_id]}/files", old_query_read_delete)
              items = result[:data]
              formatter.display_item_count(result[:data].length, result[:http]['X-Total-Count'])
            else
              items = [file_info]
            end
            return {type: :object_list, data: items, fields: %w[name type recursive_size size modified_time access_level]}
          when :find
            apifid = @api_node.resolve_api_fid(top_file_id, options.get_next_argument('path'))
            test_block = Aspera::Node.file_matcher_from_argument(options)
            return {type: :object_list, data: @api_node.find_files(apifid[:file_id], test_block), fields: ['path']}
          when :mkdir
            containing_folder_path = options.get_next_argument('path').split(Aspera::Node::PATH_SEPARATOR)
            new_folder = containing_folder_path.pop
            apifid = @api_node.resolve_api_fid(top_file_id, containing_folder_path.join(Aspera::Node::PATH_SEPARATOR))
            result = apifid[:api].create("files/#{apifid[:file_id]}/files", {name: new_folder, type: :folder})[:data]
            return Main.result_status("created: #{result['name']} (id=#{result['id']})")
          when :rename
            file_path = options.get_next_argument('source path')
            apifid = @api_node.resolve_api_fid(top_file_id, file_path)
            newname = options.get_next_argument('new name')
            result = apifid[:api].update("files/#{apifid[:file_id]}", {name: newname})[:data]
            return Main.result_status("renamed to #{newname}")
          when :delete
            return do_bulk_operation(command: command_repo, descr: 'path', values: String, id_result: 'path') do |l_path|
              apifid = @api_node.resolve_api_fid(top_file_id, l_path)
              result = apifid[:api].delete("files/#{apifid[:file_id]}")[:data]
              {'path' => l_path}
            end
          when :sync
            return execute_sync_action do |sync_direction, _local_path, remote_path|
              # Gen4 API
              # direction is push pull, bidi
              ts_direction = case sync_direction
              when :push, :bidi then Fasp::TransferSpec::DIRECTION_SEND
              when :pull then Fasp::TransferSpec::DIRECTION_RECEIVE
              else raise "internal error: bad direction: #{sync_direction} (#{sync_direction.class})"
              end
              # remote is specified by option to_folder
              apifid = @api_node.resolve_api_fid(top_file_id, remote_path)
              transfer_spec = apifid[:api].transfer_spec_gen4(apifid[:file_id], ts_direction)
              Log.log.debug{Log.dump(:ts, transfer_spec)}
              transfer_spec
            end
          when :upload
            apifid = @api_node.resolve_api_fid(top_file_id, transfer.destination_folder(Fasp::TransferSpec::DIRECTION_SEND))
            return Main.result_transfer(transfer.start(apifid[:api].transfer_spec_gen4(apifid[:file_id], Fasp::TransferSpec::DIRECTION_SEND)))
          when :download
            source_paths = transfer.ts_source_paths
            # special case for AoC : all files must be in same folder
            source_folder = source_paths.shift['source']
            # if a single file: split into folder and path
            apifid = @api_node.resolve_api_fid(top_file_id, source_folder)
            if source_paths.empty?
              file_info = apifid[:api].read("files/#{apifid[:file_id]}")[:data]
              case file_info['type']
              when 'file'
                # if the single source is a file, we need to split into folder path and filename
                src_dir_elements = source_folder.split(Aspera::Node::PATH_SEPARATOR)
                # filename is the last one
                source_paths = [{'source' => src_dir_elements.pop}]
                # source folder is what remains
                source_folder = src_dir_elements.join(Aspera::Node::PATH_SEPARATOR)
                # TODO: instead of creating a new object, use the same, and change file id with parent folder id ? possible ?
                apifid = @api_node.resolve_api_fid(top_file_id, source_folder)
              when 'link', 'folder'
                # single source is 'folder' or 'link'
                # TODO: add this ? , 'destination'=>file_info['name']
                source_paths = [{'source' => '.'}]
              else
                raise "Unknown source type: #{file_info['type']}"
              end
            end
            return Main.result_transfer(transfer.start(apifid[:api].transfer_spec_gen4(apifid[:file_id], Fasp::TransferSpec::DIRECTION_RECEIVE, {'paths'=>source_paths})))
          when :http_node_download
            source_paths = transfer.ts_source_paths
            source_folder = source_paths.shift['source']
            if source_paths.empty?
              source_folder = source_folder.split(Aspera::Node::PATH_SEPARATOR)
              source_paths = [{'source' => source_folder.pop}]
              source_folder = source_folder.join(Aspera::Node::PATH_SEPARATOR)
            end
            raise Cli::BadArgument, 'one file at a time only in HTTP mode' if source_paths.length > 1
            file_name = source_paths.first['source']
            apifid = @api_node.resolve_api_fid(top_file_id, File.join(source_folder, file_name))
            apifid[:api].call(
              operation: 'GET',
              subpath: "files/#{apifid[:file_id]}/content",
              save_to_file: File.join(transfer.destination_folder(Fasp::TransferSpec::DIRECTION_RECEIVE), file_name))
            return Main.result_status("downloaded: #{file_name}")
          when :show
            apifid = apifid_from_next_arg(top_file_id)
            items = apifid[:api].read("files/#{apifid[:file_id]}")[:data]
            return {type: :single_object, data: items}
          when :modify
            apifid = apifid_from_next_arg(top_file_id)
            update_param = options.get_next_argument('update data', type: Hash)
            apifid[:api].update("files/#{apifid[:file_id]}", update_param)[:data]
            return Main.result_status('Done')
          when :thumbnail
            apifid = apifid_from_next_arg(top_file_id)
            result = apifid[:api].call(
              operation: 'GET',
              subpath: "files/#{apifid[:file_id]}/preview",
              headers: {'Accept' => 'image/png'}
            )
            require 'aspera/preview/terminal'
            terminal_options = options.get_option(:query, default: {}).symbolize_keys
            allowed_options = Preview::Terminal.method(:build).parameters.select{|i|i[0].eql?(:key)}.map{|i|i[1]}
            unknown_options = terminal_options.keys - allowed_options
            raise "invalid options: #{unknown_options.join(', ')}, use #{allowed_options.join(', ')}" unless unknown_options.empty?
            return Main.result_status(Preview::Terminal.build(result[:http].body, **terminal_options))
          when :permission
            apifid = apifid_from_next_arg(top_file_id)
            command_perm = options.get_next_command(%i[list create delete])
            case command_perm
            when :list
              # generic options : TODO: as arg ? query_read_delete
              list_options ||= {'include' => Rest.array_params(%w[access_level permission_count])}
              # add which one to get
              list_options['file_id'] = apifid[:file_id]
              list_options['inherited'] ||= false
              items = apifid[:api].read('permissions', list_options)[:data]
              return {type: :object_list, data: items}
            when :delete
              return do_bulk_operation(command: command_perm, descr: 'identifier', values: :identifier) do |one_id|
                apifid[:api].delete("permissions/#{one_id}")
                # notify application of deletion
                the_app[:api].permissions_send_event(created_data: created_data, app_info: the_app, types: ['permission.deleted']) unless the_app.nil?
                {'id' => one_id}
              end
            when :create
              create_param = options.get_next_argument('creation data', type: Hash)
              raise 'no file_id' if create_param.key?('file_id')
              create_param['file_id'] = apifid[:file_id]
              create_param['access_levels'] = Aspera::Node::ACCESS_LEVELS unless create_param.key?('access_levels')
              # add application specific tags (AoC)
              the_app = apifid[:api].app_info
              the_app[:api].permissions_set_create_params(create_param: create_param, app_info: the_app) unless the_app.nil?
              # create permission
              created_data = apifid[:api].create('permissions', create_param)[:data]
              # notify application of creation
              the_app[:api].permissions_send_event(created_data: created_data, app_info: the_app) unless the_app.nil?
              return { type: :single_object, data: created_data}
            else raise "internal error:shall not reach here (#{command_perm})"
            end
          else raise "INTERNAL ERROR: no case for #{command_repo}"
          end # command_repo
          # raise 'INTERNAL ERROR: missing return'
        end # execute_command_gen4

        # This is older API
        def execute_async
          command = options.get_next_command(%i[list delete files show counters bandwidth])
          unless command.eql?(:list)
            async_name = options.get_option(:sync_name)
            if async_name.nil?
              async_id = instance_identifier
              if async_id.eql?(ExtendedValue::ALL) && %i[show delete].include?(command)
                async_ids = @api_node.read('async/list')[:data]['sync_ids']
              else
                Integer(async_id) # must be integer
                async_ids = [async_id]
              end
            else
              async_ids = @api_node.read('async/list')[:data]['sync_ids']
              summaries = @api_node.create('async/summary', {'syncs' => async_ids})[:data]['sync_summaries']
              selected = summaries.find{|s|s['name'].eql?(async_name)}
              raise "no such sync: #{async_name}" if selected.nil?
              async_id = selected['snid']
              async_ids = [async_id]
            end
            post_data = {'syncs' => async_ids}
          end
          case command
          when :list
            resp = @api_node.read('async/list')[:data]['sync_ids']
            return { type: :value_list, data: resp, name: 'id' }
          when :show
            resp = @api_node.create('async/summary', post_data)[:data]['sync_summaries']
            return Main.result_empty if resp.empty?
            return { type: :object_list, data: resp, fields: %w[snid name local_dir remote_dir] } if async_id.eql?(ExtendedValue::ALL)
            return { type: :single_object, data: resp.first }
          when :delete
            resp = @api_node.create('async/delete', post_data)[:data]
            return { type: :single_object, data: resp, name: 'id' }
          when :bandwidth
            post_data['seconds'] = 100 # TODO: as parameter with --value
            resp = @api_node.create('async/bandwidth', post_data)[:data]
            data = resp['bandwidth_data']
            return Main.result_empty if data.empty?
            data = data.first[async_id]['data']
            return { type: :object_list, data: data, name: 'id' }
          when :files
            # count int
            # filename str
            # skip int
            # status int
            filter = query_option
            post_data.merge!(filter) unless filter.nil?
            resp = @api_node.create('async/files', post_data)[:data]
            data = resp['sync_files']
            data = data.first[async_id] unless data.empty?
            iteration_data = []
            skip_ids_persistency = nil
            if options.get_option(:once_only, mandatory: true)
              skip_ids_persistency = PersistencyActionOnce.new(
                manager: @agents[:persistency],
                data:    iteration_data,
                id:      IdGenerator.from_list([
                  'sync_files',
                  options.get_option(:url, mandatory: true),
                  options.get_option(:username, mandatory: true),
                  async_id]))
              unless iteration_data.first.nil?
                data.select!{|l| l['fnid'].to_i > iteration_data.first}
              end
              iteration_data[0] = data.last['fnid'].to_i unless data.empty?
            end
            return Main.result_empty if data.empty?
            skip_ids_persistency&.save
            return { type: :object_list, data: data, name: 'id' }
          when :counters
            resp = @api_node.create('async/counters', post_data)[:data]['sync_counters'].first[async_id].last
            return Main.result_empty if resp.nil?
            return { type: :single_object, data: resp }
          end
        end

        # @return [Integer] id of the sync
        # @raise [Cli::BadArgument] if no such sync, or not by name
        # @param [String] field name of the field to search
        # @param [String] value value of the field to search
        def ssync_lookup(field, value)
          raise Cli::BadArgument, "Only search by name is supported (#{field})" unless field.eql?('name')
          @api_node.read('asyncs')[:data]['ids'].each do |id|
            sync_info = @api_node.read("asyncs/#{id}")[:data]['configuration']
            # name is unique, so we can return
            return id if sync_info[field].eql?(value)
          end
          raise Cli::BadArgument, "no such sync: #{field}=#{value}"
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
          bearer_token].concat(COMMON_ACTIONS).freeze

        def execute_action(command=nil, prefix_path=nil)
          command ||= options.get_next_command(ACTIONS)
          case command
          when *COMMON_ACTIONS then return execute_simple_common(command, prefix_path)
          when :async then return execute_async # former API
          when :ssync
            # newer API
            sync_command = options.get_next_command(%i[start stop bandwidth counters files state summary].concat(Plugin::ALL_OPS) - %i[modify])
            case sync_command
            when *Plugin::ALL_OPS then return entity_command(sync_command, @api_node, 'asyncs', item_list_key: 'ids'){|field, value|ssync_lookup(field, value)}
            else
              asyncs_id = instance_identifier {|field, value|ssync_lookup(field, value)}
              parameters = nil
              if %i[start stop].include?(sync_command)
                @api_node.create("asyncs/#{asyncs_id}/#{sync_command}", parameters)
                return Main.result_status('Done')
              end
              parameters = query_option(default: {}) if %i[bandwidth counters files].include?(sync_command)
              return { type: :single_object, data: @api_node.read("asyncs/#{asyncs_id}/#{sync_command}", parameters)[:data] }
            end
          when :stream
            command = options.get_next_command(%i[list create show modify cancel])
            case command
            when :list
              resp = @api_node.read('ops/transfers', old_query_read_delete)
              return { type: :object_list, data: resp[:data], fields: %w[id status] } # TODO: useful?
            when :create
              resp = @api_node.create('streams', value_create_modify(command: command))
              return { type: :single_object, data: resp[:data] }
            when :show
              resp = @api_node.read("ops/transfers/#{options.get_next_argument('transfer id')}")
              return { type: :other_struct, data: resp[:data] }
            when :modify
              resp = @api_node.update("streams/#{options.get_next_argument('transfer id')}", value_create_modify(command: command))
              return { type: :other_struct, data: resp[:data] }
            when :cancel
              resp = @api_node.cancel("streams/#{options.get_next_argument('transfer id')}")
              return { type: :other_struct, data: resp[:data] }
            else
              raise 'error'
            end
          when :transfer
            command = options.get_next_command(%i[list cancel show modify bandwidth_average sessions])
            res_class_path = 'ops/transfers'
            if %i[cancel show modify].include?(command)
              one_res_id = instance_identifier
              one_res_path = "#{res_class_path}/#{one_res_id}"
            end
            case command
            when :list
              transfers_data = @api_node.read(res_class_path, query_read_delete)[:data]
              return {
                type:   :object_list,
                data:   transfers_data,
                fields: %w[id status start_spec.direction start_spec.remote_user start_spec.remote_host start_spec.destination_path]
              }
            when :sessions
              transfers_data = @api_node.read(res_class_path, query_read_delete)[:data]
              sessions = transfers_data.map{|t|t['sessions']}.flatten
              sessions.each do |session|
                session['start_time'] = Time.at(session['start_time_usec'] / 1_000_000.0).utc.iso8601(0)
                session['end_time'] = Time.at(session['end_time_usec'] / 1_000_000.0).utc.iso8601(0)
              end
              return {
                type:   :object_list,
                data:   sessions,
                fields: %w[id status start_time end_time target_rate_kbps]
              }
            when :cancel
              resp = @api_node.cancel(one_res_path)
              return { type: :other_struct, data: resp[:data] }
            when :show
              resp = @api_node.read(one_res_path)
              return { type: :other_struct, data: resp[:data] }
            when :modify
              resp = @api_node.update(one_res_path, options.get_next_argument('update value', type: Hash))
              return { type: :other_struct, data: resp[:data] }
            when :bandwidth_average
              transfers_data = @api_node.read(res_class_path, query_read_delete)[:data]
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
                period_bandwidth = Fasp::TransferSpec::DIRECTION_ENUM_VALUES.map(&:to_sym).each_with_object({}) do |direction, h|
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
                next if Fasp::TransferSpec::DIRECTION_ENUM_VALUES.map(&:to_sym).all? do |dir|
                  period_bandwidth[dir][:sessions].zero?
                end
                result.push({start: Time.at(start_date / 1_000_000), end: Time.at(end_date / 1_000_000)}.merge(period_bandwidth))
              end
              return { type: :object_list, data: result }
            else
              raise 'error'
            end
          when :service
            command = options.get_next_command(%i[list create delete])
            if [:delete].include?(command)
              service_id = instance_identifier
            end
            case command
            when :list
              resp = @api_node.read('rund/services')
              return { type: :object_list, data: resp[:data]['services'] }
            when :create
              # @json:'{"type":"WATCHFOLDERD","run_as":{"user":"user1"}}'
              params = options.get_next_argument('Run creation data (structure)')
              resp = @api_node.create('rund/services', params)
              return Main.result_status("#{resp[:data]['id']} created")
            when :delete
              @api_node.delete("rund/services/#{service_id}")
              return Main.result_status("#{service_id} deleted")
            end
          when :watch_folder
            res_class_path = 'v3/watchfolders'
            command = options.get_next_command(%i[create list show modify delete state])
            if %i[show modify delete state].include?(command)
              one_res_id = instance_identifier
              one_res_path = "#{res_class_path}/#{one_res_id}"
            end
            # hum, to avoid: Unable to convert 2016_09_14 configuration
            @api_node.params[:headers] ||= {}
            @api_node.params[:headers]['X-aspera-WF-version'] = '2017_10_23'
            case command
            when :create
              resp = @api_node.create(res_class_path, value_create_modify(command: command))
              return Main.result_status("#{resp[:data]['id']} created")
            when :list
              resp = @api_node.read(res_class_path, old_query_read_delete)
              return { type: :value_list, data: resp[:data]['ids'], name: 'id' }
            when :show
              return { type: :single_object, data: @api_node.read(one_res_path)[:data]}
            when :modify
              @api_node.update(one_res_path, query_option(mandatory: true))
              return Main.result_status("#{one_res_id} updated")
            when :delete
              @api_node.delete(one_res_path)
              return Main.result_status("#{one_res_id} deleted")
            when :state
              return { type: :single_object, data: @api_node.read("#{one_res_path}/state")[:data] }
            end
          when :central
            command = options.get_next_command(%i[session file])
            validator_id = options.get_option(:validator)
            validation = {'validator_id' => validator_id} unless validator_id.nil?
            request_data = query_option(default: {})
            case command
            when :session
              command = options.get_next_command([:list])
              case command
              when :list
                request_data.deep_merge!({'validation' => validation}) unless validation.nil?
                resp = @api_node.create('services/rest/transfers/v1/sessions', request_data)
                return {
                  type:   :object_list,
                  data:   resp[:data]['session_info_result']['session_info'],
                  fields: %w[session_uuid status transport direction bytes_transferred]
                }
              end
            when :file
              command = options.get_next_command(%i[list modify])
              case command
              when :list
                request_data.deep_merge!({'validation' => validation}) unless validation.nil?
                resp = @api_node.create('services/rest/transfers/v1/files', request_data)[:data]
                resp = JSON.parse(resp) if resp.is_a?(String)
                Log.log.debug{Log.dump(:resp, resp)}
                return { type: :object_list, data: resp['file_transfer_info_result']['file_transfer_info'], fields: %w[session_uuid file_id status path]}
              when :modify
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
            OpenApplication.instance.uri(options.get_option(:asperabrowserurl) + '?goto=' + encoded_params)
            return Main.result_status('done')
          when :basic_token
            return Main.result_status(Rest.basic_token(options.get_option(:username, mandatory: true), options.get_option(:password, mandatory: true)))
          when :bearer_token
            private_key = OpenSSL::PKey::RSA.new(options.get_next_argument('private RSA key PEM value', type: String))
            token_info = options.get_next_argument('user and group identification', type: Hash)
            access_key = options.get_option(:username, mandatory: true)
            return Main.result_status(Aspera::Node.bearer_token(payload: token_info, access_key: access_key, private_key: private_key))
          end # case command
          raise 'ERROR: shall not reach this line'
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Aspera
