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
      subpath:     o.gparams[:path_token],
      headers:     {'Accept' => 'application/json'},
      json_params: o.sparams[:json],
      url_params:  o.sparams[:url].merge(scope: o.gparams[:scope]) # scope is here because it changes over time (node)
    })
  },
  lambda { |oauth|
    return [oauth.sparams.dig(:json, :url_token)]
  })

module Aspera
  class AoC < Rest
    PRODUCT_NAME = 'Aspera on Cloud'
    # Production domain of AoC
    PROD_DOMAIN = 'ibmaspera.com'
    # to avoid infinite loop in pub link redirection
    MAX_REDIRECT = 10
    # Well-known AoC globals client apps
    GLOBAL_CLIENT_APPS = %w[aspera.global-cli-client aspera.drive].freeze
    # index offset in data repository of client app
    DATA_REPO_INDEX_START = 4
    # cookie prefix so that console can decode identity
    COOKIE_PREFIX_CONSOLE_AOC = 'aspera.aoc'
    # path in URL of public links
    PUBLIC_LINK_PATHS = %w[/packages/public/receive /packages/public/send /files/public].freeze
    JWT_AUDIENCE = 'https://api.asperafiles.com/api/v1/oauth2/token'
    OAUTH_API_SUBPATH = 'api/v1/oauth2'
    # minimum fields for user info if retrieval fails
    USER_INFO_FIELDS_MIN = %w[name email id default_workspace_id organization_id].freeze

    private_constant :MAX_REDIRECT,
      :GLOBAL_CLIENT_APPS,
      :DATA_REPO_INDEX_START,
      :COOKIE_PREFIX_CONSOLE_AOC,
      :PUBLIC_LINK_PATHS,
      :JWT_AUDIENCE,
      :OAUTH_API_SUBPATH,
      :USER_INFO_FIELDS_MIN

    # various API scopes supported
    SCOPE_FILES_SELF = 'self'
    SCOPE_FILES_USER = 'user:all'
    SCOPE_FILES_ADMIN = 'admin:all'
    SCOPE_FILES_ADMIN_USER = 'admin-user:all'
    SCOPE_FILES_ADMIN_USER_USER = SCOPE_FILES_ADMIN_USER + '+' + SCOPE_FILES_USER
    SCOPE_NODE_USER = 'user:all'
    SCOPE_NODE_ADMIN = 'admin:all'
    FILES_APP = 'files'
    PACKAGES_APP = 'packages'
    API_V1 = 'api/v1'
    # error message when entity not found
    ENTITY_NOT_FOUND = 'No such'

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

      # check option "link"
      # if present try to get token value (resolve redirection if short links used)
      # then set options url/token/auth
      def resolve_pub_link(a_auth, a_opt)
        public_link_url = a_opt[:link]
        return if public_link_url.nil?
        raise 'do not use both link and url options' unless a_opt[:url].nil?
        redirect_count = 0
        while redirect_count <= MAX_REDIRECT
          uri = URI.parse(public_link_url)
          # detect if it's an expected format
          if PUBLIC_LINK_PATHS.include?(uri.path)
            url_param_token_pair = URI.decode_www_form(uri.query).find{|e|e.first.eql?('token')}
            raise ArgumentError, 'link option must be URL with "token" parameter' if url_param_token_pair.nil?
            # ok we get it !
            a_opt[:url] = 'https://' + uri.host
            a_auth[:crtype] = :aoc_pub_link
            a_auth[:aoc_pub_link] = {
              url:  {grant_type: 'url_token'}, # URL args
              json: {url_token: url_param_token_pair.last} # JSON body
            }
            # password protection of link
            a_auth[:aoc_pub_link][:json][:password] = a_opt[:password] unless a_opt[:password].nil?
            return # SUCCESS
          end
          Log.log.debug{"no expected format: #{public_link_url}"}
          r = Net::HTTP.get_response(uri)
          # not a redirection
          raise ArgumentError, 'link option must be redirect or have token parameter' unless r.code.start_with?('3')
          public_link_url = r['location']
          raise 'no location in redirection' if public_link_url.nil?
          Log.log.debug{"redirect to: #{public_link_url}"}
        end # loop
        raise "exceeded max redirection: #{MAX_REDIRECT}"
      end
    end # static methods

    # @param :link,:url,:auth,:client_id,:client_secret,:scope,:redirect_uri,:private_key,:passphrase,:username,:subpath,:password (for pub link)
    def initialize(opt)
      raise ArgumentError, 'Missing mandatory option: scope' if opt[:scope].nil?

      # access key secrets are provided out of band to get node api access
      # key: access key
      # value: associated secret
      @secret_finder = nil
      @user_info = nil

      # init rest params
      aoc_rest_p = {auth: {type: :oauth2}}
      # shortcut to auth section
      aoc_auth_p = aoc_rest_p[:auth]

      # sets opt[:url], aoc_rest_p[:auth][:crtype], [:auth][:aoc_pub_link] if there is a link
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
      if !aoc_auth_p.key?(:crtype)
        raise ArgumentError, 'Missing mandatory option: auth' if opt[:auth].nil?
        aoc_auth_p[:crtype] = opt[:auth]
      end

      if aoc_auth_p[:client_id].nil?
        aoc_auth_p[:client_id], aoc_auth_p[:client_secret] = self.class.get_client_info
      end

      # fill other auth parameters based on Oauth method
      case aoc_auth_p[:crtype]
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
      else raise "ERROR: unsupported auth method: #{aoc_auth_p[:crtype]}"
      end
      super(aoc_rest_p)
    end

    def url_token_data
      return nil unless params[:auth][:crtype].eql?(:aoc_pub_link)
      # TODO: can there be several in list ?
      return read('url_tokens')[:data].first
    end

    def secret_finder=(secret_finder)
      raise 'secret finder already set' unless @secret_finder.nil?
      raise 'secret finder must have lookup_secret' unless secret_finder.respond_to?(:lookup_secret)
      @secret_finder = secret_finder
    end

    # cached user information
    def user_info
      if @user_info.nil?
        # get our user's default information
        @user_info =
          begin
            read('self')[:data]
          rescue StandardError => e
            Log.log.debug{"ignoring error: #{e}"}
            {}
          end
        USER_INFO_FIELDS_MIN.each{|f|@user_info[f] = 'unknown' if @user_info[f].nil?}
      end
      return @user_info
    end

    # @returns [Aspera::Node] a node API for access key
    # @param node_info [Hash] with 'url' and 'access_key'
    # @param scope e.g. SCOPE_NODE_USER
    # no scope: requires secret
    # if secret provided beforehand: use it
    def node_id_to_api(node_id:, app_info:, scope: SCOPE_NODE_USER, use_secret: true)
      node_info = read("nodes/#{node_id}")[:data]
      raise 'internal error' unless node_info.is_a?(Hash) && node_info.key?('url') && node_info.key?('access_key')
      # get optional secret unless :use_secret is false
      ak_secret = @secret_finder&.lookup_secret(url: node_info['url'], username: node_info['access_key'], mandatory: false) if use_secret
      raise "There must be at least one of: 'secret' or 'scope' for access key #{node_info['access_key']}" if ak_secret.nil? && scope.nil?
      node_rest_params = {base_url: node_info['url']}
      # if secret is available
      if ak_secret.nil?
        # special header required for bearer token only
        node_rest_params[:headers] = {Aspera::Node::X_ASPERA_ACCESSKEY => node_info['access_key']}
        # OAuth bearer token
        node_rest_params[:auth] = params[:auth].clone
        node_rest_params[:auth][:scope] = self.class.node_scope(node_info['access_key'], scope)
      else
        node_rest_params[:auth] = {
          type:     :basic,
          username: node_info['access_key'],
          password: ak_secret
        }
      end
      return Node.new(params: node_rest_params, app_info: app_info.merge({node_info: node_info}))
    end

    # Add transferspec
    # callback in Aspera::Node (transfer_spec_gen4)
    def add_ts_tags(transfer_spec:, app_info:)
      # translate transfer direction to upload/download
      transfer_type =
        case transfer_spec['direction']
        when Fasp::TransferSpec::DIRECTION_SEND then    'upload'
        when Fasp::TransferSpec::DIRECTION_RECEIVE then 'download'
        else raise "ERROR: unexpected value: #{transfer_spec['direction']}"
        end
      # Analytics tags
      ################
      ws_info = app_info[:plugin].workspace_info
      transfer_spec.deep_merge!({
        'tags' => {
          'aspera' => {
            'usage_id' => "aspera.files.workspace.#{ws_info['id']}", # activity tracking
            'files'    => {
              'files_transfer_action' => "#{transfer_type}_#{app_info[:app].gsub(/s$/, '')}",
              'workspace_name'        => ws_info['name'], # activity tracking
              'workspace_id'          => ws_info['id']
            }
          }
        }
      })
      # Console cookie
      ################
      # we are sure that fields are not nil
      cookie_elements = [app_info[:app], user_info['name'], user_info['email']].map{|e|Base64.strict_encode64(e)}
      cookie_elements.unshift(COOKIE_PREFIX_CONSOLE_AOC)
      transfer_spec['cookie'] = cookie_elements.join(':')
      # Application tags
      ##################
      case app_info[:app]
      when FILES_APP
        file_id = transfer_spec['tags']['aspera']['node']['file_id']
        transfer_spec.deep_merge!({'tags' => {'aspera' => {'files' => {'parentCwd' => "#{app_info[:node_info]['id']}:#{file_id}"}}}}) \
          unless transfer_spec.key?('remote_access_key')
      when PACKAGES_APP
        transfer_spec.deep_merge!({
          'tags' => {
            'aspera' => {
              'files' => {
                'package_id'        => app_info[:package_info]['id'],
                'package_name'      => app_info[:package_info]['name'],
                'package_operation' => transfer_type
              }}}})
      end
      transfer_spec['tags']['aspera']['files']['node_id'] = app_info[:node_info]['id']
      transfer_spec['tags']['aspera']['app'] = app_info[:app]
    end

    # Query entity type by name and returns the id if a single entry only
    # @param entity_type path of entuty in API
    # @param entity_name name of searched entity
    # @param options additional search options
    def lookup_entity_by_name(entity_type, entity_name, options={})
      # returns entities whose name contains value (case insensitive)
      matching_items = read(entity_type, options.merge({'q' => CGI.escape(entity_name)}))[:data]
      case matching_items.length
      when 1 then return matching_items.first
      when 0 then raise %Q{#{ENTITY_NOT_FOUND} #{entity_type}: "#{entity_name}"}
      else
        # multiple case insensitive partial matches, try case insensitive full match
        # (anyway AoC does not allow creation of 2 entities with same case insensitive name)
        icase_matches = matching_items.select{|i|i['name'].casecmp?(entity_name)}
        case icase_matches.length
        when 1 then return icase_matches.first
        when 0 then raise %Q(#{entity_type}: multiple case insensitive partial match for: "#{entity_name}": #{matching_items.map{|i|i['name']}} but no case insensitive full match. Please be more specific or give exact name.) # rubocop:disable Layout/LineLength
        else raise "Two entities cannot have the same case insensitive name: #{icase_matches.map{|i|i['name']}}"
        end
      end
    end
    ID_AK_ADMIN = 'ASPERA_ACCESS_KEY_ADMIN'
    def permissions_create_params(create_param:, app_info:)
      # workspace shared folder:
      # access_id = "#{ID_AK_ADMIN}_WS_#{ app_info[:plugin].workspace_info['id']}"
      default_params = {
        # 'access_type'   => 'user', # mandatory: user or group
        # 'access_id'     => access_id, # id of user or group
        'tags' => {
          'aspera' => {
            'files' => {
              'workspace' => {
                'id'                => app_info[:plugin].workspace_info['id'],
                'workspace_name'    => app_info[:plugin].workspace_info['name'],
                'user_name'         => user_info['name'],
                'shared_by_user_id' => user_info['id'],
                'shared_by_name'    => user_info['name'],
                'shared_by_email'   => user_info['email'],
                # 'shared_with_name'  => access_id,
                'access_key'        => app_info[:node_info]['access_key'],
                'node'              => app_info[:node_info]['name']}}}}}
      create_param.deep_merge!(default_params)
      if create_param.key?('with')
        contact_info = lookup_entity_by_name(
          'contacts',
          create_param['with'],
          {'current_workspace_id' => app_info[:plugin].workspace_info['id'], 'context' => 'share_folder'})
        create_param.delete('with')
        create_param['access_type'] = contact_info['source_type']
        create_param['access_id'] = contact_info['source_id']
        create_param['tags']['aspera']['files']['workspace']['shared_with_name'] = contact_info['email']
      end
      # optionnal
      app_info[:opt_link_name] = create_param.delete('link_name')
    end

    def permissions_create_event(created_data:, app_info:)
      event_creation = {
        'types'        => ['permission.created'],
        'node_id'      => app_info[:node_info]['id'],
        'workspace_id' => app_info[:plugin].workspace_info['id'],
        'data'         => created_data # Response from previous step
      }
      # (optional). The name of the folder to be displayed to the destination user. Use it if its value is different from the "share_as" field.
      event_creation['link_name'] = app_info[:opt_link_name] unless app_info[:opt_link_name].nil?
      create('events', event_creation)
    end
  end # AoC
end # Aspera
