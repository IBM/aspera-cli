# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/nagios'
require 'aspera/hash_ext'
require 'aspera/id_generator'
require 'aspera/node'
require 'aspera/aoc'
require 'aspera/fasp/transfer_spec'
require 'base64'
require 'zlib'

module Aspera
  module Cli
    module Plugins
      class Node < BasicAuthPlugin
        class << self
          def detect(base_url)
            api = Rest.new({ base_url: base_url})
            result = api.call({ operation: 'GET', subpath: 'ping'})
            if result[:http].body.eql?('')
              return { product: :node, version: 'unknown'}
            end
            return nil
          end

          def register_node_options(env)
            env[:options].add_opt_simple(:validator, 'identifier of validator (optional for central)')
            env[:options].add_opt_simple(:asperabrowserurl, 'URL for simple aspera web ui')
            env[:options].add_opt_simple(:sync_name, 'sync name')
            env[:options].add_opt_simple(:path, 'file or folder path for gen4 operation "file"')
            env[:options].add_opt_list(:token_type, %i[aspera basic hybrid], 'Type of token used for transfers')
            env[:options].set_option(:asperabrowserurl, 'https://asperabrowser.mybluemix.net')
            env[:options].set_option(:token_type, :aspera)
            env[:options].parse_options!
          end
        end
        SAMPLE_SOAP_CALL = '<?xml version="1.0" encoding="UTF-8"?>'\
          '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="urn:Aspera:XML:FASPSessionNET:2009/11:Types">'\
          '<soapenv:Header></soapenv:Header>'\
          '<soapenv:Body><typ:GetSessionInfoRequest><SessionFilter><SessionStatus>running</SessionStatus></SessionFilter></typ:GetSessionInfoRequest></soapenv:Body>'\
          '</soapenv:Envelope>'
        SEARCH_REMOVE_FIELDS=%w[basename permissions].freeze
        VAL_ALL = 'ALL'
        private_constant(*%i[SAMPLE_SOAP_CALL SEARCH_REMOVE_FIELDS VAL_ALL])

        def initialize(env)
          super(env)
          # this is added to transfer spec, for instance to add tags (COS)
          @add_request_param = env[:add_request_param] || {}
          self.class.register_node_options(env) unless env[:skip_node_options]
          return if env[:man_only]
          @api_node =
            if env.has_key?(:node_api)
              # this can be Aspera::Node or Aspera::Rest (shares)
              env[:node_api]
            elsif options.get_option(:password, is_type: :mandatory).start_with?('Bearer ')
              # info is provided like node_info of aoc
              Aspera::Node.new(params: {
                base_url: options.get_option(:url, is_type: :mandatory),
                headers:  {
                  'X-Aspera-AccessKey' => options.get_option(:username, is_type: :mandatory),
                  'Authorization'      => options.get_option(:password, is_type: :mandatory)
                }
              })
            else
              # this is normal case
              Aspera::Node.new(params: {
                base_url: options.get_option(:url, is_type: :mandatory),
                auth:     {
                  type:     :basic,
                  username: options.get_option(:username, is_type: :mandatory),
                  password: options.get_option(:password, is_type: :mandatory)
                }})
            end
        end

        def c_textify_browse(table_data)
          return table_data.map {|i| i['permissions'] = i['permissions'].map { |x| x['name'] }.join(','); i }
        end

        # key/value is defined in main in hash_table
        def c_textify_bool_list_result(list, name_list)
          list.each_index do |i|
            next unless name_list.include?(list[i]['key'])
            list[i]['value'].each do |item|
              list.push({'key' => item['name'], 'value' => item['value']})
            end
            list.delete_at(i)
            # continue at same index because we delete current one
            redo
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
        def c_result_translate_rem_prefix(resp, type, success_msg, path_prefix)
          resres = { data: [], type: :object_list, fields: [type, 'result']}
          JSON.parse(resp[:http].body)['paths'].each do |p|
            result = success_msg
            if p.has_key?('error')
              Log.log.error("#{p['error']['user_message']} : #{p['path']}")
              result = 'ERROR: ' + p['error']['user_message']
            end
            resres[:data].push({type => p['path'], 'result' => result})
          end
          return c_result_remove_prefix_path(resres, type, path_prefix)
        end

        # get path arguments from command line, and add prefix
        def get_next_arg_add_prefix(path_prefix, name, number=:single)
          thepath = options.get_next_argument(name, expected: number)
          return thepath if path_prefix.nil?
          return File.join(path_prefix, thepath) if thepath.is_a?(String)
          return thepath.map {|p| File.join(path_prefix, p)} if thepath.is_a?(Array)
          raise StandardError, 'expect: nil, String or Array'
        end

        SIMPLE_ACTIONS = %i[health events space info license mkdir mklink mkfile rename delete search].freeze

        COMMON_ACTIONS = %i[browse upload download api_details].concat(SIMPLE_ACTIONS).freeze

        # common API to node and Shares
        # prefix_path is used to list remote sources in Faspex
        def execute_simple_common(command, prefix_path)
          case command
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
                text_body_params: SAMPLE_SOAP_CALL)[:http].body
              nagios.add_ok('central', 'accessible by node')
            rescue StandardError => e
              nagios.add_critical('central', e.to_s)
            end
            return nagios.result
          when :events
            events = @api_node.read('events', options.get_option(:value))[:data]
            return { type: :object_list, data: events}
          when :info
            node_info = @api_node.read('info')[:data]
            return { type: :single_object, data: node_info, textify: lambda { |table_data| c_textify_bool_list_result(table_data, %w[capabilities settings])}}
          when :license # requires: asnodeadmin -mu <node user> --acl-add=internal --internal
            node_license = @api_node.read('license')[:data]
            if node_license['failure'].is_a?(String) && node_license['failure'].include?('ACL')
              Log.log.error('server must have: asnodeadmin -mu <node user> --acl-add=internal --internal')
            end
            return { type: :single_object, data: node_license}
          when :delete
            paths_to_delete = get_next_arg_add_prefix(prefix_path, 'file list', :multiple)
            resp = @api_node.create('files/delete', { paths: paths_to_delete.map{|i| {'path' => i.start_with?('/') ? i : '/' + i} }})
            return c_result_translate_rem_prefix(resp, 'file', 'deleted', prefix_path)
          when :search
            search_root = get_next_arg_add_prefix(prefix_path, 'search root')
            parameters = {'path' => search_root}
            other_options = options.get_option(:value)
            parameters.merge!(other_options) unless other_options.nil?
            resp = @api_node.create('files/search', parameters)
            result = { type: :object_list, data: resp[:data]['items']}
            return Main.result_empty if result[:data].empty?
            result[:fields] = result[:data].first.keys.reject{|i|SEARCH_REMOVE_FIELDS.include?(i)}
            self.format.display_status("Items: #{resp[:data]['item_count']}/#{resp[:data]['total_count']}")
            self.format.display_status("params: #{resp[:data]['parameters'].keys.map{|k|"#{k}:#{resp[:data]['parameters'][k]}"}.join(',')}")
            return c_result_remove_prefix_path(result, 'path', prefix_path)
          when :space
            # TODO: could be a list of path
            path_list = get_next_arg_add_prefix(prefix_path, 'folder path or ext.val. list')
            path_list = [path_list] unless path_list.is_a?(Array)
            resp = @api_node.create('space', { 'paths' => path_list.map {|i| { path: i} } })
            result = { data: resp[:data]['paths'], type: :object_list}
            #return c_result_translate_rem_prefix(resp,'folder','created',prefix_path)
            return c_result_remove_prefix_path(result, 'path', prefix_path)
          when :mkdir
            path_list = get_next_arg_add_prefix(prefix_path, 'folder path or ext.val. list')
            path_list = [path_list] unless path_list.is_a?(Array)
            #TODO: a command for that ?
            #resp=@api_node.create('space',{ "paths" => path_list.map {|i| { type: :directory, path: i} } } )
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
            thepath = get_next_arg_add_prefix(prefix_path, 'path')
            query = { path: thepath}
            additional_query = options.get_option(:query)
            query.merge!(additional_query) unless additional_query.nil?
            send_result = @api_node.create('files/browse', query)[:data]
            #example: send_result={'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}
            # if there is no items
            case send_result['self']['type']
            when 'directory', 'container' # directory: node, container: shares
              result = { data: send_result['items'], type: :object_list, textify: lambda { |table_data| c_textify_browse(table_data) } }
              self.format.display_status("Items: #{send_result['item_count']}/#{send_result['total_count']}")
            else # 'file','symbolic_link'
              result = { data: send_result['self'], type: :single_object}
              #result={ data: [send_result['self']] , type: :object_list, textify: lambda { |table_data| c_textify_browse(table_data) } }
              #raise "unknown type: #{send_result['self']['type']}"
            end
            return c_result_remove_prefix_path(result, 'path', prefix_path)
          when :upload, :download
            token_type = options.get_option(:token_type)
            # nil if Shares 1.x
            token_type = :aspera if token_type.nil?
            case token_type
            when :aspera, :hybrid
              # empty transfer spec for authorization request
              request_transfer_spec={}
              # set requested paths depending on direction
              request_transfer_spec[:paths] = command.eql?(:download) ? transfer.ts_source_paths : [{ destination: transfer.destination_folder('send') }]
              # add fixed parameters if any (for COS)
              request_transfer_spec.deep_merge!(@add_request_param)
              # prepare payload for single request
              setup_payload={transfer_requests: [{transfer_request: request_transfer_spec}]}
              # only one request, so only one answer
              transfer_spec = @api_node.create("files/#{command}_setup", setup_payload)[:data]['transfer_specs'].first['transfer_spec']
              # delete this part, as the returned value contains only destination, and not sources
              transfer_spec.delete('paths') if command.eql?(:upload)
            when :basic
              raise 'shall have auth' unless @api_node.params[:auth].is_a?(Hash)
              raise 'shall be basic auth' unless @api_node.params[:auth][:type].eql?(:basic)
              ts_direction =
                case command
                when :upload then Fasp::TransferSpec::DIRECTION_SEND
                when :download then Fasp::TransferSpec::DIRECTION_RECEIVE
                else raise 'Error: need upload or download'
                end
              transfer_spec = {
                'remote_host'      => URI.parse(@api_node.params[:base_url]).host,
                'remote_user'      => Aspera::Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER,
                'ssh_port'         => Aspera::Fasp::TransferSpec::SSH_PORT,
                'direction'        => ts_direction,
                'destination_root' => transfer.destination_folder(ts_direction)
              }.deep_merge(@add_request_param)
            else raise "ERROR: token_type #{tt}"
            end
            if %i[basic hybrid].include?(token_type)
              Aspera::Node.set_ak_basic_token(transfer_spec, @api_node.params[:auth][:username], @api_node.params[:auth][:password])
            end
            return Main.result_transfer(transfer.start(transfer_spec))
          when :api_details
            return { type: :single_object, data: @api_node.params }
          end
        end

        NODE4_COMMANDS = %i[browse find mkdir rename delete upload download http_node_download file permission bearer_token_node node_info].freeze

        def aoc_tags(operation)
          case operation
          when :upload, :download
            return {}
            #return {'aspera' => {'files' => {'parentCwd' => "#{apifid[:node_info]['id']}:#{apifid[:file_id]}"}}}
          when :permission
            return {}
            #return {'aspera' => {'files' => {'workspace' => {
            #  'id'                => @workspace_id,
            #  'workspace_name'    => @workspace_name,
            #  'user_name'         => aoc_api.user_info['name'],
            #  'shared_by_user_id' => aoc_api.user_info['id'],
            #  'shared_by_name'    => aoc_api.user_info['name'],
            #  'shared_by_email'   => aoc_api.user_info['email'],
            #  'shared_with_name'  => access_id,
            #  'access_key'        => apifid[:node_info]['access_key'],
            #  'node'              => apifid[:node_info]['name']}}}}
          end
        end

        # set generic tags necessary for gen4 transfers
        def gen4_transfer_start(apifid, direction, paths: nil)
          ak_name = nil
          ak_token = nil
          case apifid[:api].params[:auth][:type]
          when :basic
            ak_name=apifid[:api].params[:auth][:username]
          when :oauth2
            ak_name=apifid[:api].params[:headers]['X-Aspera-AccessKey']
            ak_token=apifid[:api].oauth_token
          else raise "Unsupported auth method for node gen4: #{apifid[:api].params[:auth][:type]}"
          end
          transfer_spec = {
            'direction' => direction,
            'token'     => ak_token,
            'tags'      => {
              'aspera' => {
                'node' => {
                  'access_key' => ak_name,
                  'file_id'    => apifid[:file_id]
                } # node
              } # aspera
            } # tags
          }
          transfer_spec['paths']=paths unless paths.nil?
          # add application specific tags (AoC)
          apifid[:api].add_ts_tags(transfer_spec: transfer_spec)
          # add basic token
          if transfer_spec['token'].nil?
            Aspera::Node.set_ak_basic_token(transfer_spec, apifid[:api].params[:auth][:username], apifid[:api].params[:auth][:password])
          end
          # add remote host info
          if AoC.use_standard_ports
            # get default TCP/UDP ports and transfer user
            transfer_spec.merge!(Fasp::TransferSpec::AK_TSPEC_BASE)
            # by default: same address as node API
            transfer_spec['remote_host'] = URI.parse(apifid[:api].params[:base_url]).host
          else
            # retrieve values from API
            std_t_spec = apifid[:api].create(
              'files/download_setup',
              {transfer_requests: [{ transfer_request: {paths: [{'source' => '/'}] } }] }
            )[:data]['transfer_specs'].first['transfer_spec']
            # copy some parts
            %w[remote_host remote_user ssh_port fasp_port wss_enabled wss_port].each {|i| transfer_spec[i] = std_t_spec[i] if std_t_spec.has_key?(i)}
          end
          # add caller provided transfer spec
          #transfer_spec.deep_merge!(ts_add)
          return transfer.start(transfer_spec)
        end

        def execute_node_gen4_command(command_repo, top_file_id)
          case command_repo
          when :node_info, :bearer_token_node
            thepath = options.get_next_argument('path')
            apifid = @api_node.resolve_api_fid(top_file_id, thepath)
            result = {
              url:     apifid[:api].params[:base_url],
              root_id: apifid[:file_id]
            }
            raise 'No auth for node' if apifid[:api].params[:auth].nil?
            case apifid[:api].params[:auth][:type]
            when :basic
              result[:username]=apifid[:api].params[:auth][:username]
              result[:password]= apifid[:api].params[:auth][:password]
            when :oauth2
              result[:username]= apifid[:api].params[:headers]['X-Aspera-AccessKey']
              result[:password]= apifid[:api].oauth_token
            else raise 'unknown'
            end
            return {type: :single_object, data: result} if command_repo.eql?(:node_info)
            raise 'not bearer token' unless result[:password].start_with?('Bearer ')
            return Main.result_status(result[:password])
          when :browse
            thepath = options.get_next_argument('path')
            apifid = @api_node.resolve_api_fid(top_file_id, thepath)
            file_info = apifid[:api].read("files/#{apifid[:file_id]}")[:data]
            if file_info['type'].eql?('folder')
              result = apifid[:api].read("files/#{apifid[:file_id]}/files", options.get_option(:value))
              items = result[:data]
              self.format.display_status("Items: #{result[:data].length}/#{result[:http]['X-Total-Count']}")
            else
              items = [file_info]
            end
            return {type: :object_list, data: items, fields: %w[name type recursive_size size modified_time access_level]}
          when :find
            thepath = options.get_next_argument('path')
            apifid = @api_node.resolve_api_fid(top_file_id, thepath)
            test_block = Aspera::Node.file_matcher(options.get_option(:value))
            return {type: :object_list, data: @api_node.find_files(apifid[:file_id], test_block), fields: ['path']}
          when :mkdir
            thepath = options.get_next_argument('path')
            containing_folder_path = thepath.split(AoC::PATH_SEPARATOR)
            new_folder = containing_folder_path.pop
            apifid = @api_node.resolve_api_fid(top_file_id, containing_folder_path.join(AoC::PATH_SEPARATOR))
            result = apifid[:api].create("files/#{apifid[:file_id]}/files", {name: new_folder, type: :folder})[:data]
            return Main.result_status("created: #{result['name']} (id=#{result['id']})")
          when :rename
            thepath = options.get_next_argument('source path')
            newname = options.get_next_argument('new name')
            apifid = @api_node.resolve_api_fid(top_file_id, thepath)
            result = apifid[:api].update("files/#{apifid[:file_id]}", {name: newname})[:data]
            return Main.result_status("renamed #{thepath} to #{newname}")
          when :delete
            thepath = options.get_next_argument('path')
            return do_bulk_operation(thepath, 'deleted', id_result: 'path') do |l_path|
              raise "expecting String (path), got #{l_path.class.name} (#{l_path})" unless l_path.is_a?(String)
              apifid = @api_node.resolve_api_fid(top_file_id, l_path)
              result = apifid[:api].delete("files/#{apifid[:file_id]}")[:data]
              {'path' => l_path}
            end
          when :upload
            apifid = @api_node.resolve_api_fid(top_file_id, transfer.destination_folder(Fasp::TransferSpec::DIRECTION_SEND))
            return Main.result_transfer(gen4_transfer_start(apifid, Fasp::TransferSpec::DIRECTION_SEND))
          when :download
            source_paths = transfer.ts_source_paths
            # special case for AoC : all files must be in same folder
            source_folder = source_paths.shift['source']
            # if a single file: split into folder and path
            if source_paths.empty?
              source_folder = source_folder.split(AoC::PATH_SEPARATOR)
              source_paths = [{'source' => source_folder.pop}]
              source_folder = source_folder.join(AoC::PATH_SEPARATOR)
            end
            apifid = @api_node.resolve_api_fid(top_file_id, source_folder)
            return Main.result_transfer(gen4_transfer_start(apifid, Fasp::TransferSpec::DIRECTION_RECEIVE, paths: source_paths))
          when :http_node_download
            source_paths = transfer.ts_source_paths
            source_folder = source_paths.shift['source']
            if source_paths.empty?
              source_folder = source_folder.split(AoC::PATH_SEPARATOR)
              source_paths = [{'source' => source_folder.pop}]
              source_folder = source_folder.join(AoC::PATH_SEPARATOR)
            end
            raise CliBadArgument, 'one file at a time only in HTTP mode' if source_paths.length > 1
            file_name = source_paths.first['source']
            apifid = @api_node.resolve_api_fid(top_file_id, File.join(source_folder, file_name))
            apifid[:api].call(
              operation: 'GET',
              subpath: "files/#{apifid[:file_id]}/content",
              save_to_file: File.join(transfer.destination_folder(Fasp::TransferSpec::DIRECTION_RECEIVE), file_name))
            return Main.result_status("downloaded: #{file_name}")
          when :permission
            command_perm = options.get_next_command(%i[list create])
            thepath = options.get_next_argument('source path')
            apifid = @api_node.resolve_api_fid(top_file_id, thepath)
            case command_perm
            when :list
              # generic options : TODO: as arg ? option_url_query
              list_options ||= {'include' => ['[]', 'access_level', 'permission_count']}
              # special value: ALL will show all permissions
              if !VAL_ALL.eql?(apifid[:file_id])
                # add which one to get
                list_options['file_id'] = apifid[:file_id]
                list_options['inherited'] ||= false
              end
              items = apifid[:api].read('permissions', list_options)[:data]
              return {type: :object_list, data: items}
            when :create
              #create_param=self.options.get_next_argument('creation data (Hash)')
              set_workspace_info
              access_id = "#{ID_AK_ADMIN}_WS_#{@workspace_id}"
              params = {
                'file_id'       => apifid[:file_id], # mandatory
                'access_type'   => 'user', # mandatory: user or group
                'access_id'     => access_id, # id of user or group
                'access_levels' => Aspera::Node::ACCESS_LEVELS,
                'tags'          => aoc_tags(:permission)}
              item = apifid[:api].create('permissions', params)[:data]
              return {type: :single_object, data: item}
            else raise "internal error:shall not reach here (#{command_perm})"
            end
          when :file
            command_node_file = options.get_next_command(%i[show modify])
            file_path = options.get_option(:path)
            apifid =
              if file_path.nil?
                {api: @api_node, file_id: instance_identifier}
              else
                @api_node.resolve_api_fid(top_file_id, file_path) # TODO: allow follow link ?
              end
            case command_node_file
            when :show
              items = apifid[:api].read("files/#{apifid[:file_id]}")[:data]
              return {type: :single_object, data: items}
            when :modify
              update_param = options.get_next_argument('update data (Hash)')
              res = apifid[:api].update("files/#{apifid[:file_id]}", update_param)[:data]
              return {type: :single_object, data: res}
            else raise "internal error:shall not reach here (#{command_node_file})"
            end
          else raise "INTERNAL ERROR: no case for #{command_repo}"
          end # command_repo
          raise 'INTERNAL ERROR: no return'
        end # execute_node_gen4_command

        # This is older API
        def execute_async
          command = options.get_next_command(%i[list delete files show counters bandwidth])
          unless command.eql?(:list)
            asyncname = options.get_option(:sync_name)
            if asyncname.nil?
              asyncid = instance_identifier
              if asyncid.eql?('ALL') && %i[show delete].include?(command)
                asyncids = @api_node.read('async/list')[:data]['sync_ids']
              else
                Integer(asyncid) # must be integer
                asyncids = [asyncid]
              end
            else
              asyncids = @api_node.read('async/list')[:data]['sync_ids']
              summaries = @api_node.create('async/summary', {'syncs' => asyncids})[:data]['sync_summaries']
              selected = summaries.find{|s|s['name'].eql?(asyncname)}
              raise "no such sync: #{asyncname}" if selected.nil?
              asyncid = selected['snid']
              asyncids = [asyncid]
            end
            pdata = {'syncs' => asyncids}
          end
          case command
          when :list
            resp = @api_node.read('async/list')[:data]['sync_ids']
            return { type: :value_list, data: resp, name: 'id' }
          when :show
            resp = @api_node.create('async/summary', pdata)[:data]['sync_summaries']
            return Main.result_empty if resp.empty?
            return { type: :object_list, data: resp, fields: %w[snid name local_dir remote_dir] } if asyncid.eql?('ALL')
            return { type: :single_object, data: resp.first }
          when :delete
            resp = @api_node.create('async/delete', pdata)[:data]
            return { type: :single_object, data: resp, name: 'id' }
          when :bandwidth
            pdata['seconds'] = 100 # TODO: as parameter with --value
            resp = @api_node.create('async/bandwidth', pdata)[:data]
            data = resp['bandwidth_data']
            return Main.result_empty if data.empty?
            data = data.first[asyncid]['data']
            return { type: :object_list, data: data, name: 'id' }
          when :files
            # count int
            # filename str
            # skip int
            # status int
            filter = options.get_option(:value)
            pdata.merge!(filter) unless filter.nil?
            resp = @api_node.create('async/files', pdata)[:data]
            data = resp['sync_files']
            data = data.first[asyncid] unless data.empty?
            iteration_data = []
            skip_ids_persistency = nil
            if options.get_option(:once_only, is_type: :mandatory)
              skip_ids_persistency = PersistencyActionOnce.new(
                manager: @agents[:persistency],
                data:    iteration_data,
                id:      IdGenerator.from_list([
                  'sync_files',
                  options.get_option(:url, is_type: :mandatory),
                  options.get_option(:username, is_type: :mandatory),
                  asyncid]))
              unless iteration_data.first.nil?
                data.select!{|l| l['fnid'].to_i > iteration_data.first}
              end
              iteration_data[0] = data.last['fnid'].to_i unless data.empty?
            end
            return Main.result_empty if data.empty?
            skip_ids_persistency&.save
            return { type: :object_list, data: data, name: 'id' }
          when :counters
            resp = @api_node.create('async/counters', pdata)[:data]['sync_counters'].first[asyncid].last
            return Main.result_empty if resp.nil?
            return { type: :single_object, data: resp }
          end
        end

        ACTIONS = %i[
          postprocess
          stream
          transfer
          cleanup
          forward
          access_key
          watch_folder
          service
          async
          sync
          central
          asperabrowser
          basic_token].concat(COMMON_ACTIONS).freeze

        def execute_action(command=nil, prefix_path=nil)
          command ||= options.get_next_command(ACTIONS)
          case command
          when *COMMON_ACTIONS then return execute_simple_common(command, prefix_path)
          when :async then return execute_async
          when :sync
            sync_command = options.get_next_command(%i[bandwidth counters files start state stop summary].concat(Plugin::ALL_OPS)-%i[modify])
            case sync_command
            when *Plugin::ALL_OPS then return entity_command(sync_command, @api_node, 'asyncs', item_list_key: 'ids')
            else
              parameters = options.get_option(:value)
              asyncs_id=instance_identifier
              if %i[start stop].include?(sync_command)
                @api_node.create("asyncs/#{asyncs_id}/#{sync_command}", parameters)
                return Main.result_status('ok')
              end
              return { type: :single_object, data: @api_node.read("asyncs/#{asyncs_id}/#{sync_command}", parameters)[:data] }
            end
          when :stream
            command = options.get_next_command(%i[list create show modify cancel])
            case command
            when :list
              resp = @api_node.read('ops/transfers', options.get_option(:value))
              return { type: :object_list, data: resp[:data], fields: %w[id status] } # TODO: useful?
            when :create
              resp = @api_node.create('streams', options.get_option(:value, is_type: :mandatory))
              return { type: :single_object, data: resp[:data] }
            when :show
              trid = options.get_next_argument('transfer id')
              resp = @api_node.read('ops/transfers/' + trid)
              return { type: :other_struct, data: resp[:data] }
            when :modify
              trid = options.get_next_argument('transfer id')
              resp = @api_node.update('streams/' + trid, options.get_option(:value, is_type: :mandatory))
              return { type: :other_struct, data: resp[:data] }
            when :cancel
              trid = options.get_next_argument('transfer id')
              resp = @api_node.cancel('streams/' + trid)
              return { type: :other_struct, data: resp[:data] }
            else
              raise 'error'
            end
          when :transfer
            command = options.get_next_command(%i[list cancel show])
            res_class_path = 'ops/transfers'
            if %i[cancel show].include?(command)
              one_res_id = instance_identifier
              one_res_path = "#{res_class_path}/#{one_res_id}"
            end
            case command
            when :list
              # could use ? subpath: 'transfers'
              query=options.get_option(:value) || options.get_option(:query)
              raise 'Query must be a Hash' unless query.nil? || query.is_a?(Hash)
              resp = @api_node.read(res_class_path, query)
              return {
                type:   :object_list,
                data:   resp[:data],
                fields: %w[id status start_spec.direction start_spec.remote_user start_spec.remote_host start_spec.destination_path]
              }
            when :cancel
              resp = @api_node.cancel(one_res_path)
              return { type: :other_struct, data: resp[:data] }
            when :show
              resp = @api_node.read(one_res_path)
              return { type: :other_struct, data: resp[:data] }
            else
              raise 'error'
            end
          when :access_key
            ak_command = options.get_next_command([:do].concat(Plugin::ALL_OPS))
            case ak_command
            when *Plugin::ALL_OPS then return entity_command(ak_command, @api_node, 'access_keys', id_default: 'self')
            when :do
              access_key = options.get_next_argument('access key id')
              ak_info=@api_node.read("access_keys/#{access_key}")[:data]
              # change API credentials if different access key
              if !access_key.eql?('self')
                @api_node.params[:auth][:username]=ak_info['id']
                @api_node.params[:auth][:password]=config.lookup_secret(url: @api_node.params[:base_url], username: ak_info['id'], mandatory: true)
              end
              command_repo = options.get_next_command(NODE4_COMMANDS)
              return execute_node_gen4_command(command_repo, ak_info['root_file_id'])
            end
          when :service
            command = options.get_next_command(%i[list create delete])
            if [:delete].include?(command)
              svcid = instance_identifier
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
              @api_node.delete("rund/services/#{svcid}")
              return Main.result_status("#{svcid} deleted")
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
              resp = @api_node.create(res_class_path, options.get_option(:value, is_type: :mandatory))
              return Main.result_status("#{resp[:data]['id']} created")
            when :list
              resp = @api_node.read(res_class_path, options.get_option(:value))
              return { type: :value_list, data: resp[:data]['ids'], name: 'id' }
            when :show
              return { type: :single_object, data: @api_node.read(one_res_path)[:data]}
            when :modify
              @api_node.update(one_res_path, options.get_option(:value, is_type: :mandatory))
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
            request_data = options.get_option(:value)
            request_data ||= {}
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
                Log.dump(:resp, resp)
                return { type: :object_list, data: resp['file_transfer_info_result']['file_transfer_info'], fields: %w[session_uuid file_id status path]}
              when :modify
                request_data.deep_merge!(validation) unless validation.nil?
                @api_node.update('services/rest/transfers/v1/files', request_data)
                return Main.result_status('updated')
              end
            end
          when :asperabrowser
            browse_params = {
              'nodeUser' => options.get_option(:username, is_type: :mandatory),
              'nodePW'   => options.get_option(:password, is_type: :mandatory),
              'nodeURL'  => options.get_option(:url, is_type: :mandatory)
            }
            # encode parameters so that it looks good in url
            encoded_params = Base64.strict_encode64(Zlib::Deflate.deflate(JSON.generate(browse_params))).gsub(/=+$/, '').tr('+/', '-_').reverse
            OpenApplication.instance.uri(options.get_option(:asperabrowserurl) + '?goto=' + encoded_params)
            return Main.result_status('done')
          when :basic_token
            return Main.result_status(Rest.basic_creds(options.get_option(:username, is_type: :mandatory), options.get_option(:password, is_type: :mandatory)))
          end # case command
          raise 'ERROR: shall not reach this line'
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Aspera
