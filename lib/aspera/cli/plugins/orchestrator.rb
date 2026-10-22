# frozen_string_literal: true

require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/special_values'
require 'aspera/nagios'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/transfer/spec'
require 'aspera/schema/registry'
require 'xmlsimple'

module Aspera
  module Cli
    module Plugins
      # Aspera Orchestrator
      class Orchestrator < BasicAuth
        STANDARD_PATH = '/aspera/orchestrator'
        TEST_ENDPOINT = 'api/remote_node_ping'
        # Raw Markdown of the workflow authoring documents
        DOC_BASE_URL = 'https://raw.githubusercontent.com/laurent-martin/aspera-orchestrator-plugins-doc/main/docs'
        # Documents of command `workflows development`: name => file
        DOC_FILES = {
          authoring: 'workflow-authoring-guide.md',
          templates: 'action-template-reference.md',
          manual:    'Orchestrator_Plugin_Manual.md'
        }.freeze
        # Value of argument `section` of command `workflows development` for the table of contents
        DOC_TOC = 'toc'
        # Default maximum level of headings in the table of contents: guide sections, one entry per plugin
        DOC_TOC_LEVELS = {
          authoring: 3,
          templates: 2,
          manual:    3
        }.freeze
        # Sections of a plugin specification, listed by command `plugins spec`
        SPEC_SECTIONS = %i[attributes inputs outputs].freeze
        # Fields of the list of plugins of command `plugins spec`
        SPEC_LIST_FIELDS = %w[name category version display_name].freeze
        # Text value that is a YAML document (Ruby objects serialized by Orchestrator)
        YAML_DUMP = /\A---\s/
        # Types of monitors of `list_monitors` (`monitor_type`) and of `monitor_snapshot` (path)
        MONITOR_TYPES = %i[workflow workorder folder node script].freeze
        MONITOR_SNAPSHOT_TYPES = %i[workflows workorders folders nodes scripts].freeze
        # Id segment of the path, for endpoints routed only as `api/<endpoint>/<id>` that do not use it
        ANY_ID = '0'
        private_constant :STANDARD_PATH, :TEST_ENDPOINT, :DOC_BASE_URL, :DOC_FILES, :DOC_TOC, :DOC_TOC_LEVELS, :SPEC_SECTIONS, :SPEC_LIST_FIELDS, :YAML_DUMP,
          :MONITOR_TYPES, :MONITOR_SNAPSHOT_TYPES, :ANY_ID

        class << self
          # @return [Hash,NilClass]
          def detect(address_or_url)
            address_or_url = "https://#{address_or_url}" unless address_or_url.match?(%r{^[a-z]{1,6}://})
            urls = [address_or_url]
            urls.push("#{address_or_url}#{STANDARD_PATH}") unless address_or_url.end_with?(STANDARD_PATH)
            error = nil
            urls.each do |base_url|
              next unless base_url.match?(%r{^https?://})
              api = Rest::Client.new(base_url: base_url)
              data, http = api.read(TEST_ENDPOINT, query: {format: :json}, ret: :both)
              next unless data['remote_orchestrator_info']
              url = http.uri.to_s
              return {
                version: data['remote_orchestrator_info']['orchestrator-version'],
                url:     url[0..url.index(TEST_ENDPOINT) - 2]
              }
            rescue StandardError => e
              error = e
              Log.log.debug { "detect error: #{e}" }
            end
            raise error if error
            return
          end
        end

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
            test_args:    'workflows list'
          }
        end

        option :apikey,      description: 'API key (exclusive with username/password)'
        option :auth_style,  description: 'Authentication style', allowed: %i[basic query token], default: :token
        option :ret_style,   description: 'Method to specify the expected response format ("Accept")', allowed: %i[header query path], default: :query
        option :result,      description: "Specify result value as: 'work_step:parameter'", deprecation: {last: '4.27.2', message: 'use keys `step` and `variable` of argument `execution` of `workflows start`'}
        option :synchronous, description: 'Wait for completion', allowed: Type::BOOLEAN, deprecation: {last: '4.27.2', message: 'use key `synchronous` of argument `execution` of `workflows start`'}
        option :plugin_specs, description: 'URL or path of the plugin specifications (YAML) used by `plugins spec`', default: "#{DOC_BASE_URL}/plugins.yml"

        # Call orchestrator API (handles ret_style negotiation and XML parsing)
        # @param endpoint     [String]      the endpoint to call
        # @param body         [Hash, Array] the body to pass; also implies POST
        # @param content_type [String]      the body type (Mime::JSON or Mime::MULTIPART)
        # @param accept       [String]      the response type to request (Mime::JSON or Mime::XML), or nil
        # @param query        [Hash]        the arguments to pass as query parameters
        # @param xml_opts     [Hash]        options of `XmlSimple.xml_in` to parse an XML response
        # @param json_opts    [Hash]        options of `JSON.parse` to parse a JSON response
        # @param http         [Boolean]     if true, returns the HttpResponse, else
        def call_ao(endpoint, body: nil, content_type: Mime::JSON, accept: Mime::JSON, query: nil, xml_opts: {}, json_opts: {}, http: false)
          call_args = {operation: body.nil? ? 'GET' : 'POST', subpath: "api/#{endpoint}", ret: :both, query: {}, json_opts: json_opts}
          call_args.merge!(body: body, content_type: content_type) unless body.nil? # rubocop:disable Performance/RedundantMerge
          ret_style = options.get_option(:ret_style, mandatory: true)
          call_args[:query].merge!(query) unless query.nil?
          unless accept.nil?
            # 'json' or 'xml'
            short_type = accept.split('/').last
            case ret_style
            when :header
              call_args[:headers] = {'Accept' => accept}
            when :query
              call_args[:query][:format] = short_type
            when :path
              call_args[:subpath] = "#{call_args[:subpath]}.#{short_type}"
            else Aspera.error_unexpected_value(ret_style) { 'ret_style' }
            end
          end
          add_query = query_read_delete(schema: api_query_schema(endpoint, call_args[:operation]))
          call_args[:query].merge!(add_query.symbolize_keys) unless add_query.nil?
          data, resp = api_orch.call(**call_args)
          return resp if http
          result = accept.eql?(Mime::XML) ? XmlSimple.xml_in(resp.body, xml_opts) : data
          Log.dump(:data, result)
          return result
        end

        # Schema of the query parameters of an endpoint, in the OpenAPI description of Orchestrator (for `--query=help`)
        # @param endpoint  [String] Endpoint, with an id or not, e.g. `journal_files/journal`
        # @param operation [String] HTTP method
        # @return [String, nil] Schema path, or `nil` if the endpoint is not described
        def api_query_schema(endpoint, operation)
          name, id = endpoint.split('/', 2)
          paths = Schema::Registry.instance.reader(Schema::Registry::ORCHESTRATOR)['paths']
          # Orchestrator routes both `api/<name>` and `api/<name>/<id>`: prefer the form used
          candidates = ["api/#{name}", "api/#{name}/{id}"]
          candidates.reverse! unless id.nil?
          path = candidates.find { |candidate| paths.dig("/#{candidate}", operation.downcase) }
          path && Schema::Registry.query_params(Schema::Registry::ORCHESTRATOR, path, method: operation.downcase)
        end

        private :call_ao, :api_query_schema

        # --- DSL ---

        command :health,     description: 'Check Orchestrator API health'
        command :info,       description: 'Check that Orchestrator responds (ping)', action: ->(**) { Result::SingleObject.new(call_ao('remote_node_ping', accept: Mime::XML, xml_opts: {'ForceArray' => false})) }
        command :processes,  description: 'Show Orchestrator background process status', action: ->(**) { Result::ObjectList.new(call_ao('processes_status', accept: Mime::XML, xml_opts: {'ForceArray' => %w[node process]})['node'].flat_map { |n| n['process'] }) }
        command :monitors,   description: 'Monitors of workflows, work orders, folders, remote nodes and scripts'
        command :queues,     description: 'Managed queues'
        command :pools,      description: 'Resource pools'
        command :journal,    description: 'Journal books'
        command :workorders, description: 'Manage work orders'
        command :workstep,   description: 'Manage work steps'

        commands_under :monitors do
          command :snapshot, description: 'Show status of monitors, of all types or of one type',
            arguments: [{name: :type, type: Symbol, mandatory: false, allowed: MONITOR_SNAPSHOT_TYPES}],
            action: ->(type: nil, **) { Result::SingleObject.new(call_ao(type.nil? ? 'monitor_snapshot' : "monitor_snapshot/#{type}")['monitor']) }
          command :list, description: 'List monitors of a type: remote node monitors give the names of remote nodes',
            arguments: [{name: :type, type: Symbol, allowed: MONITOR_TYPES}]
        end

        commands_under :queues do
          command :list, description: 'List managed queues',
            action: ->(**) { Result::ObjectList.new(call_ao('queues_list').dig('Queues', 'queue') || []) }
        end

        commands_under :pools do
          command :status, description: 'Show resources of a resource pool and their status',
            arguments: [{name: :pool_name}],
            # Orchestrator repeats key `id` in each resource
            action: ->(pool_name:, **) { Result::ObjectList.new(call_ao("pool_status/#{ANY_ID}", query: {name: pool_name}, json_opts: {allow_duplicate_key: true})['ManagedResource'] || []) }
        end

        commands_under :journal do
          command :files, description: 'List files recorded in a journal book (filters with option query)',
            arguments: [{name: :book}],
            query_schema: Schema::Registry.query_params(Schema::Registry::ORCHESTRATOR, 'api/journal_files/{id}')
        end

        commands_under :plugins do
          command :list,       description: 'Show Orchestrator plugin versions', action: ->(**) { Result::ObjectList.new(call_ao('plugin_version')['Plugin']) }
          command :reload_set, description: 'Reload a set of plugins',
            arguments: [{name: :plugin_set, type: Hash, schema: 'opts:components.schemas.OrchestratorReloadPluginSet'}],
            action: ->(plugin_set:, **) { Result::SingleObject.new(call_ao('reload_plugin_set', body: plugin_set.transform_keys(&:to_sym))) }
          command :spec, description: "Show specifications of action plugins, from GitHub (no access to Orchestrator): list of plugins, one plugin, or its #{SPEC_SECTIONS.join(', ')}",
            arguments: [
              {name: :plugin, mandatory: false},
              {name: :section, type: Symbol, mandatory: false, allowed: SPEC_SECTIONS}
            ]
        end

        commands_under :workflows do
          command :list, description: 'List all workflows'
          command :status,     description: 'Show running status of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao(workflow_id.eql?(SpecialValues::ALL) ? 'workflows_status' : "workflows_status/#{workflow_id}")['workflows']['workflow']) }
          command :inputs,     description: 'Show input specification of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::SingleObject.new(call_ao("workflow_inputs_spec/#{workflow_id}")['workflow_inputs_spec']) }
          command :details,    description: 'Show detailed running status of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao("workflow_details/#{workflow_id}")['workflows']['workflow']['statuses']) }
          command :start,      description: 'Start a workflow: create a work order (sync or async)',
            arguments: [
              {name: :workflow_id, type: :identifier},
              {name: :parameters, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.OrchestratorInitiateParameters'},
              {name: :execution, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.OrchestratorWorkflowStart'}
            ]
          command :import,     description: 'Import a workflow from a file created by `workflows export`, local problems are reported as warnings (see `check_import`)',
            arguments: [
              {name: :file_path},
              {name: :import, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.OrchestratorWorkflowImport'}
            ]
          command :check_import, description: 'Check a workflow file (no access to Orchestrator): rules that Orchestrator does not check on import, but that make the workflow fail to publish or to run',
            arguments: [{name: :file_path}]
          command :find_constraints, description: 'List the conflicts and missing plugins of a workflow file present on the Orchestrator host, before `import_with_constraints`',
            arguments: [
              {name: :filename},
              {name: :add_as_revision, type: :identifier, mandatory: false}
            ]
          command :publish,    description: 'Publish a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::Status.new(call_ao('publish_workflow', body: {id: workflow_id}).eql?(true) ? 'published' : 'not published') }
          command :import_with_constraints, description: 'Import a workflow file present on the Orchestrator host, with resolution of conflicts',
            arguments: [{name: :payload, type: Hash, schema: 'opts:components.schemas.OrchestratorImportWithConstraints'}]
          command :export,     description: 'Export a workflow: display it, or save it with its dependencies',
            arguments: [
              {name: :workflow_id, type: :identifier},
              {name: :export, type: Hash, mandatory: false, default: {}, schema: 'opts:components.schemas.OrchestratorWorkflowExport'}
            ]
          command :workorders, description: 'List work orders of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao("work_orders_list/#{workflow_id}")['work_orders']) }
          command :development, description: "Show documentation for workflow development, from GitHub (no access to Orchestrator): whole document, its table of contents (#{DOC_TOC}, headings up to level #{DOC_TOC_LEVELS.map { |d, l| "#{l} (#{d})" }.join(', ')}, or argument level), or one section (anchor)",
            arguments: [
              {name: :document, type: Symbol, mandatory: false, default: :authoring, allowed: DOC_FILES.keys},
              {name: :section, mandatory: false},
              {name: :level, type: Integer, mandatory: false}
            ]
          command :outputs,    description: 'Show output specification of a workflow',
            arguments: [{name: :workflow_id, type: :identifier}],
            action: ->(workflow_id:, **) { Result::ObjectList.new(call_ao("workflow_outputs_spec/#{workflow_id}")['workflow_outputs_spec']['output']) }
        end

        commands_under :workorders do
          command :status, description: 'Show status of a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::SingleObject.new(call_ao("work_order_status/#{workorder_id}")['work_order']) }
          command :cancel, description: 'Cancel a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::SingleObject.new(call_ao("work_order_cancel/#{workorder_id}")['work_order']) }
          command :reset,  description: 'Reset a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::SingleObject.new(call_ao("work_order_reset/#{workorder_id}")['work_order']) }
          command :output, description: 'Show output of a work order',
            arguments: [{name: :workorder_id, type: :identifier}],
            action: ->(workorder_id:, **) { Result::ObjectList.new(call_ao("work_order_output/#{workorder_id}", accept: Mime::XML, xml_opts: {'ForceArray' => %w[variable], 'SuppressEmpty' => nil})['variable']) }
        end

        commands_under :workstep do
          command :status, description: 'Show status of a work step',
            arguments: [{name: :workstep_id, type: :identifier}]
          command :cancel, description: 'Cancel a work step',
            arguments: [{name: :workstep_id, type: :identifier}],
            action: ->(workstep_id:, **) { Result::SingleObject.new(call_ao("work_step_cancel/#{workstep_id}")) }
        end

        # --- API ---

        # Orchestrator REST API, built from CLI options on first use.
        # @return [Rest::Client]
        def api_orch
          return @api_orch if @api_orch
          base_url = options.get_option(:url, mandatory: true)
          style = options.get_option(:auth_style, mandatory: true)
          apikey = options.get_option(:apikey)
          username = options.get_option(:username)
          password = options.get_option(:password)
          Aspera.assert(apikey.nil? || (username.nil? && password.nil?), type: Cli::BadArgument) { 'apikey and username/password are mutually exclusive' }
          Aspera.assert(!apikey.nil? || (!username.nil? && !password.nil?), type: Cli::BadArgument) { 'provide either apikey or username and password' }

          auth_params =
            case style
            when :basic
              Aspera.assert(apikey.nil?, type: Cli::BadArgument) { 'basic auth style cannot be used with apikey, use token or query' }
              {
                type:     :basic,
                username: username,
                password: password
              }
            when :query
              if apikey
                {type: :url, url_query: {'apikey' => apikey}}
              else
                {type: :url, url_query: {'login' => username, 'password' => password}}
              end
            when :token
              {
                type:         :oauth2,
                grant_method: :json_credentials,
                base_url:     base_url,
                path_token:   'api/login',
                token_field:  'token',
                json:         apikey ? {apikey: apikey} : {username: username, password: password}
              }
            else Aspera.error_unexpected_value(style)
            end
          @api_orch = Rest::Client.new(
            base_url: base_url,
            auth:     auth_params
          )
        end

        def action_health(**)
          nagios = Nagios.new
          begin
            info = call_ao('remote_node_ping', accept: Mime::XML, xml_opts: {'ForceArray' => false})
            nagios.add_ok('api', 'accessible')
            nagios.check_product_version('api', 'orchestrator', info['orchestrator-version'])
          rescue StandardError => e
            nagios.add_critical('node api', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        # Monitors of work orders are wrapped in `monitor-workorder`
        def action_monitors_list(type:, **)
          monitors = call_ao("list_monitors/#{ANY_ID}", query: {monitor_type: type})
          Result::ObjectList.new(monitors.map { |monitor| monitor.is_a?(Hash) && monitor.size.eql?(1) && monitor.key?('monitor-workorder') ? monitor['monitor-workorder'] : monitor })
        end

        # Files of the packages, and files without package, with the name of their package
        def action_journal_files(book:, **)
          report = call_ao("journal_files/#{book}")
          files = Array(report['Packages']).flat_map { |package| Array(package['files']).map { |file| {'package' => package['name']}.merge(file) } }
          Result::ObjectList.new(files + Array(report['Files']))
        end

        # Fields of the work step that Orchestrator returns as YAML dumps of its Ruby objects (`prerequisites`, `work_outputs`...)
        # are removed: they are not readable, and the inputs and outputs are also given as `inputs` and `outputs`.
        def action_workstep_status(workstep_id:, **)
          status = call_ao("work_step_status/#{workstep_id}")
          status['work_step']&.reject! { |_name, value| value.is_a?(String) && value.match?(YAML_DUMP) }
          Result::SingleObject.new(status)
        end

        # 2.1/2.2 Initiate a workorder (async / synchronous)
        def action_workflows_list(**)
          Result::ObjectList.new(
            call_ao('workflows_list')['workflows']['workflow'],
            fields: %w[id portable_id name folder_id published_status published_revision_id latest_revision_id last_modification]
          )
        end

        # The document is read from GitHub: does not require access to Orchestrator
        # @param level [Integer, nil] Maximum level of headings of the table of contents (default per document)
        def action_workflows_development(document: :authoring, section: nil, level: nil, **)
          require 'aspera/markdown'
          require 'aspera/uri_reader'
          Aspera.assert(level.nil? || section.eql?(DOC_TOC), type: Cli::BadArgument) { "argument level is only for #{DOC_TOC}" }
          content = UriReader.read("#{DOC_BASE_URL}/#{DOC_FILES[document]}")
          return Result::Text.new(content) if section.nil?
          return Result::ObjectList.new(Markdown.toc(content, max_level: level || DOC_TOC_LEVELS[document]), fields: %w[level title anchor]) if section.eql?(DOC_TOC)
          text = Markdown.extract_section(content, section)
          Aspera.assert(!text.nil?, type: Cli::Error) { "Section not found: #{section}, use #{DOC_TOC} to list anchors" }
          Result::Text.new(text)
        end

        # Specifications of action plugins, read from GitHub, or from option `plugin_specs`: does not require access to Orchestrator
        # @return [Hash] Class name of plugin => attributes, inputs, outputs
        def plugin_specs
          return @plugin_specs if @plugin_specs
          require 'aspera/uri_reader'
          require 'aspera/yaml'
          specs = Yaml.safe_load(UriReader.read(options.get_option(:plugin_specs, mandatory: true)))
          Aspera.assert_type(specs, Hash, type: Cli::Error) { 'plugin specifications' }
          @plugin_specs = specs
        end

        # @param plugin  [String, nil] Class name of the plugin (case insensitive), or nil to list plugins
        # @param section [Symbol, nil] One of SPEC_SECTIONS, or nil for the whole specification
        def action_plugins_spec(plugin: nil, section: nil, **)
          specs = plugin_specs
          return Result::ObjectList.new(specs.map { |name, spec| {'name' => name}.merge(spec.except(*SPEC_SECTIONS.map(&:to_s), 'notes')) }, fields: SPEC_LIST_FIELDS) if plugin.nil?
          name = specs.keys.find { |key| key.casecmp?(plugin) }
          if name.nil?
            similar = specs.keys.select { |key| key.downcase.include?(plugin.downcase) }
            raise Cli::BadArgument, "Unknown plugin: #{plugin}#{", similar: #{similar.join(', ')}" unless similar.empty?}, use `plugins spec` to list plugins"
          end
          return Result::SingleObject.new({'name' => name}.merge(specs[name])) if section.nil?
          Result::ObjectList.new(specs[name][section.to_s].map { |key, value| {'name' => key}.merge(value) })
        end

        # Without dependencies, the workflow file (YAML) is displayed.
        # With dependencies, the package (binary) is saved in the destination folder.
        def action_workflows_export(workflow_id:, export:, **)
          dependencies = export.transform_keys(&:to_s)['dependencies'].eql?(true)
          # Orchestrator exports dependencies for any value of the parameter
          begin
            resp = call_ao("export_workflow/#{workflow_id}", accept: nil, query: dependencies ? {export_with_dependencies: true} : nil, http: true)
          rescue Rest::CallError
            # Orchestrator 4.1.6 fails to build the package of some workflows (it is written in the folder it packs)
            Log.log.warn('Export with dependencies failed: export the workflow and each sub-workflow without dependencies instead') if dependencies
            raise
          end
          return Result::Text.new(resp.body) unless dependencies
          disposition = resp['Content-Disposition']
          file_name = disposition && Rest.parse_header(disposition)[:parameters][:filename]
          file_path = File.join(transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE), File.basename(file_name || "Workflow_#{workflow_id}.wkf"))
          File.binwrite(file_path, resp.body)
          Result::Status.new("Saved to: #{file_path}")
        end

        # Check of a workflow file, for problems that Orchestrator does not detect on import: it imports an invalid workflow, which then fails to publish or to run.
        # This is the only place that knows how the check is done: it is done locally, because Orchestrator has no such API.
        # When it has one (same request as `import_workflow`), replace the body by a call, e.g.
        # `call_ao('check_workflow', body: [['import_file', content, {filename: file_name}], ['import_file_name', file_name]], content_type: Mime::MULTIPART)`
        # The response is a Hash, see {OrchestratorWorkflowChecker}.
        # Templates and inputs of steps are checked with the specifications of plugins (see `plugins spec`), when they can be read.
        # @param file_path [String] Workflow file (`.yml` or `.wkf`)
        # @return [Hash] `valid` (Boolean), `file_name`, `issues` (list of Hash: `severity`, `code`, `file`, `path`, `message`)
        def check_workflow(file_path)
          require 'aspera/orchestrator_workflow_checker'
          specs = nil
          specs_error = nil
          begin
            specs = plugin_specs
          rescue StandardError => e
            specs_error = e.message
          end
          response = OrchestratorWorkflowChecker.check(file_name: File.basename(file_path), content: File.binread(file_path), specs: specs)
          unless specs_error.nil?
            response['issues'].push({
              'severity' => 'warning',
              'code'     => 'plugins.specs_unavailable',
              'path'     => 'templates',
              'message'  => "plugin specifications not read (#{specs_error}): templates and inputs of steps are not checked"
            })
          end
          response
        end

        # @param file_path [String] Workflow file
        # @return [Result] The issues found, or a status if none
        def action_workflows_check_import(file_path:, **)
          response = check_workflow(file_path)
          return Result::Status.new('no problem found') if response['issues'].empty?
          Result::ObjectList.new(response['issues'], fields: %w[severity code file path message])
        end

        # Conflicts and missing plugins found by Orchestrator, as one row per name to resolve.
        # Orchestrator does not check that the file exists: for a wrong path, it returns the same empty result as for a file without conflict.
        # @return [Hash{String=>Object}] Items returned by Orchestrator, by name (`subwf constraints`, `missing plugins`...)
        def server_constraints(filename, add_as_revision = nil)
          list = call_ao('find_constraints', query: {file: filename, wf_id: add_as_revision}.compact)
          Aspera.assert_type(list, Array, type: Cli::Error) { 'response of find_constraints' }
          list.grep(Hash).reduce({}, :merge)
        end

        # Keys of the conflicts in Orchestrator response => keys of the argument of `import_with_constraints`
        CONSTRAINT_KEYS = {
          'subwf constraints'           => 'subwf_constraints',
          'action template constraints' => 'action_template_constraints',
          'remote node constraints'     => 'remote_node_constraints'
        }.freeze
        private_constant :CONSTRAINT_KEYS

        def action_workflows_find_constraints(filename:, add_as_revision: nil, **)
          found = server_constraints(filename, add_as_revision)
          rows = CONSTRAINT_KEYS.flat_map do |api_key, key|
            (found[api_key] || {}).map { |name, choices| {'type' => key, 'name' => name, 'choices' => choices} }
          end
          Array(found['missing plugins']).each do |name|
            rows.push({'type' => 'missing_plugins', 'name' => name, 'choices' => 'auto_enable_missing_plugins: true'})
          end
          return Result::Status.new('no conflict found (Orchestrator gives the same answer if the file does not exist)') if rows.empty?
          Result::ObjectList.new(rows, fields: %w[type name choices])
        end

        # Orchestrator fails or decides silently in these cases, which the web interface prevents:
        # - plugins to enable but `auto_enable_missing_plugins` not true: the import fails with an internal error
        # - resolution given for some conflicts only: the others are imported as copies, without error
        # @param payload [Hash] Argument of `import_with_constraints`, with string keys
        def check_import_constraints(payload)
          found = server_constraints(payload['filename'], payload['add_as_revision'])
          problems = []
          missing = Array(found['missing plugins'])
          problems.push("plugins are not enabled: #{missing.join(', ')}, set auto_enable_missing_plugins to true") unless missing.empty? || payload['auto_enable_missing_plugins'].eql?(true)
          CONSTRAINT_KEYS.each do |api_key, key|
            chosen = payload[key]
            next if chosen.nil? || chosen.empty?
            unresolved = (found[api_key] || {}).keys - chosen.keys.map(&:to_s)
            problems.push("#{key} not resolved for: #{unresolved.join(', ')} (see `workflows find_constraints`)") unless unresolved.empty?
          end
          raise Cli::BadArgument, "Import refused: #{problems.join('; ')}" unless problems.empty?
        end

        # The file is uploaded as a multipart form
        # @param import [Hash] Options: `folder_id`, `publish`, `link_to_subworkflows`
        def action_workflows_import(file_path:, import: {}, **)
          import = import.transform_keys(&:to_s)
          check_workflow(file_path)['issues'].each do |issue|
            Log.log.warn { "#{issue['severity']}: #{[issue['file'], issue['path']].compact.join(' ')}: #{issue['message']} (#{issue['code']})" }
          end
          file_name = File.basename(file_path)
          form = [
            ['import_file', File.binread(file_path), {filename: file_name}],
            ['import_file_name', file_name]
          ]
          form.push(['folder_id', import['folder_id'].to_s]) if import.key?('folder_id')
          # `false` overrides the server option `publish_api_imported_workflow`
          form.push(['publish_workflow', import['publish'].to_s]) if import.key?('publish')
          # Orchestrator takes any value as true
          form.push(%w[link_to_subworkflows true]) if import['link_to_subworkflows'].eql?(true)
          result = call_ao('import_workflow', body: form, content_type: Mime::MULTIPART)
          # Other responses: nothing was imported
          if result.key?('plugins')
            raise Cli::Error, "Plugins could not be enabled: #{Array(result['plugins']).join(', ')}" \
              "#{" (missing dependencies: #{Array(result['missing_deps']).join(', ')})" unless Array(result['missing_deps']).empty?}"
          end
          if result.key?('dependencies')
            dependencies = result['dependencies'].values.flatten.filter_map { |d| "#{d['entity']} #{d['id_value']}" if d.is_a?(Hash) }
            raise Cli::Error, "Workflow dependencies are not included in the file (export with dependencies to a .wkf file): #{dependencies.uniq.join(', ')}"
          end
          Result::SingleObject.new(result['workflow'])
        end

        # Items of the array expected by `import_with_constraints`, in this order: argument key => API key
        IMPORT_CONSTRAINT_ITEMS = {
          'filename'                    => 'filename',
          'add_as_revision'             => 'add as revision',
          'subwf_constraints'           => 'subwf constraints',
          'action_template_constraints' => 'action template constraints',
          'remote_node_constraints'     => 'remote node constraints',
          'auto_enable_missing_plugins' => 'Auto-enable missing plugins?'
        }.freeze
        private_constant :IMPORT_CONSTRAINT_ITEMS

        # The API expects an array of single-key objects, in a fixed order
        def action_workflows_import_with_constraints(payload:, **)
          payload = payload.transform_keys(&:to_s)
          check_import_constraints(payload)
          body = IMPORT_CONSTRAINT_ITEMS.map { |key, api_key| {api_key => payload.fetch(key) { key.end_with?('_constraints') ? {} : nil }} }
          Result::SingleObject.new(call_ao('import_with_constraints', body: body)['workflow'])
        end

        # Keys of argument `execution` of `workflows start`
        WORKFLOW_START_KEYS = %w[synchronous step variable].freeze
        private_constant :WORKFLOW_START_KEYS

        def action_workflows_start(workflow_id:, parameters:, execution:, **)
          execution = execution.transform_keys(&:to_s)
          unknown = execution.keys - WORKFLOW_START_KEYS
          Aspera.assert(unknown.empty?, type: Cli::BadArgument) { "Unknown keys in execution: #{unknown.join(', ')}, expected: #{WORKFLOW_START_KEYS.join(', ')}" }
          # Deprecated options, used when key not provided
          execution['synchronous'] = options.get_option(:synchronous) unless execution.key?('synchronous')
          result_location = options.get_option(:result)
          unless result_location.nil? || execution.key?('step') || execution.key?('variable')
            fields = result_location.split(':')
            Aspera.assert(fields.length == 2, type: Cli::BadArgument) { "Expects: work_step:result_name : #{result_location}" }
            execution['step'], execution['variable'] = fields
          end
          # POST /api/initiate with JSON body {workflow_id:, external_parameters:}
          json_body = {workflow_id: workflow_id.to_i, external_parameters: parameters}
          # control params passed as query string (not part of the spec requestBody)
          query_params = {}
          Aspera.assert_type(execution['synchronous'], NilClass, *BoolValue::TYPES, type: Cli::BadArgument) { 'synchronous' }
          query_params[:synchronous] = true if execution['synchronous'].eql?(true)
          # expected result for synchro call ?
          if execution.key?('step') || execution.key?('variable')
            Aspera.assert(execution['step'].is_a?(String) && execution['variable'].is_a?(String), type: Cli::BadArgument) { 'Both step and variable are required' }
            query_params[:explicit_output_step] = execution['step']
            query_params[:explicit_output_variable] = execution['variable']
            # implicitly, call is synchronous
            query_params[:synchronous] = true
          end
          # Work order information, or value of the explicit output (any JSON value)
          Result.auto(call_ao('initiate', body: json_body, query: query_params.empty? ? nil : query_params))
        end
      end
    end
  end
end

# 17.Persist custom data
# 18.Fetch queued items from queue
# 20.List Task for a User
# 21. Fetch Task details
# 22. Submit Task
# 23. Control Process
# engine monitor worker
# 24. Lookup Queued Item
# 25. Reorder Queued Items
# 26. Bulk Reorder Queued Items
# 27. Queue Item (Add an item to a Queue)
#
# Required Input:
# Optional Input:
# 28.List all queues
# 29. Portlet Version
# 30. Plugin Version
# 31. Restart Work Order from a Step
# 32. Delete element from a Managed Queue
#
