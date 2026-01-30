# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/rest'
require 'aspera/hash_ext'
require 'aspera/data_repository'
require 'aspera/transfer/spec'
require 'aspera/api/node'
require 'base64'

module Aspera
  module Api
    class AoC < Rest
      PRODUCT_NAME = 'Aspera on Cloud'
      # use default workspace if it is set, else none
      DEFAULT_WORKSPACE = ''
      # Production domain of AoC
      SAAS_DOMAIN_PROD = 'ibmaspera.com' # cspell:disable-line
      # To avoid infinite loop in pub link redirection
      MAX_AOC_URL_REDIRECT = 10
      CLIENT_ID_PREFIX = 'aspera.'
      # Well-known AoC global client apps
      GLOBAL_CLIENT_APPS = DataRepository::ELEMENTS.select{ |i| i.to_s.start_with?(CLIENT_ID_PREFIX)}.freeze
      # cookie prefix so that console can decode identity
      COOKIE_PREFIX_CONSOLE_AOC = 'aspera.aoc'
      # path in URL of public links
      PUBLIC_LINK_PATHS = %w[/packages/public/receive /packages/public/send /files/public /public/files /public/package /public/send].freeze
      JWT_AUDIENCE = 'https://api.asperafiles.com/api/v1/oauth2/token'
      OAUTH_API_SUBPATH = 'api/v1/oauth2'
      # minimum fields for user info if retrieval fails
      USER_INFO_FIELDS_MIN = %w[name email id default_workspace_id organization_id].freeze
      # types of events for shared folder creation
      # Node events: permission.created permission.modified permission.deleted
      PERMISSIONS_CREATED = ['permission.created'].freeze
      # Special user identifier when creating workspace shared folders
      ID_AK_ADMIN = 'ASPERA_ACCESS_KEY_ADMIN'

      private_constant :MAX_AOC_URL_REDIRECT,
        :CLIENT_ID_PREFIX,
        :GLOBAL_CLIENT_APPS,
        :COOKIE_PREFIX_CONSOLE_AOC,
        :PUBLIC_LINK_PATHS,
        :JWT_AUDIENCE,
        :OAUTH_API_SUBPATH,
        :USER_INFO_FIELDS_MIN,
        :PERMISSIONS_CREATED,
        :ID_AK_ADMIN

      # Various API scopes supported
      module Scope
        SELF = 'self'
        USER = 'user:all'
        ADMIN = 'admin:all'
        ADMIN_USER = 'admin-user:all'
        ADMIN_USER_USER = "#{ADMIN_USER}+#{USER}"
      end
      FILES_APP = 'files'
      PACKAGES_APP = 'packages'
      API_V1 = 'api/v1'

      # class static methods
      class << self
        # strings /Applications/Aspera\ Drive.app/Contents/MacOS/AsperaDrive|grep -E '.{100}==$'|base64 --decode
        def get_client_info(client_name = nil)
          client_key = client_name.nil? ? GLOBAL_CLIENT_APPS.first : client_name.to_sym
          return client_key, DataRepository.instance.item(client_key)
        end

        # base API url depends on domain, which could be "qa.xxx" or self-managed domain
        def api_base_url(api_domain: SAAS_DOMAIN_PROD)
          return "https://api.#{api_domain}"
        end

        # split host of URL into organization and domain
        def split_org_domain(uri)
          Aspera.assert_type(uri, URI)
          Aspera.assert(!uri.host.nil?){"No host found in URL. Please check URL format: https://myorg.#{SAAS_DOMAIN_PROD}"}
          parts = uri.host.split('.', 2)
          Aspera.assert(parts.length == 2){"expecting a public FQDN for #{PRODUCT_NAME}"}
          parts[0] = nil if parts[0].eql?('api')
          return %i{organization domain}.zip(parts).to_h
        end

        def saas_url?(url)
          URI.parse(url).host&.end_with?(".#{SAAS_DOMAIN_PROD}")
        rescue URI::InvalidURIError
          false
        end

        # @param url [String] URL of AoC public link
        # @return [Hash] information about public link, or nil if not a public link
        def link_info(url)
          final_uri = Rest.new(base_url: url, redirect_max: MAX_AOC_URL_REDIRECT).call(operation: 'GET', ret: :resp).uri
          Log.dump(:final_uri, final_uri, level: :trace1)
          org_domain = split_org_domain(final_uri)
          if (m = final_uri.path.match(%r{/oauth2/([^/]+)/login$}))
            org_domain[:organization] = m[1] if org_domain[:organization].nil?
          else
            Log.log.debug{"path=#{final_uri.path} does not end with /login"}
          end
          Aspera.assert(!final_uri.query.nil?, 'AoC shall redirect to login page with a query', type: Error)
          query = Rest.query_to_h(final_uri.query)
          Log.dump(:query, query, level: :trace1)
          # is that a public link ?
          if query.key?('token')
            Log.log.warn{"Unknown pub link path: #{final_uri.path}"} unless PUBLIC_LINK_PATHS.include?(final_uri.path)
            # ok we get it !
            return {
              instance_domain: org_domain[:domain],
              url:             "https://#{final_uri.host}",
              token:           query['token']
            }
          end
          if query.key?('state')
            # can be a private link
            state_uri = URI.parse(query['state'])
            if state_uri.query && query['redirect_uri']
              decoded_state = Rest.query_to_h(state_uri.query)
              if decoded_state.key?('short_link_url')
                if (m = state_uri.path.match(%r{/files/workspaces/([0-9]+)/all/([0-9]+):([0-9]+)}))
                  redirect_uri = URI.parse(query['redirect_uri'])
                  org_domain = split_org_domain(redirect_uri)
                  return {
                    instance_domain: org_domain[:domain],
                    organization:    org_domain[:organization],
                    url:             "https://#{redirect_uri.host}",
                    private_link:    {
                      workspace_id: m[1],
                      node_id:      m[2],
                      file_id:      m[3]
                    }
                  }
                end
              end
            end
          end
          Log.dump(:org_domain, org_domain)
          return {
            instance_domain: org_domain[:domain],
            organization:    org_domain[:organization]
          }
        end

        # Call block with same query using paging and response information.
        # Block must return an Array with data and http response
        # @return [Hash] {items: , total: }
        def call_paging(query: nil, formatter: nil)
          query = {} if query.nil?
          Aspera.assert_type(query, Hash){'query'}
          Aspera.assert(block_given?)
          # set default large page if user does not specify own parameters. AoC Caps to 1000 anyway
          query['per_page'] = 1000 unless query.key?('per_page')
          max_items = query.delete(Rest::MAX_ITEMS)
          max_pages = query.delete(Rest::MAX_PAGES)
          item_list = []
          total_count = nil
          current_page = query['page']
          current_page = 1 if current_page.nil?
          page_count = 0
          loop do
            new_query = query.clone
            new_query['page'] = current_page
            result_data, result_http = yield(new_query)
            Aspera.assert(result_http)
            total_count = result_http['X-Total-Count']&.to_i
            page_count += 1
            current_page += 1
            add_items = result_data
            break if add_items.nil?
            break if add_items.empty?
            # append new items to full list
            item_list += add_items
            break if !max_items.nil? && item_list.count >= max_items
            break if !max_pages.nil? && page_count >= max_pages
            break if total_count&.<=(item_list.count)
            formatter&.long_operation_running("#{item_list.count} / #{total_count}") unless total_count.eql?(item_list.count.to_s)
          end
          formatter&.long_operation_terminated
          item_list = item_list[0..max_items - 1] if !max_items.nil? && item_list.count > max_items
          return {items: item_list, total: total_count}
        end

        # @param id [String] Identifier or workspace
        # @return [Hash] suitable for permission filtering
        def workspace_access(id)
          {
            'access_type' => 'user',
            'access_id'   => "#{ID_AK_ADMIN}_WS_#{id}"
          }
        end

        # @param permission [Hash] Shared folder information
        # @return [Boolean] `true` if internal access
        def workspace_access?(permission)
          permission['access_id'].start_with?("#{ID_AK_ADMIN}_WS_")
        end

        # Expand access levels to full list of levels.
        # @param levels [nil, String, Array] Access levels
        # @return [Array] Expanded access levels
        def expand_access_levels(levels)
          case levels
          when nil, 'edit' then Node::ACCESS_LEVELS
          when 'preview' then %w[list preview]
          when 'download' then %w[list preview read]
          when 'upload' then %w[mkdir write]
          when Array
            Aspera.assert_array_all(levels, String){'access_levels'}
            levels.each{ |level| Aspera.assert_value(level, Node::ACCESS_LEVELS){'access_level'}}
            levels
          else Aspera.error_unexpected_value(levels){"access_levels must be a list of #{Node::ACCESS_LEVELS.join(', ')} or one of edit, preview, download, upload"}
          end
        end
      end

      attr_reader :private_link

      def initialize(
        url:,
        auth:,
        subpath: API_V1,
        client_id: nil,
        client_secret: nil,
        scope: nil,
        redirect_uri: nil,
        private_key: nil,
        passphrase: nil,
        username: nil,
        password: nil,
        workspace: nil,
        secret_finder: nil
      )
        # Test here because link may set url
        Aspera.assert(url, 'Missing mandatory option: url', type: ParameterError)
        Aspera.assert(scope, 'Missing mandatory option: scope', type: ParameterError)
        # default values for client id
        client_id, client_secret = self.class.get_client_info if client_id.nil?
        # access key secrets are provided out of band to get node api access
        # key: access key
        # value: associated secret
        @secret_finder = secret_finder
        @workspace_name = workspace
        @cache_user_info = nil
        @cache_url_token_info = nil
        @workspace_info = nil
        @home_info = nil
        auth_params = {
          type:   :oauth2,
          params: {
            client_id:     client_id,
            client_secret: client_secret,
            scope:         scope
          }
        }
        # analyze type of url
        url_info = AoC.link_info(url)
        Log.dump(:url_info, url_info)
        @private_link = url_info[:private_link]
        auth_params[:grant_method] = if url_info.key?(:token)
          :url_json
        else
          Aspera.assert(auth, 'Missing mandatory option: auth', type: ParameterError)
          auth
        end
        # this is the base API url
        api_url_base = self.class.api_base_url(api_domain: url_info[:instance_domain])
        # auth URL
        auth_params[:base_url] = "#{api_url_base}/#{OAUTH_API_SUBPATH}/#{url_info[:organization]}"
        # fill other auth parameters based on OAuth method
        case auth_params[:grant_method]
        when :web
          Aspera.assert(redirect_uri, 'Missing mandatory option: redirect_uri', type: ParameterError)
          auth_params[:redirect_uri] = redirect_uri
        when :jwt
          Aspera.assert(private_key, 'Missing mandatory option: private_key', type: ParameterError)
          Aspera.assert(username, 'Missing mandatory option: username', type: ParameterError)
          auth_params[:private_key_obj] = OpenSSL::PKey::RSA.new(private_key, passphrase)
          auth_params[:payload] = {
            iss: client_id, # issuer
            sub: username, # subject
            aud: JWT_AUDIENCE
          }
          # add jwt payload for global client id
          auth_params[:payload][:org] = url_info[:organization] if GLOBAL_CLIENT_APPS.include?(client_id)
          auth_params[:cache_ids] = [url_info[:organization]]
        when :url_json
          auth_params[:url] = {grant_type: 'url_token'} # Query arguments
          auth_params[:json] = {url_token: url_info[:token]} # JSON body
          # password protection of link
          auth_params[:json][:password] = password unless password.nil?
          # basic auth required for /token
          auth_params[:auth] = {type: :basic, username: client_id, password: client_secret}
        else Aspera.error_unexpected_value(auth_params[:grant_method]){'auth, use one of: :web, :jwt'}
        end
        super(
          base_url: "#{api_url_base}/#{subpath}",
          auth: auth_params
          )
      end

      # read using the query and paging
      # @return [Hash] {items: , total: }
      def read_with_paging(subpath, query = nil, formatter: nil)
        return self.class.call_paging(query: query, formatter: formatter) do |paged_query|
          read(subpath, query: paged_query, ret: :both)
        end
      end

      def assert_public_link_types(expected)
        Aspera.assert_values(public_link['purpose'], expected){'public link type'}
      end

      def additional_persistence_ids
        return [current_user_info['id']] if public_link.nil?
        return [] # TODO : public_link['id'] ?
      end

      # Cached public link information
      # @return [Hash, nil] token info if public link or nil
      def public_link
        return unless auth_params[:grant_method].eql?(:url_json)
        return @cache_url_token_info unless @cache_url_token_info.nil?
        # TODO: can there be several in list ?
        @cache_url_token_info = read('url_tokens').first
        return @cache_url_token_info
      end

      # Cached user information
      def current_user_info(exception: false)
        return @cache_user_info unless @cache_user_info.nil?
        # get our user's default information
        @cache_user_info =
          begin
            read('self')
          rescue StandardError => e
            raise e if exception
            Log.log.debug{"ignoring error: #{e}"}
            {}
          end
        USER_INFO_FIELDS_MIN.each{ |f| @cache_user_info[f] = nil if @cache_user_info[f].nil?}
        return @cache_user_info
      end

      # Cached workspace information
      def workspace
        return @workspace_info unless @workspace_info.nil?
        ws_id =
          if !public_link.nil?
            Log.log.debug('Using workspace of public link')
            public_link['data']['workspace_id']
          elsif !private_link.nil?
            Log.log.debug('Using workspace of private link')
            private_link[:workspace_id]
          elsif @workspace_name.eql?(DEFAULT_WORKSPACE)
            if !current_user_info['default_workspace_id'].nil?
              Log.log.debug('Using default workspace'.green)
              current_user_info['default_workspace_id']
            end
          elsif @workspace_name.nil?
            nil
          else
            lookup_by_name('workspaces', @workspace_name)['id']
          end
        @workspace_info =
          if ws_id.nil?
            {
              name: 'Shared (no workspace)'
            }
          else
            read("workspaces/#{ws_id}").slice('id', 'name', 'home_node_id', 'home_file_id').symbolize_keys
          end
        Log.dump(:workspace_info, @workspace_info)
        @workspace_info
      end

      # Cached Home information for current user in Files app
      def home
        return @home_info unless @home_info.nil?
        @home_info =
          if !public_link.nil?
            assert_public_link_types(['view_shared_file'])
            {
              node_id: public_link['data']['node_id'],
              file_id: public_link['data']['file_id']
            }
          elsif !private_link.nil?
            {
              node_id: private_link[:node_id],
              file_id: private_link[:file_id]
            }
          elsif workspace[:home_node_id] && workspace[:home_file_id]
            {
              node_id: workspace[:home_node_id],
              file_id: workspace[:home_file_id]
            }
          else
            # not part of any workspace, but has some folder shared
            user_info = current_user_info(exception: true) rescue {'read_only_home_node_id' => nil, 'read_only_home_file_id' => nil}
            {
              node_id: user_info['read_only_home_node_id'],
              file_id: user_info['read_only_home_file_id']
            }
          end
        Aspera.assert(!@home_info[:node_id].to_s.empty?, "Cannot get user's home node id, check your default workspace or specify one", type: Error)
        Log.dump(:context, @home_info)
        @home_info
      end

      # Return a Node API for given node id, in a given context (files, packages), for the given scope.
      # @param node_id        [String] identifier of node in AoC
      # @param workspace_id   [String,nil] workspace identifier
      # @param workspace_name [String,nil] workspace name
      # @param scope          [String,nil] e.g. Node::Scope::USER, or Node::Scope::ADMIN, or nil (requires secret)
      # @param package_info   [Hash,nil] created package information
      # @returns [Node] a node API for access key
      def node_api_from(node_id:, workspace_id: nil, workspace_name: nil, scope: Node::Scope::USER, package_info: nil)
        Aspera.assert_type(node_id, String)
        node_info = read("nodes/#{node_id}")
        workspace_name = read("workspaces/#{workspace_id}")['name'] if workspace_name.nil? && !workspace_id.nil?
        app_info = {
          api:            self, # for callback
          app:            package_info.nil? ? FILES_APP : PACKAGES_APP,
          node_info:      node_info,
          workspace_id:   workspace_id,
          workspace_name: workspace_name
        }
        if PACKAGES_APP.eql?(app_info[:app])
          Aspera.assert(!package_info.nil?){'package info required'}
          app_info[:package_id] = package_info['id']
          app_info[:package_name] = package_info['name']
        end
        node_params = {base_url: node_info['url']}
        ak_secret = @secret_finder&.lookup_secret(url: node_info['url'], username: node_info['access_key'])
        # If secret is available, or no scope, use basic auth
        if scope.nil? || ak_secret
          Aspera.assert(ak_secret, "Secret not found for access key #{node_info['access_key']}@#{node_info['url']}", type: Error)
          node_params[:auth] = {
            type:     :basic,
            username: node_info['access_key'],
            password: ak_secret
          }
        else
          # OAuth bearer token
          node_params[:auth] = auth_params.clone
          node_params[:auth][:params] ||= {}
          node_params[:auth][:params][:scope] = Node.token_scope(node_info['access_key'], scope)
          node_params[:auth][:params][:owner_access] = true if scope.eql?(Node::Scope::ADMIN)
          # Special header required for bearer token only
          node_params[:headers] = {Node::HEADER_X_ASPERA_ACCESS_KEY => node_info['access_key']}
        end
        node_params[:app_info] = app_info
        return Node.new(**node_params)
      end

      # Check metadata: remove when validation is done server side
      def validate_metadata(pkg_data)
        # validate only for shared inboxes
        return unless pkg_data['recipients'].is_a?(Array) &&
          pkg_data['recipients'].first.is_a?(Hash) &&
          pkg_data['recipients'].first.key?('type') &&
          pkg_data['recipients'].first['type'].eql?('dropbox')
        meta_schema = read("dropboxes/#{pkg_data['recipients'].first['id']}")['metadata_schema']
        if meta_schema.nil? || meta_schema.empty?
          Log.log.debug('no metadata in shared inbox')
          return
        end
        Aspera.assert(pkg_data.key?('metadata')){"package requires metadata: #{meta_schema}"}
        pkg_meta = pkg_data['metadata']
        Aspera.assert_type(pkg_meta, Array){'metadata'}
        Log.dump(:metadata, pkg_meta)
        pkg_meta.each do |field|
          Aspera.assert_type(field, Hash){'metadata field'}
          Aspera.assert(field.key?('name')){'metadata field must have name'}
          Aspera.assert(field.key?('values')){'metadata field must have values'}
          Aspera.assert_type(field['values'], Array){'metadata field values'}
          Aspera.assert(!meta_schema.none?{ |i| i['name'].eql?(field['name'])}){"unknown metadata field: #{field['name']}"}
        end
        meta_schema.each do |field|
          provided = pkg_meta.select{ |i| i['name'].eql?(field['name'])}
          Aspera.assert(provided.count <= 1, type: Error){"only one field with name #{field['name']} allowed"}
          Aspera.assert(!provided.empty?, type: Error){"missing mandatory field: #{field['name']}"} if field['required']
        end
      end

      # Normalize package creation recipient lists as expected by AoC API
      # AoC expects {type: , id: }, but ascli allows providing either the native values or just a name
      # in that case, the name is resolved and replaced with {type: , id: }
      # @param package_data    [Hash]   The whole package creation payload
      # @param rcpt_lst_field  [String] The field in structure, i.e. recipients or bcc_recipients
      # @param new_user_option [Hash]   Additionnal fields for contact creation
      # @return nil, `package_data` is modified
      def resolve_package_recipients(package_data, rcpt_lst_field, new_user_option)
        return unless package_data.key?(rcpt_lst_field)
        Aspera.assert_type(package_data[rcpt_lst_field], Array){rcpt_lst_field}
        new_user_option = {'package_contact' => true} if new_user_option.nil?
        Aspera.assert_type(new_user_option, Hash){'new_user_option'}
        ws_id = package_data['workspace_id']
        # list with resolved elements
        resolved_list = []
        package_data[rcpt_lst_field].each do |short_recipient_info|
          case short_recipient_info
          when Hash # native API information, check keys
            Aspera.assert(short_recipient_info.keys.sort.eql?(%w[id type])){"#{rcpt_lst_field} element shall have fields: id and type"}
          when String # CLI helper: need to resolve provided name to type/id
            # email: user, else dropbox
            entity_type = short_recipient_info.include?('@') ? 'contacts' : 'dropboxes'
            begin
              full_recipient_info = lookup_by_name(entity_type, short_recipient_info, query: {'current_workspace_id' => ws_id})
            rescue EntityNotFound
              # dropboxes cannot be created on the fly
              Aspera.assert_values(entity_type, 'contacts', type: Error){"No such shared inbox in workspace #{ws_id}"}
              # unknown user: create it as external user
              full_recipient_info = create('contacts', {
                'current_workspace_id' => ws_id,
                'email'                => short_recipient_info
              }.merge(new_user_option))
            end
            short_recipient_info = if entity_type.eql?('dropboxes')
              {'id' => full_recipient_info['id'], 'type' => 'dropbox'}
            else
              {'id' => full_recipient_info['source_id'], 'type' => full_recipient_info['source_type']}
            end
          else Aspera.error_unexpected_value(short_recipient_info.class.name){"#{rcpt_lst_field} item must be a String (email, shared inbox) or Hash (id,type)"}
          end
          # add original or resolved recipient info
          resolved_list.push(short_recipient_info)
        end
        # replace with resolved elements
        package_data[rcpt_lst_field] = resolved_list
        return
      end

      # CLI allows simplified format for metadata: transform if necessary for API
      def update_package_metadata_for_api(pkg_data)
        case pkg_data['metadata']
        when Array, NilClass # no action
        when Hash
          api_meta = pkg_data['metadata'].map do |k, v|
            {
              # 'input_type' => 'single-dropdown',
              'name'   => k,
              'values' => v.is_a?(Array) ? v : [v]
            }
          end
          pkg_data['metadata'] = api_meta
        else Aspera.error_unexpected_value(pkg_meta.class)
        end
        return
      end

      # create a package
      # @param package_data [Hash] package creation (with extensions...)
      # @param validate_meta [TrueClass,FalseClass] true to validate parameters locally
      # @param new_user_option [Hash,NilClass] options if an unknown user is specified
      # @return transfer spec, node api and package information
      def create_package_simple(package_data, validate_meta, new_user_option)
        update_package_metadata_for_api(package_data)
        # list of files to include in package, optional
        # package_data['file_names']||=[..list of filenames to transfer...]

        # lookup users
        resolve_package_recipients(package_data, 'recipients', new_user_option)
        resolve_package_recipients(package_data, 'bcc_recipients', new_user_option)

        validate_metadata(package_data) if validate_meta

        # tell AoC what to expect in package: 1 transfer (can also be done after transfer)
        # TODO: if multi session was used we should probably tell
        # also, currently no "multi-source" , i.e. only from client-side files, unless "node" agent is used
        # `single_source` is required to allow web UI to ask for CSEAR password on download, see API doc
        package_data.merge!({
          'single_source'      => true,
          'sent'               => true,
          'transfers_expected' => 1
        })

        #  create a new package container
        created_package = create('packages', package_data)

        package_node_api = node_api_from(
          node_id: created_package['node_id'],
          workspace_id: created_package['workspace_id'],
          package_info: created_package
        )

        return {
          spec: package_node_api.transfer_spec_gen4(created_package['contents_file_id'], Transfer::Spec::DIRECTION_SEND),
          node: package_node_api,
          info: created_package
        }
      end

      # Add transfer spec
      # callback in Node (transfer_spec_gen4)
      def add_ts_tags(transfer_spec:, app_info:)
        # translate transfer direction to upload/download
        transfer_type = Transfer::Spec.direction_to_transfer_type(transfer_spec['direction'])
        # Analytics tags
        ################
        transfer_spec.deep_merge!({
          'tags' => {
            Transfer::Spec::TAG_RESERVED => {
              'app'      => app_info[:app],
              'usage_id' => "aspera.files.workspace.#{app_info[:workspace_id]}", # activity tracking
              'files'    => {
                'node_id'               => app_info[:node_info]['id'],
                'files_transfer_action' => "#{transfer_type}_#{app_info[:app].gsub(/s$/, '')}",
                'workspace_name'        => app_info[:workspace_name], # activity tracking
                'workspace_id'          => app_info[:workspace_id]
              }
            }
          }
        })
        # Console cookie
        ################
        # we are sure that fields are not nil
        cookie_elements = [app_info[:app], current_user_info['name'] || 'public link', current_user_info['email'] || 'none'].map{ |e| Base64.strict_encode64(e)}
        cookie_elements.unshift(COOKIE_PREFIX_CONSOLE_AOC)
        transfer_spec['cookie'] = cookie_elements.join(':')
        # Application tags
        ##################
        case app_info[:app]
        when FILES_APP
          file_id = transfer_spec['tags'][Transfer::Spec::TAG_RESERVED]['node']['file_id']
          transfer_spec.deep_merge!({
            'tags' => {
              Transfer::Spec::TAG_RESERVED => {
                'files' => {
                  'parentCwd' => "#{app_info[:node_info]['id']}:#{file_id}"
                }
              }
            }
          }) unless transfer_spec.key?('remote_access_key')
        when PACKAGES_APP
          transfer_spec.deep_merge!({
            'tags' => {
              Transfer::Spec::TAG_RESERVED => {
                'files' => {
                  'package_id'        => app_info[:package_id],
                  'package_name'      => app_info[:package_name],
                  'package_operation' => transfer_type
                }
              }
            }
          })
        end
      end

      # Callback from Plugins::Node
      # add application specific tags to permissions creation
      # @param perm_data [Hash] parameters for creating permissions
      # @param app_info [Hash] application information
      def permissions_set_create_params(perm_data:, app_info:)
        defaults = {
          'tags' => {
            Transfer::Spec::TAG_RESERVED => {
              'files' => {
                'workspace' => {
                  'id'                => app_info[:workspace_id],
                  'workspace_name'    => app_info[:workspace_name],
                  'user_name'         => current_user_info['name'],
                  'shared_by_user_id' => current_user_info['id'],
                  'shared_by_name'    => current_user_info['name'],
                  'shared_by_email'   => current_user_info['email'],
                  'access_key'        => app_info[:node_info]['access_key'],
                  'node'              => app_info[:node_info]['name']
                }
              }
            }
          }
        }
        perm_data.deep_merge!(defaults)
        tag_workspace = perm_data['tags'][Transfer::Spec::TAG_RESERVED]['files']['workspace']
        shared_with = perm_data.delete('with')
        case shared_with
        when NilClass
        when ''
          # workspace shared folder
          perm_data.merge!(self.class.workspace_access(app_info[:workspace_id]))
          tag_workspace['shared_with_name'] = perm_data['access_id']
        else
          entity_info = lookup_by_name('contacts', shared_with, query: {'current_workspace_id' => app_info[:workspace_id]})
          perm_data['access_type'] = entity_info['source_type']
          perm_data['access_id'] = entity_info['source_id']
          tag_workspace['shared_with_name'] = entity_info['email'] # TODO: check that ???
        end
        if perm_data.key?('as')
          tag_workspace['share_as'] = perm_data['as']
          perm_data.delete('as')
        end
        # optional
        app_info[:opt_link_name] = perm_data.delete('link_name')
      end

      # Callback from Plugins::Node
      # send shared folder event to AoC
      # @param event_data [Hash] response from permission creation
      # @param app_info [Hash] hash with app info
      # @param types [Array] event types
      def permissions_send_event(event_data:, app_info:, types: PERMISSIONS_CREATED)
        Aspera.assert_type(types, Array)
        Aspera.assert(!types.empty?)
        event_creation = {
          'types'        => types,
          'node_id'      => app_info[:node_info]['id'],
          'workspace_id' => app_info[:workspace_id],
          'data'         => event_data
        }
        # (optional). The name of the folder to be displayed to the destination user.
        # Use it if its value is different from the "share_as" field.
        event_creation['link_name'] = app_info[:opt_link_name] unless app_info[:opt_link_name].nil?
        create('events', event_creation)
      end
    end
  end
end
