# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# cspell:ignore asperabrowserurl
require_relative '../../schema/registry'
require_relative '../../sealed_hash'
require_relative '../../cli/plugins/basic_auth'
require_relative '../../cli/hints'
require_relative '../xfer/sync_actions'
require_relative '../../cli/special_values'
require_relative '../../transfer/spec'
require_relative '../../nagios'
require_relative '../../hash_ext'
require_relative '../../id_generator'
require_relative 'api'
require_relative '../../oauth/client/factory'
require_relative '../../rest/list'
require_relative '../../assert'
require_relative '../xfer/transfer_agent'
require 'base64'

module Aspera
  module Plugins
    module Node
      class Commands < Cli::Plugins::Base
        include Cli::Plugins::BasicAuth

        include Aspera::Plugins::Xfer::SyncActions

        application_name 'HSTS Node API'

        SESSION_TIME_FIELDS = %i[start end].freeze
        private_constant :SESSION_TIME_FIELDS
        # Keys of the schemas of the bundle (manifest): Node API, options of the commands
        API_SCHEMA = 'node'
        EMULATOR_OPTIONS = 'node_opts:components.schemas.NodeEmulatorOptions'
        API_OPTIONS = 'node_opts:components.schemas.NodeApiOptions'

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
              api = Rest::Client.new(base_url: base_url)
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
        option :asperabrowserurl, description: 'URL of Aspera Browser, web application to browse the node', default: 'https://laurent-martin.github.io/aspera-browser-react/'
        option :node_api,         description: 'Gen4: use of the Node API (dot-notation: cache, standard_ports, accept_v4)', schema: API_OPTIONS, on_set: Api.method(:api_options=)
        option :root_id,          description: 'Gen4: File id of top folder when using access key (override AK root id)'
        option :dynamic_key,      description: 'Private key PEM to use for dynamic key auth', on_set: Api.method(:use_dynamic_key=)

        # @param wizard  [Wizard] The wizard object
        # @param app_url [String] Tested URL
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          username = options.get_option(:username, mandatory: true)
          return {
            preset_ids:   [username],
            preset_value: {
              url:      app_url,
              username: username,
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
          search:      {description: 'Search for files',             arguments: [{name: :path}]},
          space:       {description: 'Show space information',       arguments: [{name: :paths, multiple: true}]},
          mkdir:       {description: 'Create a folder (Gen3)',       arguments: [{name: :paths, multiple: true}]},
          mklink:      {description: 'Create a symbolic link (Gen3)', arguments: [{name: :target}, {name: :link_path}]},
          mkfile:      {description: 'Create a file (Gen3)', arguments: [{name: :path}, {name: :contents, mandatory: false, default: nil}]},
          rename:      {description: 'Rename a file or folder (Gen3)', arguments: [{name: :folder}, {name: :source}, {name: :destination}]},
          delete:      {description: 'Delete files or folders (Gen3)', arguments: [{name: :paths, multiple: true}]},
          ls:          {description: 'List files (Gen3)',            arguments: [{name: :path}], aliases: [:browse]},
          upload:      {description: 'Upload files (Gen3)',          transfer_paths: :send},
          download:    {description: 'Download files (Gen3)',        transfer_paths: :receive},
          cat:         {description: 'Show file contents (Gen3)',    arguments: [{name: :path}]},
          transport:   {description: 'Show transport parameters'},
          spec:        {description: 'Show transfer spec base'},
          api_details: {description: 'Show API details'},
          health:      {description: 'Check node health'},
          events:      {description: 'List events', read_only: true},
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
        SINGLE_PATH_ARG = [{name: :path}].freeze
        COMMANDS_GEN4_SPEC = {
          mkdir:             {description: 'Create folder',                  arguments: SINGLE_PATH_ARG},
          mklink:            {description: 'Create symbolic link',           arguments: SINGLE_PATH_ARG},
          mkfile:            {description: 'Create file',                    arguments: [{name: :path}, {name: :contents, mandatory: false, default: nil}]},
          rename:            {description: 'Rename entry',                   arguments: [{name: :source_path}, {name: :new_name}]},
          delete:            {description: 'Delete entry',                   arguments: [{name: :path, bulk: true}]},
          upload:            {description: 'Upload files',                   transfer_paths: :send},
          download:          {description: 'Download files',                 transfer_paths: :receive},
          modify:            {description: 'Modify file',                    arguments: [{name: :path}, {name: :file, type: Hash, schema: 'node:components.schemas.files-id-put-request'}]},
          cat:               {description: 'Show file contents',             arguments: SINGLE_PATH_ARG},
          show:              {description: 'Show file info',                 arguments: SINGLE_PATH_ARG},
          thumbnail:         {description: 'Show file thumbnail',            arguments: SINGLE_PATH_ARG, read_only: true},
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

        # @param api [Rest::Client] an existing API object for the Node API
        def initialize(context:, api: nil)
          super(context: context)
          # Api or Rest::Client (Shares), when provided by the host plugin
          @api_node = api
        end

        # Node API: provided by the host plugin, or built from CLI options on first use.
        # @return [Api, Rest::Client]
        def api_node
          @api_node ||=
            if OAuth::Factory.bearer_auth?(options.get_option(:password, mandatory: true))
              # info is provided like node_info of aoc
              Api.new(
                base_url: options.get_option(:url, mandatory: true),
                headers:  Api.bearer_headers(options.get_option(:password, mandatory: true))
              )
            else
              # this is normal case
              Api.new(
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
          # not a URL query: merged into the POST body of files/browse
          query = options.get_option(:query) || {}
          # special parameter: max number of entries in result
          max_items = query.delete(Rest::List::MAX_ITEMS)
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
              response = api_node.create('files/browse', query)
              # 'file','symbolic_link'
              return Cli::Result::SingleObject.new(response['self']) if !Commands.gen3_entry_folder?(response['self']) || only_path
              items = response['items']
              total_count ||= response['total_count']
              all_items.concat(items)
              if single_call
                formatter.display_item_count(response['item_count'], total_count)
                break
              end
              folders_to_process.concat(items.select { |i| Commands.gen3_entry_folder?(i) }.map { |i| i['path'] }) if recursive
              if !max_items.nil? && (all_items.count >= max_items)
                all_items = all_items.slice(0, max_items) if all_items.count > max_items
                break
              end
              break if all_items.count >= total_count
              offset += items.count
              query['skip'] = offset
              Rest::Parameters.instance.spinner_cb.call(all_items.count)
            end
            query.delete('skip')
          end
          return Cli::Result::ObjectList.new(all_items)
        ensure
          Rest::Parameters.instance.spinner_cb.call(action: :success)
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
          if (m = Cli::Parser.percent_selector(path))
            Aspera.assert_values(m[:field], ['id'], type: Cli::BadArgument) { 'file id' }
            val = m[:value]
            return NodeFileId.new(api_node, val.nil? || val.empty? ? top_file_id : val)
          end
          api_node.resolve_api_fid(top_file_id, path)
        end

        # Search /async by name
        # @param field [String] name of the field to search
        # @param value [String] value of the field to search
        # @return [Integer] id of the sync
        # @raise [Cli::BadArgument] if no such sync, or not by name
        def async_lookup(field, value)
          Aspera.assert_values(field, ['name'], type: Cli::BadArgument) { 'search field' }
          async_ids = api_node.read('async/list')['sync_ids']
          summaries = api_node.create('async/summary', {'syncs' => async_ids})['sync_summaries']
          selected = summaries.find { |s| s['name'].eql?(value) }
          raise Cli::BadIdentifier.new('sync', value, field: field) if selected.nil?
          return selected['snid']
        end

        # Lookup for access_keys: only supports %id:self selector.
        # @param field [String] must be 'id'
        # @param value [String] must be 'self'
        # @return [String] the resolved access key id
        def lookup_access_key_self_id(field, value, **)
          Aspera.assert(field.eql?('id') && value.eql?('self'), type: Cli::BadArgument) { 'only selector: %id:self' }
          api_node.read('access_keys/self')['id']
        end

        # Search /asyncs by name
        # @param field [String] name of the field to search
        # @param value [String] value of the field to search
        # @return [Integer] id of the sync
        # @raise [Cli::BadArgument] if no such sync, or not by name
        def ssync_lookup(field, value)
          Aspera.assert_values(field, ['name'], type: Cli::BadArgument) { 'search field' }
          api_node.read('asyncs')['ids'].each do |id|
            sync_info = api_node.read("asyncs/#{id}")['configuration']
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
          transport:   ->(**) { Cli::Result::SingleObject.new(api_node.transport_params) },
          spec:        ->(**) { Cli::Result::SingleObject.new(api_node.base_spec, fields: Cli::Formatter.all_but(*Aspera::Transfer::Spec::SPECIFIC)) },
          api_details: ->(**) { Cli::Result::SingleObject.new({base_url: api_node.base_url}.merge(api_node.params)) },
          events:      ->(**) { Cli::Result::ObjectList.new(api_node.read('events', query_read_delete(schema: Schema::Registry.query_params(API_SCHEMA, 'events'))), fields: ->(f) { !f.start_with?('data') }) },
          info:        ->(**) { Cli::Result::SingleObject.new(api_node.read('info')) },
          slash:       ->(**) { Cli::Result::SingleObject.new(api_node.read('')) },
          license:     ->(**) { Cli::Result::SingleObject.new(api_node.read('license')) }
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
            command dir, description: "#{dir.capitalize}-sync (Gen3)", transfer_paths: :send, arguments: Aspera::Plugins::Xfer::SyncActions::PATH_AND_INFO_ARGS
          end
          sync_admin_commands :admin
          sync_logs_command :logs
        end
        # access_keys sub-tree
        command :access_keys, description: 'Manage access keys'
        commands_under :access_keys do
          command :do, description: 'Execute Gen4 command via access key',
            arguments: [{name: :access_key_id, type: :identifier}],
            setup: :setup_access_key_do
          command :set_bearer_key, description: 'Set bearer key on access key',
            arguments: [{name: :access_key_id, type: :identifier}, {name: :bearer_key_pem}]
          crud_commands entity: 'access_keys',
            api:            :api_node,

            body_component: API_SCHEMA,
            lookup:         :lookup_access_key_self_id
        end

        commands_under %i[access_keys do] do
          COMMANDS_GEN4_SPEC.each do |cmd, spec|
            command cmd, **spec
          end
          command :v3, description: 'Legacy v3 commands on files', mount: {plugin: self, instance: :v3_node_plugin}
          command :permission, description: 'Manage permissions',
            arguments: [{name: :path, description: 'Path, or %id:<file id>, or %id: for root'}],
            setup: :setup_access_key_do_permission
          command :sync, description: 'Synchronize folders'
          commands_under :sync do
            Sync::Operations::DIRECTIONS.each do |dir|
              command dir, description: "#{dir.capitalize}-sync", transfer_paths: :send, arguments: Aspera::Plugins::Xfer::SyncActions::PATH_AND_INFO_ARGS
            end
            sync_admin_commands :admin
            sync_logs_command :logs
          end
        end
        commands_under %i[access_keys do permission] do
          command :list,   description: 'List permissions on a file'
          command :show,   description: 'Show a permission',
            arguments: [{name: :permission_id, type: :identifier}],
            action: ->(apifid:, permission_id:, **) { Cli::Result::SingleObject.new(apifid.node_api.read("permissions/#{permission_id}")) }
          command :create, description: 'Create a permission',
            arguments: [{name: :permission, type: Hash, schema: 'node:components.schemas.permissions-post-request'}]
          command(
            :modify, description: 'Modify a permission',
            arguments: [{name: :permission_id, type: :identifier}, {name: :permission, type: Hash, schema: 'node:components.schemas.permissions-id-put-request'}],
            action: lambda do |permission:, apifid:, permission_id:, **|
              apifid.node_api.update("permissions/#{permission_id}", permission)
              Cli::Result::Status.new('Updated')
            end
          )
          command :delete, description: 'Delete permissions',
            arguments: [{name: :permission_id, type: :identifier, bulk: true}]
        end
        # async (legacy /async)
        commands_under :async, description: 'Manage legacy synchronizations (/async)' do
          command :list,      description: 'List async sync IDs', action: ->(**) { Cli::Result::ValueList.new(api_node.read('async/list')['sync_ids']) }
          command :show,      description: 'Show async summary',
            arguments: [{name: :async_id, type: :identifier, lookup: :async_lookup}]
          command(
            :delete, description: 'Delete async',
            arguments: [{name: :async_id, type: :identifier, lookup: :async_lookup}],
            action: lambda do |async_id:, **|
              async_ids = async_id.eql?(Cli::SpecialValues::ALL) ? api_node.read('async/list')['sync_ids'] : [async_id]
              Cli::Result::SingleObject.new(api_node.create('async/delete', {'syncs' => async_ids}))
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
        commands_under :ssync, description: 'Manage synchronizations (/asyncs)' do
          crud_commands entity: 'asyncs',
            name: 'sync session',
            id_name: :ssync_id,
            api: :api_node,
            operations: %i[create list show delete],
            items_key: 'ids',
            lookup: :ssync_lookup
          command(
            :start, description: 'Start a sync', arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: lambda do |ssync_id:, **|
              api_node.call(operation: 'POST', subpath: "asyncs/#{ssync_id}/start", content_type: Mime::TEXT, body: '', ret: :resp).body
              Cli::Result::Status.new('Done')
            end
          )
          command(
            :stop, description: 'Stop a sync', arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: lambda do |ssync_id:, **|
              api_node.call(operation: 'POST', subpath: "asyncs/#{ssync_id}/stop", content_type: Mime::TEXT, body: '', ret: :resp).body
              Cli::Result::Status.new('Done')
            end
          )
          command :bandwidth, read_only: true, description: 'Show sync bandwidth',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Cli::Result::SingleObject.new(api_node.read("asyncs/#{ssync_id}/bandwidth", query_read_delete(default: {}))) }
          command :counters, read_only: true, description: 'Show sync counters',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Cli::Result::SingleObject.new(api_node.read("asyncs/#{ssync_id}/counters", query_read_delete(default: {}))) }
          command :files, read_only: true, description: 'List sync files',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Cli::Result::SingleObject.new(api_node.read("asyncs/#{ssync_id}/files", query_read_delete(default: {}))) }
          command :state, read_only: true, description: 'Show sync state',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Cli::Result::SingleObject.new(api_node.read("asyncs/#{ssync_id}/state")) }
          command :summary, read_only: true, description: 'Show sync summary',
            arguments: [{name: :ssync_id, type: :identifier, lookup: :ssync_lookup}],
            action: ->(ssync_id:, **) { Cli::Result::SingleObject.new(api_node.read("asyncs/#{ssync_id}/summary")) }
        end
        # stream
        command :stream, description: 'Manage stream operations'
        commands_under :stream do
          command :list,   description: 'List streams', action: ->(**) { Cli::Result::ObjectList.new(api_node.read('ops/transfers', query_read_delete), fields: %w[id status]) }
          command :create, description: 'Create a stream',
            arguments: [{name: :stream, type: Hash, schema: 'node:components.schemas.transferPostRequest'}],
            action: ->(stream:, **) { Cli::Result::SingleObject.new(api_node.create('streams', stream)) }
          command :show,   description: 'Show a stream',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: ->(transfer_id:, **) { Cli::Result::SingleObject.new(api_node.read("ops/transfers/#{transfer_id}")) }
          command :modify, description: 'Modify a stream',
            arguments: [{name: :transfer_id, type: :identifier}, {name: :stream, type: Hash, schema: 'node:components.schemas.transferPutRequest'}],
            action: ->(stream:, transfer_id:, **) { Cli::Result::SingleObject.new(api_node.update("streams/#{transfer_id}", stream)) }
          command :cancel, description: 'Cancel a stream',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: ->(transfer_id:, **) { Cli::Result::SingleObject.new(api_node.cancel("streams/#{transfer_id}")) }
        end
        # transfer
        command :transfer, description: 'Manage transfer operations'
        commands_under :transfer do
          command :list, description: 'List transfers'
          command(
            :cancel, description: 'Cancel a transfer',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: lambda do |transfer_id:, **|
              api_node.cancel("ops/transfers/#{transfer_id}")
              Cli::Result::Status.new('Cancelled')
            end
          )
          command :show, description: 'Show a transfer',
            arguments: [{name: :transfer_id, type: :identifier}],
            action: ->(transfer_id:, **) { Cli::Result::SingleObject.new(api_node.read("ops/transfers/#{transfer_id}")) }
          command(
            :modify, description: 'Modify a transfer',
            arguments: [{name: :transfer_id, type: :identifier}, {name: :transfer, type: Hash, schema: 'node:components.schemas.transferPutRequest'}],
            action: lambda do |transfer:, transfer_id:, **|
              api_node.update("ops/transfers/#{transfer_id}", transfer)
              Cli::Result::Status.new('Modified')
            end
          )
          command :bandwidth_average, description: 'Show average bandwidth per period'
          command :sessions,          description: 'List transfer sessions'
        end
        # service
        command :service, description: 'Manage services'
        commands_under :service do
          command :list, description: 'List services', action: ->(**) { Cli::Result::ObjectList.new(api_node.read('rund/services')['services']) }
          command(
            :create, description: 'Create a service',
            arguments: [{name: :service, type: Hash}],
            action: lambda do |service:, **|
              resp = api_node.create('rund/services', service)
              Cli::Result::Status.new("#{resp['id']} created")
            end
          )
          command(
            :delete, description: 'Delete a service',
            arguments: [{name: :service_id, type: :identifier}],
            action: lambda do |service_id:, **|
              api_node.delete("rund/services/#{service_id}")
              Cli::Result::Status.new("#{service_id} deleted")
            end
          )
        end
        # watch_folder
        command :watch_folder, description: 'Manage watch folders', setup: :setup_watch_folder
        commands_under :watch_folder do
          command :create, description: 'Create a watch folder',
            arguments: [{name: :watch_folder, type: Hash}],
            action: ->(watch_folder:, **) { Cli::Result::Status.new("#{api_node.create('v3/watchfolders', watch_folder)['id']} created") }
          command :list,   description: 'List watch folders',
            action: ->(**) { Cli::Result::ValueList.new(api_node.read('v3/watchfolders', query_read_delete)['ids']) }
          command :show,   description: 'Show a watch folder',
            arguments: [{name: :watch_folder_id, type: :identifier}],
            action: ->(watch_folder_id:, **) { Cli::Result::SingleObject.new(api_node.read("v3/watchfolders/#{watch_folder_id}")) }
          command(
            :modify, description: 'Modify a watch folder',
            arguments: [{name: :watch_folder_id, type: :identifier}, {name: :watch_folder, type: Hash}],
            action: lambda do |watch_folder:, watch_folder_id:, **|
              api_node.update("v3/watchfolders/#{watch_folder_id}", watch_folder)
              Cli::Result::Status.new("#{watch_folder_id} updated")
            end
          )
          command(
            :delete, description: 'Delete a watch folder',
            arguments: [{name: :watch_folder_id, type: :identifier}],
            action: lambda do |watch_folder_id:, **|
              api_node.delete("v3/watchfolders/#{watch_folder_id}")
              Cli::Result::Status.new("#{watch_folder_id} deleted")
            end
          )
          command :state, read_only: true, description: 'Show watch folder state',
            arguments: [{name: :watch_folder_id, type: :identifier}],
            action: ->(watch_folder_id:, **) { Cli::Result::SingleObject.new(api_node.read("v3/watchfolders/#{watch_folder_id}/state")) }
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
        command :asperabrowser, description: 'Open Aspera Browser on this node (the password is optional: it is then entered in the application)'
        command :basic_token,   description: 'Generate basic auth token', action: ->(**) { Cli::Result::Text.new(Rest.basic_authorization(options.get_option(:username, mandatory: true), options.get_option(:password, mandatory: true))) }
        command(
          :bearer_token, description: 'Generate bearer token',
          arguments: [{name: :private_key_pem}, {name: :token, type: Hash, schema: 'node_opts:components.schemas.NodeBearerTokenOptions'}],
          action: lambda do |private_key_pem:, token:, **|
            private_key = OpenSSL::PKey::RSA.new(private_key_pem)
            access_key  = options.get_option(:username, mandatory: true)
            Cli::Result::Text.new(Api.bearer_token(payload: token, access_key: access_key, private_key: private_key))
          end
        )
        command :emulator,      description: 'Start node emulator', security: :low,
          aliases: [:simulator],
          arguments: [{name: :parameters, type: Hash, mandatory: false, default: {}, schema: EMULATOR_OPTIONS}]
        command :telemetry,     description: 'Report telemetry to external system',
          arguments: [{name: :parameters, type: Hash, mandatory: false, default: {}, schema: 'node_opts:components.schemas.NodeTelemetryOptions'}]

        # --- Handler methods (Gen3) ---

        def action_delete(paths:, **)
          # TODO: add query for recursive
          paths_to_delete = Array(paths)
          resp = api_node.create('files/delete', {paths: paths_to_delete.map { |i| {'path' => i.start_with?('/') ? i : "/#{i}"} }})
          cli_result_from_paths_response(resp, 'file deleted')
        end

        def action_search(path:, **)
          parameters = {'path' => path}
          # not a URL query: merged into the POST body of files/search
          other_options = options.get_option(:query)
          parameters.merge!(other_options) unless other_options.nil?
          resp = api_node.create('files/search', parameters)
          return Cli::Result::Empty.new if resp['items'].empty?
          fields = resp['items'].first.keys.reject { |i| SEARCH_REMOVE_FIELDS.include?(i) }
          formatter.display_item_count(resp['item_count'], resp['total_count'])
          formatter.display_status("params: #{resp['parameters'].keys.map { |k| "#{k}:#{resp['parameters'][k]}" }.join(',')}")
          Cli::Result::ObjectList.new(resp['items'], fields: fields)
        end

        def action_space(paths:, **)
          paths = Array(paths)
          resp = api_node.create('space', {'paths' => paths.map { |i| {path: i} }})
          Cli::Result::ObjectList.new(resp['paths'])
        end

        def action_mkdir(paths:, **)
          paths = Array(paths)
          resp = api_node.create('files/create', {'paths' => paths.map { |i| {type: :directory, path: i} }})
          cli_result_from_paths_response(resp, 'folder created')
        end

        def action_mklink(target:, link_path:, **)
          resp = api_node.create('files/create', {'paths' => [{type: :symbolic_link, path: link_path, target: {path: target}}]})
          cli_result_from_paths_response(resp, 'link created')
        end

        def action_mkfile(path:, contents:, **)
          contents64 = contents.nil? ? '' : Base64.strict_encode64(contents)
          resp = api_node.create('files/create', {'paths' => [{type: :file, path: path, contents: contents64}]})
          cli_result_from_paths_response(resp, 'file created')
        end

        def action_rename(folder:, source:, destination:, **)
          # TODO: multiple ?
          resp = api_node.create('files/rename', {'paths' => [{'path' => folder, 'source' => source, 'destination' => destination}]})
          cli_result_from_paths_response(resp, 'entry moved')
        end

        # Obtains a transfer spec via the Node API for the given direction/folders.
        def sync_gen3_block
          lambda do |direction, local_path, remote_path|
            request_transfer_spec = sync_spec_request(direction, local_path, remote_path)
            api_node.add_tspec_info(request_transfer_spec) if api_node.respond_to?(:add_tspec_info)
            transfer_spec = api_node.create(
              'files/sync_setup',
              {transfer_requests: [{transfer_request: request_transfer_spec}]}
            )['transfer_specs'].first&.fetch('transfer_spec')
            transfer_spec.delete_if { |_k, v| v.nil? }
            Log.dump(:ts, transfer_spec)
            transfer_spec
          end
        end

        Sync::Operations::DIRECTIONS.each do |dir|
          define_action_method([:sync, dir]) { |path:, sync_info: {}, **| run_sync_transfer(dir, path: path, sync_info: sync_info, &sync_gen3_block) }
        end

        def action_upload(**)
          # empty transfer spec for authorization request
          request_transfer_spec = {}
          request_transfer_spec[:paths] = [{destination: transfer.destination_folder(Aspera::Transfer::Spec::DIRECTION_SEND)}]
          # add fixed parameters if any (for COS)
          api_node.add_tspec_info(request_transfer_spec) if api_node.respond_to?(:add_tspec_info)
          Api.add_public_key(request_transfer_spec)
          setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
          transfer_spec = api_node.create('files/upload_setup', setup_payload)['transfer_specs'].first&.fetch('transfer_spec')
          Api.add_private_key(transfer_spec)
          transfer_spec.delete('paths')
          Xfer::TransferAgent.result_transfer(transfer.start(transfer_spec))
        end

        def action_download(**)
          # empty transfer spec for authorization request
          request_transfer_spec = {}
          request_transfer_spec[:paths] = transfer.ts_source_paths
          # add fixed parameters if any (for COS)
          api_node.add_tspec_info(request_transfer_spec) if api_node.respond_to?(:add_tspec_info)
          Api.add_public_key(request_transfer_spec)
          setup_payload = {transfer_requests: [{transfer_request: request_transfer_spec}]}
          transfer_spec = api_node.create('files/download_setup', setup_payload)['transfer_specs'].first&.fetch('transfer_spec')
          Api.add_private_key(transfer_spec)
          Xfer::TransferAgent.result_transfer(transfer.start(transfer_spec))
        end

        def action_cat(path:, **)
          http = api_node.read("files/#{URI.encode_www_form_component(path)}/contents", ret: :resp)
          Cli::Result::Text.new(http.body)
        end

        def action_health(**)
          nagios = Nagios.new
          begin
            info = api_node.read('info')
            nagios.add_ok('node api', 'accessible')
            nagios.check_time_offset(info['current_time'], 'node api')
            nagios.check_product_version('node api', 'entsrv', info['version'])
          rescue StandardError => e
            nagios.add_critical('node api', e.to_s)
          end
          begin
            api_node.call(
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
          Cli::Result::ObjectList.new(nagios.status_list)
        end

        # watch_folder setup: inject required API header (avoids "Unable to convert 2016_09_14 configuration")
        def setup_watch_folder(**)
          api_node.headers['X-aspera-WF-version'] = '2017_10_23'
          {}
        end

        # access_keys > do - setup: resolve access key and root file id
        # @return [Hash] context hash containing :do_root_file_id
        def setup_access_key_do(access_key_id:, **)
          @do_root_file_id = options.get_option(:root_id)
          if @do_root_file_id.nil?
            ak_info = api_node.read("access_keys/#{access_key_id}")
            ak_secret = context.secret_finder.lookup(url: api_node.base_url, username: ak_info['id'])
            if !access_key_id.eql?('self')
              Aspera.assert(ak_secret, type: Cli::MissingArgument) { "Please provide secret for #{ak_info['id']} using option: secret or by setting a preset for #{ak_info['id']}@#{api_node.base_url}." }
              api_node.auth_params[:username] = ak_info['id']
              api_node.auth_params[:password] = ak_secret
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
          file_info = apifid.node_api.read("files/#{apifid.file_id}", headers: Api.add_cache_control)
          return Cli::Result::ObjectList.new([file_info], fields: GEN4_LS_FIELDS) unless file_info['type'].eql?('folder')
          Cli::Result::ObjectList.new(apifid.node_api.list_files(apifid.file_id, query: query_read_delete), fields: GEN4_LS_FIELDS)
        end

        # access_keys > do > find
        def action_access_keys_do_find(path:, filter: nil, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Cli::Result::ObjectList.new(api_node.find_files(apifid.file_id, Cli::Plugins::Base.file_matcher(filter)), fields: ['path'])
        end

        # access_keys > do > cat
        def action_access_keys_do_cat(path:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Cli::Result::Text.new(apifid.node_api.read("files/#{apifid.file_id}/content", ret: :resp).body)
        end

        # access_keys > do > show
        def action_access_keys_do_show(path:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Cli::Result::SingleObject.new(apifid.node_api.read("files/#{apifid.file_id}", headers: Api.add_cache_control))
        end

        # access_keys > do > modify
        def action_access_keys_do_modify(path:, file:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          apifid.node_api.update("files/#{apifid.file_id}", file)
          Cli::Result::Status.new('Done')
        end

        # access_keys > do > thumbnail
        def action_access_keys_do_thumbnail(path:, do_root_file_id:, **)
          apifid = apifid_from_path(do_root_file_id, path)
          Cli::Result::Image.new(apifid.node_api.read("files/#{apifid.file_id}/preview", headers: Api.add_cache_control({'Accept' => 'image/png'}), ret: :resp).body)
        end

        # access_keys > do > rename
        def action_access_keys_do_rename(source_path:, new_name:, do_root_file_id:, **)
          apifid = api_node.resolve_api_fid(do_root_file_id, source_path)
          apifid.node_api.update("files/#{apifid.file_id}", {name: new_name})
          Cli::Result::Status.new("renamed to #{new_name}")
        end

        # access_keys > do > delete
        def action_access_keys_do_delete(path:, do_root_file_id:, **)
          bulk_result(path, command: :delete, id_result: 'path') do |l_path|
            apifid = if (m = Cli::Parser.percent_selector(l_path))
              Aspera.assert_values(m[:field], ['id'], type: Cli::BadIdentifier)
              NodeFileId.new(api_node, m[:value])
            else
              api_node.resolve_api_fid(do_root_file_id, l_path)
            end
            apifid.node_api.delete("files/#{apifid.file_id}")
            {'path' => l_path}
          end
        end

        # Shared Gen4 sync block: obtains a transfer spec via the Gen4 API for the given direction/remote_path.
        def sync_gen4_block(do_root_file_id)
          lambda do |direction, _local_path, remote_path|
            ts_direction = direction.eql?(:pull) ? Aspera::Transfer::Spec::DIRECTION_RECEIVE : Aspera::Transfer::Spec::DIRECTION_SEND
            apifid = api_node.resolve_api_fid(do_root_file_id, remote_path)
            apifid.node_api.transfer_spec_gen4(apifid.file_id, ts_direction)
          end
        end

        Sync::Operations::DIRECTIONS.each do |dir|
          define_action_method([:access_keys, :do, :sync, dir]) do |path:, sync_info: {}, do_root_file_id:, **|
            run_sync_transfer(dir, path: path, sync_info: sync_info, &sync_gen4_block(do_root_file_id))
          end
        end

        # access_keys > do > upload
        def action_access_keys_do_upload(do_root_file_id:, **)
          apifid = api_node.resolve_api_fid(do_root_file_id, transfer.destination_folder(Aspera::Transfer::Spec::DIRECTION_SEND), true)
          Xfer::TransferAgent.result_transfer(transfer.start(apifid.node_api.transfer_spec_gen4(apifid.file_id, Aspera::Transfer::Spec::DIRECTION_SEND)))
        end

        # access_keys > do > download
        def action_access_keys_do_download(do_root_file_id:, **)
          apifid, source_paths = api_node.resolve_api_fid_paths(do_root_file_id, transfer.ts_source_paths)
          Xfer::TransferAgent.result_transfer(transfer.start(apifid.node_api.transfer_spec_gen4(apifid.file_id, Aspera::Transfer::Spec::DIRECTION_RECEIVE, {'paths'=>source_paths})))
        end

        # access_keys > do > v3 - mount target: Node plugin on the node hosting the root file
        # @return [Node]
        def v3_node_plugin(do_root_file_id:, **)
          Commands.new(context: context, api: api_node.resolve_api_fid(do_root_file_id, '').node_api)
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
            result[:username] = apifid.node_api.params[:headers][Api::HEADER_X_ASPERA_ACCESS_KEY]
            result[:password] = apifid.node_api.oauth.authorization
          else Aspera.error_unexpected_value(apifid.node_api.auth_params[:type]) { 'Node API Auth type' }
          end
          [apifid, result]
        end

        def action_access_keys_do_node_info(path:, do_root_file_id:, **)
          _apifid, result = gen4_apifid_info(do_root_file_id, path)
          Cli::Result::SingleObject.new(result)
        end

        def action_access_keys_do_bearer_token_node(path:, do_root_file_id:, **)
          apifid, result = gen4_apifid_info(do_root_file_id, path)
          Log.dump(:result, result)
          Aspera.assert(apifid.node_api.auth_params[:type].eql?(:oauth2), type: Cli::BadArgument) { "Cannot get bearer token if authenticating with secret (#{apifid.node_api.auth_params[:type]})" }
          Aspera.assert(OAuth::Factory.bearer_auth?(result[:password]), 'Not using bearer token auth')
          Cli::Result::Text.new(result[:password])
        end

        # access_keys > do > mkdir / mklink / mkfile — shared helper: resolve parent folder,
        # build payload from query option, optionally check for name collision.
        # @return [Array(NodeFileId, Hash)] parent apifid and payload with :name set
        # @param path [String] full path (folder/name)
        def gen4_mk_resolve(top_file_id, path)
          containing_folder_path, new_item = Api.split_folder(path)
          apifid = api_node.resolve_api_fid(top_file_id, containing_folder_path, true)
          # not a URL query: special keys `check` and `target`, rest merged into the POST body
          query = options.get_option(:query)
          check_exists = true
          payload = {name: new_item}
          if query
            check_exists = !query.delete('check').eql?(false)
            target = query.delete('target')
            if target
              target_apifid = api_node.resolve_api_fid(top_file_id, target, true)
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
          Cli::Result::SingleObject.new(apifid.node_api.create("files/#{apifid.file_id}/files", payload))
        end

        def action_access_keys_do_mklink(path:, do_root_file_id:, **)
          apifid, payload = gen4_mk_resolve(do_root_file_id, path)
          payload[:type] = :link
          Aspera.assert(payload[:target_id], 'Missing target_id', type: Cli::BadArgument)
          Aspera.assert(payload[:target_node_id], 'Missing target_node_id', type: Cli::BadArgument)
          Cli::Result::SingleObject.new(apifid.node_api.create("files/#{apifid.file_id}/files", payload))
        end

        def action_access_keys_do_mkfile(path:, contents:, do_root_file_id:, **)
          apifid, payload = gen4_mk_resolve(do_root_file_id, path)
          payload[:type] = :file
          payload[:contents] = contents.nil? ? '' : Base64.strict_encode64(contents)
          Cli::Result::SingleObject.new(apifid.node_api.create("files/#{apifid.file_id}/files", payload))
        end

        # access_keys > do > permission > list/show/create/modify/delete
        def action_access_keys_do_permission_list(apifid:, **)
          list_query = query_read_delete(default: Rest.php_style({'include' => %w[access_level permission_count]}))
          # Specify file to get permissions for unless not specified (then, get all permissions)
          list_query['file_id'] = apifid.file_id unless apifid.file_id.to_s.empty?
          list_query['inherited'] = false if list_query.key?('file_id') && !list_query.key?('inherited')
          Cli::Result::ObjectList.new(apifid.node_api.read_with_pages('permissions', list_query))
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
          create_param['access_levels'] = Api::ACCESS_LEVELS unless create_param.key?('access_levels')
          the_app = apifid.node_api.app_info
          the_app&.api&.permissions_set_create_params(perm_data: create_param, app_info: the_app)
          created_data = apifid.node_api.create('permissions', create_param)
          the_app&.api&.permissions_send_event(event_data: created_data, app_info: the_app)
          Cli::Result::SingleObject.new(created_data)
        end

        # access_keys > set_bearer_key
        def action_access_keys_set_bearer_key(access_key_id:, bearer_key_pem:, **)
          access_key_id = api_node.read('access_keys/self')['id'] if access_key_id.eql?('self')
          key = OpenSSL::PKey.read(bearer_key_pem)
          key = key.public_key if key.private?
          api_node.update("access_keys/#{access_key_id}", {token_verification_key: key.to_pem})
          Cli::Result::Status.new('public key updated')
        end

        # async sub-commands: individual handlers
        def action_async_show(async_id:, **)
          async_ids = api_node.read('async/list')['sync_ids']
          if async_id.eql?(Cli::SpecialValues::ALL)
            resp = api_node.create('async/summary', {'syncs' => async_ids})['sync_summaries']
            return Cli::Result::Empty.new if resp.empty?
            return Cli::Result::ObjectList.new(resp, fields: %w[snid name local_dir remote_dir])
          end
          Integer(async_id)
          resp = api_node.create('async/summary', {'syncs' => [async_id]})['sync_summaries']
          return Cli::Result::Empty.new if resp.empty?
          Cli::Result::SingleObject.new(resp.first)
        end

        def action_async_bandwidth(async_id:, **)
          Integer(async_id)
          post_data = {'syncs' => [async_id], 'seconds' => 100}
          resp = api_node.create('async/bandwidth', post_data)
          data = resp['bandwidth_data']
          return Cli::Result::Empty.new if data.empty?
          Cli::Result::ObjectList.new(data.first[async_id]['data'])
        end

        def action_async_files(async_id:, **)
          Integer(async_id)
          post_data = {'syncs' => [async_id]}
          # not a URL query: merged into the POST body of async/files
          filter = options.get_option(:query)
          post_data.merge!(filter) unless filter.nil?
          resp = api_node.create('async/files', post_data)
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
          return Cli::Result::Empty.new if data.empty?
          skip_ids_persistency&.save
          Cli::Result::ObjectList.new(data)
        end

        def action_async_counters(async_id:, **)
          Integer(async_id)
          resp = api_node.create('async/counters', {'syncs' => [async_id]})['sync_counters'].first&.[](async_id)&.last
          return Cli::Result::Empty.new if resp.nil?
          Cli::Result::SingleObject.new(resp)
        end

        # transfer sub-commands
        def action_transfer_list(**)
          transfer_filter = query_read_delete(default: {}, schema: Schema::Registry.query_params(API_SCHEMA, 'ops/transfers'))
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
              return Cli::Result::Status.new('Persistency reset')
            end
          else
            Aspera.assert(!transfer_filter.key?('reset'), 'reset only with once_only', type: Cli::BadArgument)
          end
          transfers_data = api_node.read_with_paging('ops/transfers', transfer_filter, iteration: iteration_persistency&.data)
          iteration_persistency&.save
          Cli::Result::ObjectList.new(transfers_data, fields: %w[id status start_spec.direction start_spec.remote_user start_spec.remote_host start_spec.destination_path])
        end

        def action_transfer_sessions(**)
          transfers_data = api_node.read('ops/transfers', query_read_delete(schema: Schema::Registry.query_params(API_SCHEMA, 'ops/transfers')))
          sessions = transfers_data.flat_map { |t| t['sessions'] }
          sessions.each do |session|
            SESSION_TIME_FIELDS.each do |what|
              session["#{what}_time"] = session["#{what}_time_usec"] ? Time.at(session["#{what}_time_usec"] / 1_000_000.0).utc.iso8601(0) : nil
            end
          end
          Cli::Result::ObjectList.new(sessions, fields: %w[id status start_time end_time target_rate_kbps])
        end

        def action_transfer_bandwidth_average(**)
          transfers_data = api_node.read('ops/transfers', query_read_delete(schema: Schema::Registry.query_params(API_SCHEMA, 'ops/transfers')))
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
            period_bandwidth = Aspera::Transfer::Spec::DIRECTION_ENUM_VALUES.map(&:to_sym).to_h do |dir|
              [dir, dir_info.to_h { |k2| [k2, 0] }]
            end
            transfers_data.each do |t|
              next if t['avg_rate_kbps'].zero?
              next if t['start_time_usec'] >= end_date || t['end_time_usec'] <= start_date
              info = period_bandwidth[t['start_spec']['direction'].to_sym]
              info[:avg_kbps] += t['avg_rate_kbps']
              info[:sessions] += 1
            end
            next if Aspera::Transfer::Spec::DIRECTION_ENUM_VALUES.map(&:to_sym).all? { |dir| period_bandwidth[dir][:sessions].zero? }
            result.push({start: Time.at(start_date / 1_000_000), end: Time.at(end_date / 1_000_000)}.merge(period_bandwidth))
          end
          Cli::Result::ObjectList.new(result)
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
          resp = api_node.create('services/rest/transfers/v1/sessions', criteria)
          Cli::Result::ObjectList.new(resp['session_info_result']['session_info'], fields: %w[session_uuid status transport direction bytes_transferred])
        end

        # central > file > list
        def action_central_file_list(criteria:, **)
          criteria ||= {}
          validation = central_validation
          criteria.deep_merge!({'validation' => validation}) unless validation.nil?
          resp = api_node.create('services/rest/transfers/v1/files', criteria)
          resp = JSON.parse(resp) if resp.is_a?(String)
          Log.dump(:resp, resp)
          Cli::Result::ObjectList.new(resp['file_transfer_info_result']['file_transfer_info'], fields: %w[session_uuid file_id status path])
        end

        # central > file > modify
        def action_central_file_modify(file:, **)
          file ||= {}
          validation = central_validation
          file.deep_merge!(validation) unless validation.nil?
          api_node.update('services/rest/transfers/v1/files', file)
          Cli::Result::Status.new('updated')
        end

        def action_asperabrowser(**)
          browse_params = {
            'nodeUser' => options.get_option(:username, mandatory: true),
            'nodePW'   => options.get_option(:password),
            'nodeURL'  => options.get_option(:url, mandatory: true)
          }.reject { |_key, value| value.to_s.empty? }
          # Not encrypted (decoded by the web application), in the fragment: it is not sent to the web server
          encoded_params = SealedHash.seal(browse_params, encrypt: false, reverse: true)
          Environment.instance.open_uri("#{options.get_option(:asperabrowserurl)}##{URI.encode_www_form(goto: encoded_params)}")
          return Cli::Result::Status.new('done')
        end

        def action_emulator(parameters: {}, **)
          require_relative '../../secret/strength'
          require_relative '../../web_server_simple'
          require_relative 'emulator'
          # missing parameters take the default of the schema
          defaults = Schema::Registry.instance.reader(EMULATOR_OPTIONS).current['properties'].each_with_object({}) do |(name, property), result|
            result[name.to_sym] = property['default'] if property.key?('default')
          end
          parameters = defaults.merge(parameters.symbolize_keys)
          config = WebServerSimple.servlet_parameters(parameters)
          docroot = config.delete(:docroot)
          retention_sec = config.delete(:retention_sec)
          password_min_bits = config.delete(:password_min_bits)
          Aspera.assert(config[:username].nil? == config[:password].nil?, type: Cli::BadArgument) { 'Parameters username and password must be set together' }
          Secret::Strength.assert_strong(config[:password], name: 'password', min_bits: password_min_bits, type: Cli::BadArgument) unless config[:password].nil?
          # Files of the docroot can be sent to, or received from, any host by anyone who can reach the server
          WebServerSimple.serve(parameters, NodeEmulatorServlet, protected: !config[:username].nil?, what: 'username and password', type: Cli::BadArgument) do
            Log.log.warn('No username and password: emulator accepts requests without authentication') if config[:username].nil? # HashiCorpIgnore
            [config, Emulator.new(docroot: docroot, retention_sec: retention_sec)]
          end
          return Cli::Result::Status.new('Emulator terminated')
        end

        def action_telemetry(parameters: {}, **)
          # `url` and `key` are required by the schema
          parameters = parameters.symbolize_keys
          require 'socket'
          parameters[:interval] = 10 unless parameters.key?(:interval)
          parameters[:hostname] = Socket.gethostname unless parameters.key?(:hostname)
          interval = parameters[:interval].to_f
          Aspera.assert(interval >= 0, type: Cli::BadArgument) { 'Interval must be a positive number in seconds, or 0 for single shot' }
          otel_api = Rest::Client.new(
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
            transfers_data = api_node.read_with_paging('ops/transfers', {active_only: true})
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
          return Cli::Result::ObjectList.new(obj_list, fields: %w[path result])
        end
      end
      # Hints of errors of the Node API on configuration of the server
      Cli::Hints.add(
        exception:   Rest::CallError,
        match:       /Server is not configured for this request/,
        remediation: [
          'Transfer user shall have those parameters in aspera.conf set to: token',
          'authorization_transfer_in_value authorization_transfer_out_value'
        ]
      )
      Cli::Hints.add(
        exception:   Rest::CallError,
        match:       /Please configure ACLs for this URI/,
        remediation: [
          'server must have: asnodeadmin -mu <node user> --acl-add=internal --internal'
        ]
      )
    end
  end
end
