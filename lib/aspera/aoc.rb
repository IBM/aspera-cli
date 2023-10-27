# frozen_string_literal: true

require 'aspera/log'
require 'aspera/rest'
require 'aspera/hash_ext'
require 'aspera/data_repository'
require 'aspera/fasp/transfer_spec'
require 'base64'
require 'cgi'

Aspera::Oauth.register_token_creator(
  :aoc_pub_link,
  lambda{|o|
    o.api.call({
      operation:   'POST',
      subpath:     o.generic_parameters[:path_token],
      headers:     {'Accept' => 'application/json'},
      json_params: o.specific_parameters[:json],
      url_params:  o.specific_parameters[:url].merge(scope: o.generic_parameters[:scope]) # scope is here because it changes over time (node)
    })
  },
  lambda { |oauth|
    return [oauth.specific_parameters.dig(:json, :url_token)]
  })

module Aspera
  class AoC < Aspera::Rest
    PRODUCT_NAME = 'Aspera on Cloud'
    # Production domain of AoC
    PROD_DOMAIN = 'ibmaspera.com'
    # to avoid infinite loop in pub link redirection
    MAX_PUB_LINK_REDIRECT = 10
    # Well-known AoC globals client apps
    GLOBAL_CLIENT_APPS = %w[aspera.global-cli-client aspera.drive].freeze
    # index offset in data repository of client app
    DATA_REPO_INDEX_START = 4
    # cookie prefix so that console can decode identity
    COOKIE_PREFIX_CONSOLE_AOC = 'aspera.aoc'
    # path in URL of public links
    PUBLIC_LINK_PATHS = %w[/packages/public/receive /packages/public/send /files/public /public/files /public/send].freeze
    JWT_AUDIENCE = 'https://api.asperafiles.com/api/v1/oauth2/token'
    OAUTH_API_SUBPATH = 'api/v1/oauth2'
    # minimum fields for user info if retrieval fails
    USER_INFO_FIELDS_MIN = %w[name email id default_workspace_id organization_id].freeze
    # types of events for shared folder creation
    # Node events: permission.created permission.modified permission.deleted
    PERMISSIONS_CREATED = ['permission.created'].freeze

    private_constant :MAX_PUB_LINK_REDIRECT,
      :GLOBAL_CLIENT_APPS,
      :DATA_REPO_INDEX_START,
      :COOKIE_PREFIX_CONSOLE_AOC,
      :PUBLIC_LINK_PATHS,
      :JWT_AUDIENCE,
      :OAUTH_API_SUBPATH,
      :USER_INFO_FIELDS_MIN,
      :PERMISSIONS_CREATED

    # various API scopes supported
    SCOPE_FILES_SELF = 'self'
    SCOPE_FILES_USER = 'user:all'
    SCOPE_FILES_ADMIN = 'admin:all'
    SCOPE_FILES_ADMIN_USER = 'admin-user:all'
    SCOPE_FILES_ADMIN_USER_USER = "#{SCOPE_FILES_ADMIN_USER}+#{SCOPE_FILES_USER}"
    SCOPE_NODE_USER = 'user:all'
    SCOPE_NODE_ADMIN = 'admin:all'
    FILES_APP = 'files'
    PACKAGES_APP = 'packages'
    API_V1 = 'api/v1'

    # class static methods
    class << self
      # strings /Applications/Aspera\ Drive.app/Contents/MacOS/AsperaDrive|grep -E '.{100}==$'|base64 --decode
      def get_client_info(client_name=GLOBAL_CLIENT_APPS.first)
        client_index = GLOBAL_CLIENT_APPS.index(client_name)
        raise "no such pre-defined client: #{client_name}" if client_index.nil?
        return client_name, Base64.urlsafe_encode64(DataRepository.instance.data(DATA_REPO_INDEX_START + client_index))
      end

      # @param url of AoC instance
      # @return organization id in url and AoC domain: ibmaspera.com, asperafiles.com or qa.asperafiles.com, etc...
      def parse_url(aoc_org_url)
        uri = URI.parse(aoc_org_url.gsub(%r{/+$}, ''))
        instance_fqdn = uri.host
        Log.log.debug{"instance_fqdn=#{instance_fqdn}"}
        raise "No host found in URL.Please check URL format: https://myorg.#{PROD_DOMAIN}" if instance_fqdn.nil?
        organization, instance_domain = instance_fqdn.split('.', 2)
        Log.log.debug{"instance_domain=#{instance_domain}"}
        Log.log.debug{"organization=#{organization}"}
        raise "expecting a public FQDN for #{PRODUCT_NAME}" if instance_domain.nil?
        return organization, instance_domain
      end

      # base API url depends on domain, which could be "qa.xxx"
      def api_base_url(organization: 'api', api_domain: PROD_DOMAIN)
        return "https://#{organization}.#{api_domain}"
      end

      def metering_api(entitlement_id, customer_id, api_domain=PROD_DOMAIN)
        return Rest.new({
          base_url: "#{api_base_url(api_domain: api_domain)}/metering/v1",
          headers:  {'X-Aspera-Entitlement-Authorization' => Rest.basic_creds(entitlement_id, customer_id)}
        })
      end

      # node API scopes
      def node_scope(access_key, scope)
        return "node.#{access_key}:#{scope}"
      end

      # @param url [String] URL of AoC public link
      # @return [Hash] information about public link, or nil if not a public link
      def public_link_info(url)
        pub_uri = URI.parse(url)
        return nil if pub_uri.query.nil?
        # detect if it's an expected format
        url_param_token_pair = URI.decode_www_form(pub_uri.query).find{|e|e.first.eql?('token')}
        return nil if url_param_token_pair.nil?
        Log.log.warn{"Unknown pub link path: #{pub_uri.path}"} unless PUBLIC_LINK_PATHS.include?(pub_uri.path)
        # ok we get it !
        return {
          url:   'https://' + pub_uri.host,
          token: url_param_token_pair.last
        }
      end

      # check option "link"
      # if present try to get token value (resolve redirection if short links used)
      # then set options url/token/auth
      def resolve_pub_link(a_auth, a_opt)
        public_link_url = a_opt[:link]
        return nil if public_link_url.nil?
        raise 'Do not use both link and url options' unless a_opt[:url].nil?
        result = Rest.new({base_url: public_link_url, redirect_max: MAX_PUB_LINK_REDIRECT}).read('')
        public_link_url = result[:http].uri.to_s
        pub_link_info = public_link_info(public_link_url)
        raise ArgumentError, 'link option must be redirect or have token parameter' if pub_link_info.nil?
        a_opt[:url] = pub_link_info[:url]
        a_auth[:grant_method] = :aoc_pub_link
        a_auth[:aoc_pub_link] = {
          url:  {grant_type: 'url_token'}, # URL args
          json: {url_token: pub_link_info[:token]} # JSON body
        }
        # password protection of link
        a_auth[:aoc_pub_link][:json][:password] = a_opt[:password] unless a_opt[:password].nil?
        # SUCCESS
        return nil
      end
    end # static methods

    # CLI options that are also options to initialize
    OPTIONS_NEW = %i[link url auth client_id client_secret scope redirect_uri private_key passphrase username password].freeze

    # @param any of OPTIONS_NEW + subpath
    def initialize(opt)
      raise ArgumentError, 'Missing mandatory option: scope' if opt[:scope].nil?

      # access key secrets are provided out of band to get node api access
      # key: access key
      # value: associated secret
      @secret_finder = nil
      @cache_user_info = nil
      @cache_url_token_info = nil

      # init rest params
      aoc_rest_p = {auth: {type: :oauth2}}
      # shortcut to auth section
      aoc_auth_p = aoc_rest_p[:auth]

      # sets opt[:url], aoc_rest_p[:auth][:grant_method], [:auth][:aoc_pub_link] if there is a link
      self.class.resolve_pub_link(aoc_auth_p, opt)

      # test here because link may set url
      raise ArgumentError, 'Missing mandatory option: url' if opt[:url].nil?

      # get org name and domain from url
      organization, instance_domain = self.class.parse_url(opt[:url])
      # this is the base API url
      api_url_base = self.class.api_base_url(api_domain: instance_domain)
      # API URL, including subpath (version ...)
      aoc_rest_p[:base_url] = "#{api_url_base}/#{opt[:subpath]}"
      # base auth URL
      aoc_auth_p[:base_url] = "#{api_url_base}/#{OAUTH_API_SUBPATH}/#{organization}"
      aoc_auth_p[:client_id] = opt[:client_id]
      aoc_auth_p[:client_secret] = opt[:client_secret]
      aoc_auth_p[:scope] = opt[:scope]

      # filled if pub link
      if !aoc_auth_p.key?(:grant_method)
        raise ArgumentError, 'Missing mandatory option: auth' if opt[:auth].nil?
        aoc_auth_p[:grant_method] = opt[:auth]
      end

      if aoc_auth_p[:client_id].nil?
        aoc_auth_p[:client_id], aoc_auth_p[:client_secret] = self.class.get_client_info
      end

      # fill other auth parameters based on Oauth method
      case aoc_auth_p[:grant_method]
      when :web
        raise ArgumentError, 'Missing mandatory option: redirect_uri' if opt[:redirect_uri].nil?
        aoc_auth_p[:web] = {redirect_uri: opt[:redirect_uri]}
      when :jwt
        raise ArgumentError, 'Missing mandatory option: private_key' if opt[:private_key].nil?
        raise ArgumentError, 'Missing mandatory option: username' if opt[:username].nil?
        aoc_auth_p[:jwt] = {
          private_key_obj: OpenSSL::PKey::RSA.new(opt[:private_key], opt[:passphrase]),
          payload:         {
            iss: aoc_auth_p[:client_id],  # issuer
            sub: opt[:username],          # subject
            aud: JWT_AUDIENCE
          }
        }
        # add jwt payload for global ids
        aoc_auth_p[:jwt][:payload][:org] = organization if GLOBAL_CLIENT_APPS.include?(aoc_auth_p[:client_id])
      when :aoc_pub_link
        # basic auth required for /token
        aoc_auth_p[:auth] = {type: :basic, username: aoc_auth_p[:client_id], password: aoc_auth_p[:client_secret]}
      else raise "ERROR: unsupported auth method: #{aoc_auth_p[:grant_method]}"
      end
      super(aoc_rest_p)
    end

    def url_token_data
      return nil unless params[:auth][:grant_method].eql?(:aoc_pub_link)
      return @cache_url_token_info unless @cache_url_token_info.nil?
      # TODO: can there be several in list ?
      @cache_url_token_info = read('url_tokens')[:data].first
      return @cache_url_token_info
    end

    def additional_persistence_ids
      return [current_user_info['id']] if url_token_data.nil?
      return [] # TODO : url_token_data['id'] ?
    end

    def secret_finder=(secret_finder)
      raise 'secret finder already set' unless @secret_finder.nil?
      raise 'secret finder must have lookup_secret' unless secret_finder.respond_to?(:lookup_secret)
      @secret_finder = secret_finder
    end

    # cached user information
    def current_user_info(exception: false)
      if @cache_user_info.nil?
        # get our user's default information
        @cache_user_info =
          begin
            read('self')[:data]
          rescue StandardError => e
            raise e if exception
            Log.log.debug{"ignoring error: #{e}"}
            {}
          end
        USER_INFO_FIELDS_MIN.each{|f|@cache_user_info[f] = 'unknown' if @cache_user_info[f].nil?}
      end
      return @cache_user_info
    end

    # @param node_id [String] identifier of node in AoC
    # @param workspace_id [String] workspace identifier
    # @param workspace_name [String] workspace name
    # @param scope e.g. SCOPE_NODE_USER, or nil (requires secret)
    # @param package_info [Hash] created package information
    # @returns [Aspera::Node] a node API for access key
    def node_api_from(node_id:, workspace_id: nil, workspace_name: nil, scope: SCOPE_NODE_USER, package_info: nil)
      raise 'invalid type for node_id' unless node_id.is_a?(String)
      node_info = read("nodes/#{node_id}")[:data]
      if workspace_name.nil? && !workspace_id.nil?
        workspace_name = read("workspaces/#{workspace_id}")[:data]['name']
      end
      app_info = {
        api:            self, # for callback
        app:            package_info.nil? ? FILES_APP : PACKAGES_APP,
        node_info:      node_info,
        workspace_id:   workspace_id,
        workspace_name: workspace_name
      }
      if PACKAGES_APP.eql?(app_info[:app])
        raise 'package info required' if package_info.nil?
        app_info[:package_id] = package_info['id']
        app_info[:package_name] = package_info['name']
      end
      node_rest_params = {base_url: node_info['url']}
      # if secret is available
      if scope.nil?
        node_rest_params[:auth] = {
          type:     :basic,
          username: node_info['access_key'],
          password: @secret_finder&.lookup_secret(url: node_info['url'], username: node_info['access_key'], mandatory: true)
        }
      else
        # OAuth bearer token
        node_rest_params[:auth] = params[:auth].clone
        node_rest_params[:auth][:scope] = self.class.node_scope(node_info['access_key'], scope)
        # special header required for bearer token only
        node_rest_params[:headers] = {Aspera::Node::HEADER_X_ASPERA_ACCESS_KEY => node_info['access_key']}
      end
      return Node.new(params: node_rest_params, app_info: app_info)
    end

    # Check metadata: remove when validation is done server side
    def validate_metadata(pkg_data)
      # validate only for shared inboxes
      return unless pkg_data['recipients'].is_a?(Array) &&
        pkg_data['recipients'].first.is_a?(Hash) &&
        pkg_data['recipients'].first.key?('type') &&
        pkg_data['recipients'].first['type'].eql?('dropbox')
      meta_schema = read("dropboxes/#{pkg_data['recipients'].first['id']}")[:data]['metadata_schema']
      if meta_schema.nil? || meta_schema.empty?
        Log.log.debug('no metadata in shared inbox')
        return
      end
      pkg_meta = pkg_data['metadata']
      raise "package requires metadata: #{meta_schema}" unless pkg_data.key?('metadata')
      raise 'metadata must be an Array' unless pkg_meta.is_a?(Array)
      Log.dump(:metadata, pkg_meta)
      pkg_meta.each do |field|
        raise 'metadata field must be Hash' unless field.is_a?(Hash)
        raise 'metadata field must have name' unless field.key?('name')
        raise 'metadata field must have values' unless field.key?('values')
        raise 'metadata values must be an Array' unless field['values'].is_a?(Array)
        raise "unknown metadata field: #{field['name']}" if meta_schema.select{|i|i['name'].eql?(field['name'])}.empty?
      end
      meta_schema.each do |field|
        provided = pkg_meta.select{|i|i['name'].eql?(field['name'])}
        raise "only one field with name #{field['name']} allowed" if provided.count > 1
        raise "missing mandatory field: #{field['name']}" if field['required'] && provided.empty?
      end
    end

    # Normalize package creation recipient lists as expected by AoC API
    # AoC expects {type: , id: }, but ascli allows providing either the native values or just a name
    # in that case, the name is resolved and replaced with {type: , id: }
    # @param package_data The whole package creation payload
    # @param recipient_list_field The field in structure, i.e. recipients or bcc_recipients
    # @return nil package_data is modified
    def resolve_package_recipients(package_data, ws_id, recipient_list_field, new_user_option)
      return unless package_data.key?(recipient_list_field)
      raise "#{recipient_list_field} must be an Array" unless package_data[recipient_list_field].is_a?(Array)
      new_user_option = {'package_contact' => true} if new_user_option.nil?
      raise 'new_user_option must be a Hash' unless new_user_option.is_a?(Hash)
      # list with resolved elements
      resolved_list = []
      package_data[recipient_list_field].each do |short_recipient_info|
        case short_recipient_info
        when Hash # native API information, check keys
          raise "#{recipient_list_field} element shall have fields: id and type" unless short_recipient_info.keys.sort.eql?(%w[id type])
        when String # CLI helper: need to resolve provided name to type/id
          # email: user, else dropbox
          entity_type = short_recipient_info.include?('@') ? 'contacts' : 'dropboxes'
          begin
            full_recipient_info = lookup_by_name(entity_type, short_recipient_info, {'current_workspace_id' => ws_id})
          rescue RuntimeError => e
            raise e unless e.message.start_with?(ENTITY_NOT_FOUND)
            # dropboxes cannot be created on the fly
            raise "No such shared inbox in workspace #{ws_id}" if entity_type.eql?('dropboxes')
            # unknown user: create it as external user
            full_recipient_info = create('contacts', {
              'current_workspace_id' => ws_id,
              'email'                => short_recipient_info
            }.merge(new_user_option))[:data]
          end
          short_recipient_info = if entity_type.eql?('dropboxes')
            {'id' => full_recipient_info['id'], 'type' => 'dropbox'}
          else
            {'id' => full_recipient_info['source_id'], 'type' => full_recipient_info['source_type']}
          end
        else # unexpected extended value, must be String or Hash
          raise "#{recipient_list_field} item must be a String (email, shared inbox) or Hash (id,type)"
        end # type of recipient info
        # add original or resolved recipient info
        resolved_list.push(short_recipient_info)
      end
      # replace with resolved elements
      package_data[recipient_list_field] = resolved_list
      return nil
    end

    # CLI allows simplified format for metadata: transform if necessary for API
    def update_package_metadata_for_api(pkg_data)
      case pkg_data['metadata']
      when Array, NilClass # no action
      when Hash
        api_meta = []
        pkg_data['metadata'].each do |k, v|
          api_meta.push({
            # 'input_type' => 'single-dropdown',
            'name'   => k,
            'values' => v.is_a?(Array) ? v : [v]
          })
        end
        pkg_data['metadata'] = api_meta
      else raise "metadata field if not of expected type: #{pkg_meta.class}"
      end
      return nil
    end

    # create a package
    # @param package_data [Hash] package creation (with extensions...)
    # @param validate_meta [TrueClass,FalseClass] true to validate parameters locally
    # @param new_user_option [Hash] options if an unknown user is specified
    # @return transfer spec, node api and package information
    def create_package_simple(package_data, validate_meta, new_user_option)
      update_package_metadata_for_api(package_data)
      # list of files to include in package, optional
      # package_data['file_names']||=[..list of filenames to transfer...]

      # lookup users
      resolve_package_recipients(package_data, package_data['workspace_id'], 'recipients', new_user_option)
      resolve_package_recipients(package_data, package_data['workspace_id'], 'bcc_recipients', new_user_option)

      validate_metadata(package_data) if validate_meta

      #  create a new package container
      created_package = create('packages', package_data)[:data]

      package_node_api = node_api_from(
        node_id: created_package['node_id'],
        workspace_id: created_package['workspace_id'],
        package_info: created_package)

      # tell AoC what to expect in package: 1 transfer (can also be done after transfer)
      # TODO: if multi session was used we should probably tell
      # also, currently no "multi-source" , i.e. only from client-side files, unless "node" agent is used
      update("packages/#{created_package['id']}", {'sent' => true, 'transfers_expected' => 1})[:data]

      return {
        spec: package_node_api.transfer_spec_gen4(created_package['contents_file_id'], Fasp::TransferSpec::DIRECTION_SEND),
        node: package_node_api,
        info: created_package
      }
    end

    # Add transferspec
    # callback in Aspera::Node (transfer_spec_gen4)
    def add_ts_tags(transfer_spec:, app_info:)
      # translate transfer direction to upload/download
      transfer_type = Fasp::TransferSpec.action(transfer_spec)
      # Analytics tags
      ################
      transfer_spec.deep_merge!({
        'tags' => {
          Fasp::TransferSpec::TAG_RESERVED => {
            'usage_id' => "aspera.files.workspace.#{app_info[:workspace_id]}", # activity tracking
            'files'    => {
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
      cookie_elements = [app_info[:app], current_user_info['name'], current_user_info['email']].map{|e|Base64.strict_encode64(e)}
      cookie_elements.unshift(COOKIE_PREFIX_CONSOLE_AOC)
      transfer_spec['cookie'] = cookie_elements.join(':')
      # Application tags
      ##################
      case app_info[:app]
      when FILES_APP
        file_id = transfer_spec['tags'][Fasp::TransferSpec::TAG_RESERVED]['node']['file_id']
        transfer_spec.deep_merge!({'tags' => {Fasp::TransferSpec::TAG_RESERVED => {'files' => {'parentCwd' => "#{app_info[:node_info]['id']}:#{file_id}"}}}}) \
          unless transfer_spec.key?('remote_access_key')
      when PACKAGES_APP
        transfer_spec.deep_merge!({
          'tags' => {
            Fasp::TransferSpec::TAG_RESERVED => {
              'files' => {
                'package_id'        => app_info[:package_id],
                'package_name'      => app_info[:package_name],
                'package_operation' => transfer_type
              }
            }
          }
        })
      end
      transfer_spec['tags'][Fasp::TransferSpec::TAG_RESERVED]['files']['node_id'] = app_info[:node_info]['id']
      transfer_spec['tags'][Fasp::TransferSpec::TAG_RESERVED]['app'] = app_info[:app]
    end

    ID_AK_ADMIN = 'ASPERA_ACCESS_KEY_ADMIN'
    # Callback from Plugins::Node
    # add application specific tags to permissions creation
    # @param create_param [Hash] parameters for creating permissions
    # @param app_info [Hash] application information
    def permissions_set_create_params(create_param:, app_info:)
      # workspace shared folder:
      # access_id = "#{ID_AK_ADMIN}_WS_#{app_info[:workspace_id]}"
      default_params = {
        # 'access_type'   => 'user', # mandatory: user or group
        # 'access_id'     => access_id, # id of user or group
        'tags' => {
          Fasp::TransferSpec::TAG_RESERVED => {
            'files' => {
              'workspace' => {
                'id'                => app_info[:workspace_id],
                'workspace_name'    => app_info[:workspace_name],
                'user_name'         => current_user_info['name'],
                'shared_by_user_id' => current_user_info['id'],
                'shared_by_name'    => current_user_info['name'],
                'shared_by_email'   => current_user_info['email'],
                # 'shared_with_name'  => access_id,
                'access_key'        => app_info[:node_info]['access_key'],
                'node'              => app_info[:node_info]['name']
              }
            }
          }
        }
      }
      create_param.deep_merge!(default_params)
      if create_param.key?('with')
        contact_info = lookup_by_name(
          'contacts',
          create_param['with'],
          {'current_workspace_id' => app_info[:workspace_id], 'context' => 'share_folder'})
        create_param.delete('with')
        create_param['access_type'] = contact_info['source_type']
        create_param['access_id'] = contact_info['source_id']
        create_param['tags'][Fasp::TransferSpec::TAG_RESERVED]['files']['workspace']['shared_with_name'] = contact_info['email']
      end
      # optional
      app_info[:opt_link_name] = create_param.delete('link_name')
    end

    # Callback from Plugins::Node
    # send shared folder event to AoC
    # @param created_data [Hash] response from permission creation
    # @param app_info [Hash] hash with app info
    # @param types [Array] event types
    def permissions_send_event(created_data:, app_info:, types: PERMISSIONS_CREATED)
      raise "INTERNAL: (assert) Invalid event types: #{types}" unless types.is_a?(Array) && !types.empty?
      event_creation = {
        'types'        => types,
        'node_id'      => app_info[:node_info]['id'],
        'workspace_id' => app_info[:workspace_id],
        'data'         => created_data
      }
      # (optional). The name of the folder to be displayed to the destination user.
      # Use it if its value is different from the "share_as" field.
      event_creation['link_name'] = app_info[:opt_link_name] unless app_info[:opt_link_name].nil?
      create('events', event_creation)
    end
  end # AoC
end # Aspera
