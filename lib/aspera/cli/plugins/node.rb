# frozen_string_literal: true

# cspell:ignore snid fnid bidi ssync asyncs rund asnodeadmin mkfile mklink asperabrowser asperabrowserurl watchfolders watchfolderd entsrv
require 'aspera/schema/registry'
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

        application_name 'HSTS Node API'

        SESSION_TIME_FIELDS = %i[start end].freeze
        private_constant :SESSION_TIME_FIELDS

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
              Log.log.debug { "detect error: #{e}" }
            end
            raise error if error
            return
          end

          # Using /files/browse: is it a folder (node and shares)
          def gen3_entry_folder?(entry)
            FOLDER_TYPES.include?(entry['type'])
          end
        end

        # DSL option declarations - at class level, picked up by Base#initialize via ancestor chain.
        # Included by other plugins (Ats, Cos, Aoc) via `use_options Node`.
        option :validator,        description: 'Identifier of validator (optional for central)'
        option :asperabrowserurl, description: 'URL for simple aspera web ui', default: 'https://asperabrowser.mybluemix.net'
        option :node_api,         description: 'Gen4: standard_ports: Use standard FASP ports (true) or get from node API (false). cache: Set to false to force actual file system read',
          allowed: Hash, handler: {o: Api::Node, m: :api_options}
        option :root_id,          description: 'Gen4: File id of top folder when using access key (override AK root id)'
        option :dynamic_key,      description: 'Private key PEM to use for dynamic key auth', handler: {o: Api::Node, m: :use_dynamic_key}

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

        # DSL metadata for Gen3 root commands (description:, arguments:, transfer_paths:, aliases:).
        # :access_keys is skipped (intermediate node declared separately), :sync is declared separately.
        # action: entries are in GEN3_NODE_ACTIONS, or implicit.
        COMMANDS_GEN3_SPEC = {
          search:      {description: 'Search for files',             arguments: [{name: :path, type: String}]},
          space:       {description: 'Show space information',       arguments: [{name: :paths, multiple: true}]},
          mkdir:       {description: 'Create a folder (Gen3)',       arguments: [{name: :paths, multiple: true}]},
          mklink:      {description: 'Create a symbolic link (Gen3)', arguments: [{name: :target, type: String}, {name: :link_path, type: String}]},
          mkfile:      {description: 'Create a file (Gen3)', arguments: [{name: :path, type: String}, {name: :contents, mandatory: false, default: nil}]},
          rename:      {description: 'Rename a file or folder (Gen3)', arguments: [{name: :folder, type: String}, {name: :source, type: String}, {name: :destination, type: String}]},
          delete:      {description: 'Delete files or folders (Gen3)', arguments: [{name: :paths, multiple: true}]},
          ls:          {description: 'List files (Gen3)',            arguments: [{name: :path, type: String}], aliases: [:browse]},
          upload:      {description: 'Upload files (Gen3)',          transfer_paths: :send},
          download:    {description: 'Download files (Gen3)',        transfer_paths: :receive},
          cat:         {description: 'Show file contents (Gen3)',    arguments: [{name: :path, type: String}]},
          transport:   {description: 'Show transport parameters'},
          spec:        {description: 'Show transfer spec base'},
          api_details: {description: 'Show API details'},
          health:      {description: 'Check node health'},
          events:      {description: 'List events'},
          info:        {description: 'Show node info'},
          slash:       {description: 'Show root info'},
          license:     {description: 'Show license'},
          access_keys: {description: 'Manage access keys'}
        }.freeze

        private_constant :CENTRAL_SOAP_API_TEST, :SEARCH_REMOVE_FIELDS

        # Gen4 read commands also exposed on AoC packages (`aoc packages ls <id>`)
        NODE4_READ_ACTIONS = %i[bearer_token_node node_info ls find].freeze

        # DSL metadata for Gen4 commands under `access_keys do` (description:, arguments:, transfer_paths:, aliases:).
        # Other plugins expose this sub-tree with `mount:` (aoc, ats).
        # :sync, :permission and :v3 are excluded: they are intermediate nodes declared separately.
        SINGLE_PATH_ARG = [{name: :path, type: String}].freeze
        COMMANDS_GEN4_SPEC = {
          mkdir:             {description: 'Create folder',                  arguments: SINGLE_PATH_ARG},
          mklink:            {description: 'Create symbolic link',           arguments: SINGLE_PATH_ARG},
          mkfile:            {description: 'Create file',                    arguments: [{name: :path, type: String}, {name: :contents, mandatory: false, default: nil}]},
          rename:            {description: 'Rename entry',                   arguments: [{name: :source_path, type: String}, {name: :new_name, type: String}]},
          delete:            {description: 'Delete entry',                   arguments: [{name: :path, type: String, bulk: true}]},
          upload:            {description: 'Upload files',                   transfer_paths: :send},
          download:          {description: 'Download files',                 transfer_paths: :receive},
          modify:            {description: 'Modify file',                    arguments: [{name: :path, type: String}, {name: :file, type: Hash, schema: 'node:components.schemas.files-id-put-request'}]},
          cat:               {description: 'Show file contents',             arguments: SINGLE_PATH_ARG},
          show:              {description: 'Show file info',                 arguments: SINGLE_PATH_ARG},
          thumbnail:         {description: 'Show file thumbnail',            arguments: SINGLE_PATH_ARG},
          bearer_token_node: {description: 'Show bearer token for file node', arguments: SINGLE_PATH_ARG},
          node_info:         {description: 'Show node info for file',        arguments: SINGLE_PATH_ARG},
          ls:                {description: 'List files',                     arguments: SINGLE_PATH_ARG, aliases: [:browse]},
          find:              {description: 'Find files',                     arguments: SINGLE_PATH_ARG + FILTER_ARGS}
        }.freeze
        private_constant :SINGLE_PATH_ARG

        # Root commands exposed by `cos node` and `shares files` (mount: only:)
        COMMANDS_COS = %i[upload download info access_keys api_details transfer].freeze
        COMMANDS_SHARES = %i[api_details space mkdir mklink mkfile rename delete ls upload download cat sync transport spec].freeze
        # `browse` display fields for gen4
        GEN4_LS_FIELDS = %w[name type recursive_size size modified_time access_level].freeze

        # @param api [Rest] an existing API object for the Node API
        def initialize(context:, api: nil)
          super(context: context, basic_options: api.nil?)
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
        # @param path [String] starting path
        def browse_gen3(path)
          folders_to_process = path
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
          Aspera.assert(!(recursive && single_call), type: Cli::BadArgument) { 'options `recursive` and `skip` cannot be used together' }
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
              return Result::SingleObject.new(response['self']) if !Node.gen3_entry_folder?(response['self']) || only_path
              items = response['items']
              total_count ||= response['total_count']
              all_items.concat(items)
              if single_call
                formatter.display_item_count(response['item_count'], total_count)
                break
              end
              folders_to_process.concat(items.select { |i| Node.gen3_entry_folder?(i) }.map { |i| i['path'] }) if recursive
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

        # Resolve a NodeFileId from a path argument.
        # Supports %id:<file_id> syntax (returns NodeFileId for that id) or a plain path.
        # @param top_file_id [String] root file id for path resolution
        # @param path        [String] plain path or %id:<file_id> selector
        def apifid_from_path(top_file_id, path)
          if (m = Parser.percent_selector(path))
            Aspera.assert_values(m[:field], ['id'], type: BadArgument) { 'file id' }
            val = m[:value]
            return Api::NodeFileId.new(@api_node, val.nil? || val.empty? ? top_file_id : val)
          end
          @api_node.resolve_api_fid(top_file_id, path)
        end

        # Search /async by name
        # @param field [String] name of the field to search
        # @param value [String] value of the field to search
        # @return [Integer] id of the sync
        # @raise [Cli::BadArgument] if no such sync, or not by name
        def async_lookup(field, value)
          Aspera.assert_values(field, ['name'], type: Cli::BadArgument) { 'search field' }
          async_ids = @api_node.read('async/list')['sync_ids']
          summaries = @api_node.create('async/summary', {'syncs' => async_ids})['sync_summaries']
          selected = summaries.find { |s| s['name'].eql?(value) }
          raise Cli::BadIdentifier.new('sync', value, field: field) if selected.nil?
          return selected['snid']
        end

        # Lookup for access_keys: only supports %id:self selector.
        # @param field [String] must be 'id'
        # @param value [String] must be 'self'
        # @return [String] the resolved access key id
        def lookup_access_key_self_id(field, value, **)
          Aspera.assert(field.eql?('id') && value.eql?('self'), type: BadArgument) { 'only selector: %id:self' }
          @api_node.read('access_keys/self')['id']
        end

        # Search /asyncs by name
        # @param field [String] name of the field to search
        # @param value [String] value of the field to search
        # @return [Integer] id of the sync
        # @raise [Cli::BadArgument] if no such sync, or not by name
        def ssync_lookup(field, value)
          Aspera.assert_values(field, ['name'], type: Cli::BadArgument) { 'search field' }
          @api_node.read('asyncs')['ids'].each do |id|
            sync_info = @api_node.read("asyncs/#{id}")['configuration']
            # name is unique, so we can return
            return id if sync_info[field].eql?(value)
          end
          raise Cli::BadIdentifier.new('ssync', value, field: field)
        end

        # --- DSL command declarations ---

        # Gen3 leaf commands — metadata from COMMANDS_GEN3_SPEC; action: added where node-specific.
        # :sync is declared separately (intermediate node with sub-commands).
        GEN3_NODE_ACTIONS = {
          ls:          ->(path:, **) { browse_gen3(path) },
          transport:   ->(**) { Result::SingleObject.new(@api_node.transport_params) },
          spec:        ->(**) { Result::SingleObject.new(@api_node.base_spec, fields: Formatter.all_but(*Transfer::Spec::SPECIFIC)) },
          api_details: ->(**) { Result::SingleObject.new({base_url: @api_node.base_url}.merge(@api_node.params)) },
          events:      ->(**) { Result::ObjectList.new(@api_node.read('events', query_read_delete(schema: Schema::Registry.query_params(Schema::Registry::NODE, 'events'))), fields: ->(f) { !f.start_with?('data') }) },
          info:        ->(**) { Result::SingleObject.new(@api_node.read('info')) },
          slash:       ->(**) { Result::SingleObject.new(@api_node.read('')) },
          license:     ->(**) { Result::SingleObject.new(@api_node.read('license')) }
        }.freeze
        private_constant :GEN3_NODE_ACTIONS
        COMMANDS_GEN3_SPEC.each do |cmd, spec|
          next if cmd.eql?(:access_keys) # intermediate node declared separately below
          action = GEN3_NODE_ACTIONS[cmd]
          command cmd, **spec, **(action ? {action: action} : {})
        end
        command :sync, description: 'Synchronize folders (Gen3)'
        commands_under :sync do
          Sync::Operations::DIRECTIONS.each do |dir|
            command dir, description: "#{dir.capitalize}-sync (Gen3)", transfer_paths: :send, arguments: SyncActions::PATH_AND_INFO_ARGS
          end
          command :admin, description: 'Manage sync database (admin operations)'
          SyncActions.register_sync_admin_commands(self, :admin)
        end
        # access_keys sub-tree
        command :access_keys, description: 'Manage access keys'
        commands_under :access_keys do
          command :do, description: 'Execute Gen4 command via access key',
            arguments: [{name: :access_key_id, type: :identifier}],
            setup: :setup_access_key_do
          command :set_bearer_key, description: 'Set bearer key on access key',
            arguments: [{name: :access_key_id}, {name: :bearer_key_pem, type: String}]
          crud_commands entity: 'access_keys',
            api:            :@api_node,

            body_component: Schema::Registry::NODE,
            lookup:         :lookup_access_key_self_id
        end

        commands_under %i[access_keys do] do
          COMMANDS_GEN4_SPEC.each do |cmd, spec|
            command cmd, **spec
          end
          command :v3, description: 'Legacy v3 commands on files', mount: {plugin: self, instance: :v3_node_plugin}
          command :permission, description: 'Manage permissions',
            arguments: [{name: :path, type: String, description: 'Path, or %id:<file id>, or %id: for root'}],
            setup: :setup_access_key_do_permission
          command :sync, description: 'Synchronize folders'
          commands_under :sync do
            Sync::Operations::DIRECTIONS.each do |dir|
              command dir, description: "#{dir.capitalize}-sync", transfer_paths: :send, arguments: SyncActions::PATH_AND_INFO_ARGS
            end
            command :admin, description: 'Manage sync database (admin operations)'
            SyncActions.register_sync_admin_commands(self, :admin)
          end
        end
        commands_under %i[access_keys do permission] do
          command :list,   description: 'List permissions on a file'
          command :show,   description: 'Show a permission',
            arguments: [{name: :permission_id, type: :identifier}],
            action: ->(apifid:, permission_id:, **) { Result::SingleObject.new(apifid.node_api.read("permissions/#{permission_id}")) }
          command :create, description: 'Create a permission',
            arguments: [{name: :permission, type: Hash, schema: 'node:components.schemas.permissions-post-request'}]
          command(
            :modify, description: 'Modify a permission',
            arguments: [{name: :permission_id, type: :identifier}, {name: :permission, type: Hash, schema: 'node:components.schemas.permissions-id-put-request'}],
            action: lambda do |permission:, apifid:, permission_id:, **|
              apifid.node_api.update("permissions/#{permission_id}", permission)
              Result::Status.new('Updated')
            end
          )
          command :delete, description: 'Delete permissions',
            arguments: [{name: :permission_id, bulk: true}]
        end
        # async (legacy /async)
        commands_under :async, description: 'synchronization (legacy /async)' do
          command :list,      description: 'List async sync IDs', action: ->(**) { Result::ValueList.new(@api_node.read('async/list')['sync_ids']) }
          command :show,      description: 'Show async summary',
            arguments: [{name: :async_id, type: :identifier, lookup: :async_lookup}]
          command(
            :delete, description: 'Delete async',
            arguments: [{name: :async_id, type: :identifier, lookup: :async_lookup}],
            action: lambda do |async_id:, **|
              async_ids = async_id.eql?(SpecialValues::ALL) ? @api_node.read('async/list')['sync_ids'] : [async_id]
              Result::SingleObject.new(@api_node.create('async/delete', {'syncs' => async_ids}))
            end
          )
          command :bandwidth, description: 'Show async bandwidth',
            arguments: [{name: :async_id, type: :identifier, lookup: :async_lookup}]
          command :files,     description: 'List async files',
            arguments: [{name: :async_id, type: :identifier, lookup: :async_lookup}]
          command :counters,  description: 'Show async counters',
            arguments: [{name: :async_id, type: :identifier, lookup: :async_lookup}]
        end
        # ssync (/asyncs)
        commands_under :ssync, description: 'synchronization (/asyncs)' do
          crud_commands entity: 'asyncs',
            name: 'sync session',
            id_name: :ssync_id,
            api: :@api_node,
            operations: %i[create list show delete],
            items_key: 'ids',
            lookup: :ssync_lookup
          command(
            :start, description: 'Start a sync', arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: lambda do |ssync_id:, **|
              @api_node.call(operation: 'POST', subpath: "asyncs/#{ssync_id}/start", content_type: Mime::TEXT, body: '', ret: :resp).body
              Result::Status.new('Done')
            end
          )
          command(
            :stop, description: 'Stop a sync', arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: lambda do |ssync_id:, **|
              @api_node.call(operation: 'POST', subpath: "asyncs/#{ssync_id}/stop", content_type: Mime::TEXT, body: '', ret: :resp).body
              Result::Status.new('Done')
            end
          )
          command :bandwidth, description: 'Show sync bandwidth',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Result::SingleObject.new(@api_node.read("asyncs/#{ssync_id}/bandwidth", options.get_option(:query) || {})) }
          command :counters, description: 'Show sync counters',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Result::SingleObject.new(@api_node.read("asyncs/#{ssync_id}/counters", options.get_option(:query) || {})) }
          command :files, description: 'List sync files',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Result::SingleObject.new(@api_node.read("asyncs/#{ssync_id}/files", options.get_option(:query) || {})) }
          command :state, description: 'Show sync state',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Result::SingleObject.new(@api_node.read("asyncs/#{ssync_id}/state")) }
          command :summary, description: 'Show sync summary',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Result::SingleObject.new(@api_node.read("asyncs/#{ssync_id}/summary")) }
        end
        # stream
        command :stream, description: 'Manage stream operations'
        commands_under :stream do
          command :list,   description: 'List streams', action: ->(**) { Result::ObjectList.new(@api_node.read('ops/transfers', query_read_delete), fields: %w[id status]) }
          command :create, description: 'Create a stream',
            arguments: [{name: :stream, type: Hash, schema: 'node:components.schemas.transferPostRequest'}],
            action: ->(stream:, **) { Result::SingleObject.new(@api_node.create('streams', stream)) }
          command :show,   description: 'Show a stream',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: ->(transfer_id:, **) { Result::SingleObject.new(@api_node.read("ops/transfers/#{transfer_id}")) }
          command :modify, description: 'Modify a stream',
            arguments: [{name: :transfer_id, type: :identifier}, {name: :stream, type: Hash, schema: 'node:components.schemas.transferPutRequest'}],
            action: ->(stream:, transfer_id:, **) { Result::SingleObject.new(@api_node.update("streams/#{transfer_id}", stream)) }
          command :cancel, description: 'Cancel a stream',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: ->(transfer_id:, **) { Result::SingleObject.new(@api_node.cancel("streams/#{transfer_id}")) }
        end
        # transfer
        command :transfer, description: 'Manage transfer operations'
        commands_under :transfer do
          command :list, description: 'List transfers'
          command(
            :cancel, description: 'Cancel a transfer',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: lambda do |transfer_id:, **|
              @api_node.cancel("ops/transfers/#{transfer_id}")
              Result::Status.new('Cancelled')
            end
          )
          command :show, description: 'Show a transfer',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: ->(transfer_id:, **) { Result::SingleObject.new(@api_node.read("ops/transfers/#{transfer_id}")) }
          command(
            :modify, description: 'Modify a transfer',
            arguments: [{name: :transfer_id, type: :identifier}, {name: :transfer, type: Hash, schema: 'node:components.schemas.transferPutRequest'}],
            action: lambda do |transfer:, transfer_id:, **|
              @api_node.update("ops/transfers/#{transfer_id}", transfer)
              Result::Status.new('Modified')
            end
          )
          command :bandwidth_average, description: 'Show average bandwidth per period'
          command :sessions,          description: 'List transfer sessions'
        end
        # service
        command :service, description: 'Manage services'
        commands_under :service do
          command :list, description: 'List services', action: ->(**) { Result::ObjectList.new(@api_node.read('rund/services')['services']) }
          command(
            :create, description: 'Create a service',
            arguments: [{name: :service, type: Hash}],
            action: lambda do |service:, **|
              resp = @api_node.create('rund/services', service)
              Result::Status.new("#{resp['id']} created")
            end
          )
          command(
            :delete, description: 'Delete a service',
            arguments: [{name: :service_id, type: :identifier}],
            action: lambda do |service_id:, **|
              @api_node.delete("rund/services/#{service_id}")
              Result::Status.new("#{service_id} deleted")
            end
          )
        end
        # watch_folder
        command :watch_folder, description: 'Manage watch folders', setup: :setup_watch_folder
        commands_under :watch_folder do
          command :create, description: 'Create a watch folder',
            arguments: [{name: :watch_folder, type: Hash}],
            action: ->(watch_folder:, **) { Result::Status.new("#{@api_node.create('v3/watchfolders', watch_folder)['id']} created") }
          command :list,   description: 'List watch folders',
            action: ->(**) { Result::ValueList.new(@api_node.read('v3/watchfolders', query_read_delete)['ids']) }
          command :show,   description: 'Show a watch folder',
            arguments: [{name: :watch_folder_id, type: :identifier}],
            action: ->(watch_folder_id:, **) { Result::SingleObject.new(@api_node.read("v3/watchfolders/#{watch_folder_id}")) }
          command(
            :modify, description: 'Modify a watch folder',
            arguments: [{name: :watch_folder_id, type: :identifier}, {name: :watch_folder, type: Hash}],
            action: lambda do |watch_folder:, watch_folder_id:, **|
              @api_node.update("v3/watchfolders/#{watch_folder_id}", watch_folder)
              Result::Status.new("#{watch_folder_id} updated")
            end
          )
          command(
            :delete, description: 'Delete a watch folder',
            arguments: [{name: :watch_folder_id, type: :identifier}],
            action: lambda do |watch_folder_id:, **|
              @api_node.delete("v3/watchfolders/#{watch_folder_id}")
              Result::Status.new("#{watch_folder_id} deleted")
            end
          )
          command :state, description: 'Show watch folder state',
            arguments: [{name: :watch_folder_id, type: :identifier}],
            action: ->(watch_folder_id:, **) { Result::SingleObject.new(@api_node.read("v3/watchfolders/#{watch_folder_id}/state")) }
        end
        # central
        command :central, description: 'Query Central service'
        commands_under :central do
          command :session, description: 'Query sessions'
          command :file,    description: 'Query files'
        end
        commands_under %i[central session] do
          command :list, description: 'List sessions',
            arguments: [{name: :criteria, type: Hash, mandatory: false, default: nil}]
        end
        commands_under %i[central file] do
          command :list,   description: 'List file transfers',
            arguments: [{name: :criteria, type: Hash, mandatory: false, default: nil}]
          command :modify, description: 'Modify file transfer validation',
            arguments: [{name: :file, type: Hash, mandatory: false, default: nil}]
        end
        # Standalone leaf commands
        command :asperabrowser, description: 'Open Aspera browser'
        command :basic_token,   description: 'Generate basic auth token', action: ->(**) { Result::Text.new(Rest.basic_authorization(options.get_option(:username, mandatory: true), options.get_option(:password, mandatory: true))) }
        command(
          :bearer_token, description: 'Generate bearer token',
          arguments: [{name: :private_key_pem, type: String}, {name: :token, type: Hash, schema: 'opts:components.schemas.NodeBearerTokenOptions'}],
          action: lambda do |private_key_pem:, token:, **|
            private_key = OpenSSL::PKey::RSA.new(private_key_pem)
            access_key  = options.get_option(:username, mandatory: true)
            Result::Text.new(Api::Node.bearer_token(payload: token, access_key: access_key, private_key: private_key))
          end
        )
        command :simulator,     description: 'Start node simulator',
          arguments: [{name: :parameters, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.NodeSimulatorOptions'}]
        command :telemetry,     description: 'Report telemetry to external system',
          arguments: [{name: :parameters, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.NodeTelemetryOptions'}]

        # --- Handler methods (Gen3) ---

        def action_delete(paths:, **)
          # TODO: add query for recursive
          paths_to_delete = Array(paths)
          resp = @api_node.create('files/delete', {paths: paths_to_delete.map { |i| {'path' => i.start_with?('/') ? i : "/#{i}"} }})
          cli_result_from_paths_response(resp, 'file deleted')
        end

        def action_search(path:, **)
          parameters = {'path' => path}
          other_options = options.get_option(:query)
          parameters.merge!(other_options) unless other_options.nil?
          resp = @api_node.create('files/search', parameters)
          return Result::Empty.new if resp['items'].empty?
          fields = resp['items'].first.keys.reject { |i| SEARCH_REMOVE_FIELDS.include?(i) }
          formatter.display_item_count(resp['item_count'], resp['total_count'])
          formatter.display_status("params: #{resp['parameters'].keys.map { |k| "#{k}:#{resp['parameters'][k]}" }.join(',')}")
          Result::ObjectList.new(resp['items'], fields: fields)
        end

        def action_space(paths:, **)
          paths = Array(paths)
          resp = @api_node.create('space', {'paths' => paths.map { |i| {path: i} }})
          Result::ObjectList.new(resp['paths'])
        end

        def action_mkdir(paths:, **)
          paths = Array(paths)
          resp = @api_node.create('files/create', {'paths' => paths.map { |i| {type: :directory, path: i} }})
          cli_result_from_paths_response(resp, 'folder created')
        end

        def action_mklink(target:, link_path:, **)
          resp = @api_node.create('files/create', {'paths' => [{type: :symbolic_link, path: link_path, target: {path: target}}]})
          cli_result_from_paths_response(resp, 'link created')
        end

        def action_mkfile(path:, contents:, **)
          contents64 = contents.nil? ? '' : Base64.strict_encode64(contents)
          resp = @api_node.create('files/create', {'paths' => [{type: :file, path: path, contents: contents64}]})
          cli_result_from_paths_response(resp, 'file created')
        end

        def action_rename(folder:, source:, destination:, **)
          # TODO: multiple ?
          resp = @api_node.create('files/rename', {'paths' => [{'path' => folder, 'source' => source, 'destination' => destination}]})
          cli_result_from_paths_response(resp, 'entry moved')
        end

        # Obtains a transfer spec via the Node API for the given direction/folders.
        def sync_gen3_block
          lambda do |direction, local_path, remote_path|
            request_transfer_spec = sync_spec_request(direction, local_path, remote_path)
            @api_node.add_tspec_info(request_transfer_spec) if @api_node.respond_to?(:add_tspec_info)
            transfer_spec = @api_node.create(
              'files/sync_setup',
              {transfer_requests: [{transfer_request: request_transfer_spec}]}
            )['transfer_specs'].first['transfer_spec']
            transfer_spec.delete_if { |_k, v| v.nil? }
            Log.dump(:ts, transfer_spec)
            transfer_spec
          end
        end

        Sync::Operations::DIRECTIONS.each do |dir|
          define_method(:"action_sync_#{dir}") { |path:, sync_info: {}, **| run_sync_transfer(dir, path: path, sync_info: sync_info, &sync_gen3_block) }
        end

        def action_upload(**)
          # empty transfer spec for authorization request
          request_transfer_spec = {}
          request_transfer_spec[:paths] = [{destination: transfer.destination_folder(Transfer::Spec::DIRECTION_SEND)}]
          # add fixed parameters if any (for COS)
          @api_node.add_tspec_info(request_transfer_spec) if @api_node.respond_to?(:add_tspec_info)
          Api::Node.add_public_key(request_transfer_spec)
          setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
          transfer_spec = @api_node.create('files/upload_setup', setup_payload)['transfer_specs'].first['transfer_spec']
          Api::Node.add_private_key(transfer_spec)
          transfer_spec.delete('paths')
          Runner.result_transfer(transfer.start(transfer_spec))
        end

        def action_download(**)
          # empty transfer spec for authorization request
          request_transfer_spec = {}
          request_transfer_spec[:paths] = transfer.ts_source_paths
          # add fixed parameters if any (for COS)
          @api_node.add_tspec_info(request_transfer_spec) if @api_node.respond_to?(:add_tspec_info)
          Api::Node.add_public_key(request_transfer_spec)
          setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
          transfer_spec = @api_node.create('files/download_setup', setup_payload)['transfer_specs'].first['transfer_spec']
          Api::Node.add_private_key(transfer_spec)
          Runner.result_transfer(transfer.start(transfer_spec))
        end

        def action_cat(path:, **)
          http = @api_node.read("files/#{URI.encode_www_form_component(path)}/contents", ret: :resp)
          Result::Text.new(http.body)
        end

        def action_health(**)
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
        def setup_watch_folder(**)
          @api_node.params[:headers] ||= {}
          @api_node.params[:headers]['X-aspera-WF-version'] = '2017_10_23'
          {}
        end

        # access_keys > do - setup: resolve access key and root file id
        # @return [Hash] context hash containing :do_root_file_id
        def setup_access_key_do(access_key_id:, **)
          @do_root_file_id = options.get_option(:root_id)
          if @do_root_file_id.nil?
            ak_info = @api_node.read("access_keys/#{access_key_id}")
            ak_secret = context.secret_finder.lookup(url: @api_node.base_url, username: ak_info['id'])
            if !access_key_id.eql?('self')
              Aspera.assert(ak_secret, type: Cli::MissingArgument) { "Please provide secret for #{ak_info['id']} using option: secret or by setting a preset for #{ak_info['id']}@#{@api_node.base_url}." }
              @api_node.auth_params[:username] = ak_info['id']
              @api_node.auth_params[:password] = ak_secret
            end
            @do_root_file_id = ak_info['root_file_id']
          end
          {do_root_file_id: @do_root_file_id}
        end

        # access_keys > do > permission - setup: resolve apifid from the path argument of the node
        # do_root_file_id: comes from ctx (setup_access_key_do, or seed of a mount)
        # @return [Hash] context hash containing :apifid
        def setup_access_key_do_permission(do_root_file_id:, path:, **)
          {apifid: apifid_from_path(do_root_file_id, path)}
        end

        # access_keys > do > ls
        def action_access_keys_do_ls(path:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          file_info = apifid.node_api.read("files/#{apifid.file_id}", headers: Api::Node.add_cache_control)
          return Result::ObjectList.new([file_info], fields: GEN4_LS_FIELDS) unless file_info['type'].eql?('folder')
          Result::ObjectList.new(apifid.node_api.list_files(apifid.file_id, query: query_read_delete), fields: GEN4_LS_FIELDS)
        end

        # access_keys > do > find
        def action_access_keys_do_find(path:, filter: nil, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Result::ObjectList.new(@api_node.find_files(apifid.file_id, Base.file_matcher(filter)), fields: ['path'])
        end

        # access_keys > do > cat
        def action_access_keys_do_cat(path:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Result::Text.new(apifid.node_api.read("files/#{apifid.file_id}/content", ret: :resp).body)
        end

        # access_keys > do > show
        def action_access_keys_do_show(path:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Result::SingleObject.new(apifid.node_api.read("files/#{apifid.file_id}"))
        end

        # access_keys > do > modify
        def action_access_keys_do_modify(path:, file:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          apifid.node_api.update("files/#{apifid.file_id}", file)
          Result::Status.new('Done')
        end

        # access_keys > do > thumbnail
        def action_access_keys_do_thumbnail(path:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Result::Image.new(apifid.node_api.read("files/#{apifid.file_id}/preview", headers: {'Accept' => 'image/png'}, ret: :resp).body)
        end

        # access_keys > do > rename
        def action_access_keys_do_rename(source_path:, new_name:, do_root_file_id:, **)
          apifid = @api_node.resolve_api_fid(do_root_file_id, source_path)
          apifid.node_api.update("files/#{apifid.file_id}", {name: new_name})
          Result::Status.new("renamed to #{new_name}")
        end

        # access_keys > do > delete
        def action_access_keys_do_delete(path:, do_root_file_id:, **)
          bulk_result(path, command: :delete, id_result: 'path') do |l_path|
            apifid = if (m = Parser.percent_selector(l_path))
              Aspera.assert_values(m[:field], ['id'], type: BadIdentifier)
              Api::NodeFileId.new(@api_node, m[:value])
            else
              @api_node.resolve_api_fid(do_root_file_id, l_path)
            end
            apifid.node_api.delete("files/#{apifid.file_id}")
            {'path' => l_path}
          end
        end

        # Shared Gen4 sync block: obtains a transfer spec via the Gen4 API for the given direction/remote_path.
        def sync_gen4_block(do_root_file_id)
          lambda do |direction, _local_path, remote_path|
            ts_direction = direction.eql?(:pull) ? Transfer::Spec::DIRECTION_RECEIVE : Transfer::Spec::DIRECTION_SEND
            apifid = @api_node.resolve_api_fid(do_root_file_id, remote_path)
            apifid.node_api.transfer_spec_gen4(apifid.file_id, ts_direction)
          end
        end

        Sync::Operations::DIRECTIONS.each do |dir|
          define_method(:"action_access_keys_do_sync_#{dir}") do |path:, sync_info: {}, do_root_file_id:, **|
            run_sync_transfer(dir, path: path, sync_info: sync_info, &sync_gen4_block(do_root_file_id))
          end
        end

        # access_keys > do > upload
        def action_access_keys_do_upload(do_root_file_id:, **)
          apifid = @api_node.resolve_api_fid(do_root_file_id, transfer.destination_folder(Transfer::Spec::DIRECTION_SEND), true)
          Runner.result_transfer(transfer.start(apifid.node_api.transfer_spec_gen4(apifid.file_id, Transfer::Spec::DIRECTION_SEND)))
        end

        # access_keys > do > download
        def action_access_keys_do_download(do_root_file_id:, **)
          apifid, source_paths = @api_node.resolve_api_fid_paths(do_root_file_id, transfer.ts_source_paths)
          Runner.result_transfer(transfer.start(apifid.node_api.transfer_spec_gen4(apifid.file_id, Transfer::Spec::DIRECTION_RECEIVE, {'paths'=>source_paths})))
        end

        # access_keys > do > v3 - mount target: Node plugin on the node hosting the root file
        # @return [Node]
        def v3_node_plugin(do_root_file_id:, **)
          Node.new(context: context, api: @api_node.resolve_api_fid(do_root_file_id, '').node_api)
        end

        # access_keys > do > node_info / bearer_token_node — shared helper builds the result hash
        def gen4_apifid_info(do_root_file_id, path)
          apifid = apifid_from_path(do_root_file_id, path)
          result = {url: apifid.node_api.base_url, root_id: apifid.file_id}
          case apifid.node_api.auth_params[:type]
          when :basic
            result[:username] = apifid.node_api.auth_params[:username]
            result[:password] = apifid.node_api.auth_params[:password]
          when :oauth2
            result[:username] = apifid.node_api.params[:headers][Api::Node::HEADER_X_ASPERA_ACCESS_KEY]
            result[:password] = apifid.node_api.oauth.authorization
          else Aspera.error_unexpected_value(apifid.node_api.auth_params[:type]) { 'Node API Auth type' }
          end
          [apifid, result]
        end

        def action_access_keys_do_node_info(path:, do_root_file_id:, **)
          _apifid, result = gen4_apifid_info(do_root_file_id, path)
          Result::SingleObject.new(result)
        end

        def action_access_keys_do_bearer_token_node(path:, do_root_file_id:, **)
          apifid, result = gen4_apifid_info(do_root_file_id, path)
          Log.dump(:result, result)
          Aspera.assert(apifid.node_api.auth_params[:type].eql?(:oauth2), type: BadArgument) { "Cannot get bearer token if authenticating with secret (#{apifid.node_api.auth_params[:type]})" }
          Aspera.assert(OAuth::Factory.bearer_auth?(result[:password]), 'Not using bearer token auth')
          Result::Text.new(result[:password])
        end

        # access_keys > do > mkdir / mklink / mkfile — shared helper: resolve parent folder,
        # build payload from query option, optionally check for name collision.
        # @return [Array(NodeFileId, Hash)] parent apifid and payload with :name set
        # @param path [String] full path (folder/name)
        def gen4_mk_resolve(top_file_id, path)
          containing_folder_path, new_item = Api::Node.split_folder(path)
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
            found = folder_content.find { |i| i['name'].eql?(new_item) || i['name'].eql?(link_name) }
            Aspera.assert(!found, type: Cli::Error) { "A #{found['type']} already exists with name #{new_item}" }
          end
          [apifid, payload]
        end

        def action_access_keys_do_mkdir(path:, do_root_file_id:, **)
          apifid, payload = gen4_mk_resolve(do_root_file_id, path)
          payload[:type] = :folder
          Result::SingleObject.new(apifid.node_api.create("files/#{apifid.file_id}/files", payload))
        end

        def action_access_keys_do_mklink(path:, do_root_file_id:, **)
          apifid, payload = gen4_mk_resolve(do_root_file_id, path)
          payload[:type] = :link
          Aspera.assert(payload[:target_id], 'Missing target_id')
          Aspera.assert(payload[:target_node_id], 'Missing target_node_id')
          Result::SingleObject.new(apifid.node_api.create("files/#{apifid.file_id}/files", payload))
        end

        def action_access_keys_do_mkfile(path:, contents:, do_root_file_id:, **)
          apifid, payload = gen4_mk_resolve(do_root_file_id, path)
          payload[:type] = :file
          payload[:contents] = contents.nil? ? '' : Base64.strict_encode64(contents)
          Result::SingleObject.new(apifid.node_api.create("files/#{apifid.file_id}/files", payload))
        end

        # access_keys > do > permission > list/show/create/modify/delete
        def action_access_keys_do_permission_list(apifid:, **)
          list_query = query_read_delete(default: Rest.php_style({'include' => %w[access_level permission_count]}))
          # Specify file to get permissions for unless not specified (then, get all permissions)
          list_query['file_id'] = apifid.file_id unless apifid.file_id.to_s.empty?
          list_query['inherited'] = false if list_query.key?('file_id') && !list_query.key?('inherited')
          Result::ObjectList.new(apifid.node_api.read_with_pages('permissions', list_query))
        end

        def action_access_keys_do_permission_delete(permission_id:, apifid:, **)
          bulk_result(permission_id, command: :delete) do |one_id|
            apifid.node_api.delete("permissions/#{one_id}")
            the_app = apifid.node_api.app_info
            the_app&.api&.permissions_send_event(event_data: {}, app_info: the_app, types: ['permission.deleted'])
            {'id' => one_id}
          end
        end

        def action_access_keys_do_permission_create(permission:, apifid:, **)
          create_param = permission
          Aspera.assert(!create_param.key?('file_id'), type: Cli::BadArgument) { 'no file_id' }
          create_param['file_id'] = apifid.file_id
          create_param['access_levels'] = Api::Node::ACCESS_LEVELS unless create_param.key?('access_levels')
          the_app = apifid.node_api.app_info
          the_app&.api&.permissions_set_create_params(perm_data: create_param, app_info: the_app)
          created_data = apifid.node_api.create('permissions', create_param)
          the_app&.api&.permissions_send_event(event_data: created_data, app_info: the_app)
          Result::SingleObject.new(created_data)
        end

        # access_keys > set_bearer_key
        def action_access_keys_set_bearer_key(access_key_id:, bearer_key_pem:, **)
          access_key_id = @api_node.read('access_keys/self')['id'] if access_key_id.eql?('self')
          key = OpenSSL::PKey.read(bearer_key_pem)
          key = key.public_key if key.private?
          @api_node.update("access_keys/#{access_key_id}", {token_verification_key: key.to_pem})
          Result::Status.new('public key updated')
        end

        # async sub-commands: individual handlers
        def action_async_show(async_id:, **)
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

        def action_async_bandwidth(async_id:, **)
          Integer(async_id)
          post_data = {'syncs' => [async_id], 'seconds' => 100}
          resp = @api_node.create('async/bandwidth', post_data)
          data = resp['bandwidth_data']
          return Result::Empty.new if data.empty?
          Result::ObjectList.new(data.first[async_id]['data'])
        end

        def action_async_files(async_id:, **)
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
            data.select! { |l| l['fnid'].to_i > iteration_data.first } unless iteration_data.first.nil?
            iteration_data[0] = data.last['fnid'].to_i unless data.empty?
          end
          return Result::Empty.new if data.empty?
          skip_ids_persistency&.save
          Result::ObjectList.new(data)
        end

        def action_async_counters(async_id:, **)
          Integer(async_id)
          resp = @api_node.create('async/counters', {'syncs' => [async_id]})['sync_counters'].first[async_id].last
          return Result::Empty.new if resp.nil?
          Result::SingleObject.new(resp)
        end

        # transfer sub-commands
        def action_transfer_list(**)
          transfer_filter = query_read_delete(default: {}, schema: Schema::Registry.query_params(Schema::Registry::NODE, 'ops/transfers'))
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

        def action_transfer_sessions(**)
          transfers_data = @api_node.read('ops/transfers', query_read_delete(schema: Schema::Registry.query_params(Schema::Registry::NODE, 'ops/transfers')))
          sessions = transfers_data.flat_map { |t| t['sessions'] }
          sessions.each do |session|
            SESSION_TIME_FIELDS.each do |what|
              session["#{what}_time"] = session["#{what}_time_usec"] ? Time.at(session["#{what}_time_usec"] / 1_000_000.0).utc.iso8601(0) : nil
            end
          end
          Result::ObjectList.new(sessions, fields: %w[id status start_time end_time target_rate_kbps])
        end

        def action_transfer_bandwidth_average(**)
          transfers_data = @api_node.read('ops/transfers', query_read_delete(schema: Schema::Registry.query_params(Schema::Registry::NODE, 'ops/transfers')))
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
              [dir, dir_info.to_h { |k2| [k2, 0] }]
            end
            transfers_data.each do |t|
              next if t['avg_rate_kbps'].zero?
              next if t['start_time_usec'] >= end_date || t['end_time_usec'] <= start_date
              info = period_bandwidth[t['start_spec']['direction'].to_sym]
              info[:avg_kbps] += t['avg_rate_kbps']
              info[:sessions] += 1
            end
            next if Transfer::Spec::DIRECTION_ENUM_VALUES.map(&:to_sym).all? { |dir| period_bandwidth[dir][:sessions].zero? }
            result.push({start: Time.at(start_date / 1_000_000), end: Time.at(end_date / 1_000_000)}.merge(period_bandwidth))
          end
          Result::ObjectList.new(result)
        end

        # central: shared helper
        def central_validation
          validator_id = options.get_option(:validator)
          validator_id ? {'validator_id' => validator_id} : nil
        end

        # central > session > list
        def action_central_session_list(criteria:, **)
          criteria ||= {}
          validation = central_validation
          criteria.deep_merge!({'validation' => validation}) unless validation.nil?
          resp = @api_node.create('services/rest/transfers/v1/sessions', criteria)
          Result::ObjectList.new(resp['session_info_result']['session_info'], fields: %w[session_uuid status transport direction bytes_transferred])
        end

        # central > file > list
        def action_central_file_list(criteria:, **)
          criteria ||= {}
          validation = central_validation
          criteria.deep_merge!({'validation' => validation}) unless validation.nil?
          resp = @api_node.create('services/rest/transfers/v1/files', criteria)
          resp = JSON.parse(resp) if resp.is_a?(String)
          Log.dump(:resp, resp)
          Result::ObjectList.new(resp['file_transfer_info_result']['file_transfer_info'], fields: %w[session_uuid file_id status path])
        end

        # central > file > modify
        def action_central_file_modify(file:, **)
          file ||= {}
          validation = central_validation
          file.deep_merge!(validation) unless validation.nil?
          @api_node.update('services/rest/transfers/v1/files', file)
          Result::Status.new('updated')
        end

        def action_asperabrowser(**)
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

        def action_simulator(parameters: {}, **)
          require 'aspera/node_simulator'
          parameters = parameters.symbolize_keys
          uri = URI.parse(parameters.delete(:url) { WebServerSimple::DEFAULT_URL })
          server = WebServerSimple.new(uri, **parameters.slice(*WebServerSimple::PARAMS))
          server.mount(uri.path, NodeSimulatorServlet, parameters.except(*WebServerSimple::PARAMS), NodeSimulator.new)
          server.start
          return Result::Status.new('Simulator terminated')
        end

        def action_telemetry(parameters: {}, **)
          parameters = parameters.symbolize_keys
          %i[url key].each do |psym|
            Aspera.assert(parameters.key?(psym), type: Cli::BadArgument) { "Missing parameter: #{psym}" }
          end
          require 'socket'
          parameters[:interval] = 10 unless parameters.key?(:interval)
          parameters[:hostname] = Socket.gethostname unless parameters.key?(:hostname)
          interval = parameters[:interval].to_f
          Aspera.assert(interval > 0, type: Cli::BadArgument) { 'Interval must be a positive number in seconds' }
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
              Log.log.error { "#{p['error']['user_message']} : #{p['path']}" }
              result = p['error']['user_message']
              errors.push([p['path'], p['error']['user_message']])
            end
            obj_list.push({'path' => p['path'], 'result' => result})
          end
          # one error make all fail
          raise errors.map { |i| "#{i.first}: #{i.last}" }.join(', ') unless errors.empty?
          obj_list
        end

        # Translates paths results into CLI result, and removes prefix
        def cli_result_from_paths_response(response, success_msg)
          obj_list = response_to_result(response, success_msg)
          return Result::ObjectList.new(obj_list, fields: %w[path result])
        end
      end
    end
  end
end
