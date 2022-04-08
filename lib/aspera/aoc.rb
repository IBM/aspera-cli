# frozen_string_literal: true

require 'aspera/log'
require 'aspera/rest'
require 'aspera/hash_ext'
require 'aspera/data_repository'
require 'aspera/fasp/transfer_spec'
require 'base64'

Aspera::Oauth.register_token_creator(:aoc_pub_link,lambda{|o|
  o.token_auth_api.call({
    operation:   'POST',
    subpath:     o.params[:path_token],
    headers:     {'Accept' => 'application/json'},
    json_params: o.params[:aoc_pub_link][:json],
    url_params:  o.params[:aoc_pub_link][:url].merge(scope: o.params[:scope]) # scope is here because it changes over time (node)
  })
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
    COOKIE_PREFIX = 'aspera.aoc'
    # path in URL of public links
    PUBLIC_LINK_PATHS = %w[/packages/public/receive /packages/public/send /files/public].freeze
    JWT_AUDIENCE = 'https://api.asperafiles.com/api/v1/oauth2/token'
    OAUTH_API_SUBPATH = 'api/v1/oauth2'
    # minimum fields for user info if retrieval fails
    USER_INFO_FIELDS_MIN = %w[name email id default_workspace_id organization_id].freeze

    private_constant :MAX_REDIRECT,:GLOBAL_CLIENT_APPS,:DATA_REPO_INDEX_START,:COOKIE_PREFIX,:PUBLIC_LINK_PATHS,:JWT_AUDIENCE,
      :OAUTH_API_SUBPATH,:USER_INFO_FIELDS_MIN

    # various API scopes supported
    SCOPE_FILES_SELF = 'self'
    SCOPE_FILES_USER = 'user:all'
    SCOPE_FILES_ADMIN = 'admin:all'
    SCOPE_FILES_ADMIN_USER = 'admin-user:all'
    SCOPE_FILES_ADMIN_USER_USER = SCOPE_FILES_ADMIN_USER + '+' + SCOPE_FILES_USER
    SCOPE_NODE_USER = 'user:all'
    SCOPE_NODE_ADMIN = 'admin:all'
    PATH_SEPARATOR = '/'
    FILES_APP = 'files'
    PACKAGES_APP = 'packages'
    API_V1 = 'api/v1'

    # class instance variable, access with accessors on class
    @use_standard_ports = true

    # class static methods
    class << self
      attr_accessor :use_standard_ports
      # strings /Applications/Aspera\ Drive.app/Contents/MacOS/AsperaDrive|grep -E '.{100}==$'|base64 --decode
      def get_client_info(client_name=GLOBAL_CLIENT_APPS.first)
        client_index = GLOBAL_CLIENT_APPS.index(client_name)
        raise "no such pre-defined client: #{client_name}" if client_index.nil?
        return client_name,Base64.urlsafe_encode64(DataRepository.instance.data(DATA_REPO_INDEX_START + client_index))
      end

      # @param url of AoC instance
      # @return organization id in url and AoC domain: ibmaspera.com, asperafiles.com or qa.asperafiles.com, etc...
      def parse_url(aoc_org_url)
        uri = URI.parse(aoc_org_url.gsub(/\/+$/,''))
        instance_fqdn = uri.host
        Log.log.debug("instance_fqdn=#{instance_fqdn}")
        raise "No host found in URL.Please check URL format: https://myorg.#{PROD_DOMAIN}" if instance_fqdn.nil?
        organization,instance_domain = instance_fqdn.split('.',2)
        Log.log.debug("instance_domain=#{instance_domain}")
        Log.log.debug("organization=#{organization}")
        raise "expecting a public FQDN for #{PRODUCT_NAME}" if instance_domain.nil?
        return organization,instance_domain
      end

      # base API url depends on domain, which could be "qa.xxx"
      def api_base_url(api_domain=PROD_DOMAIN)
        return "https://api.#{api_domain}"
      end

      def metering_api(entitlement_id,customer_id,api_domain=PROD_DOMAIN)
        return Rest.new({
          base_url: "#{api_base_url(api_domain)}/metering/v1",
          headers:  {'X-Aspera-Entitlement-Authorization' => Rest.basic_creds(entitlement_id,customer_id)}
        })
      end

      # node API scopes
      def node_scope(access_key,scope)
        return "node.#{access_key}:#{scope}"
      end

      # check option "link"
      # if present try to get token value (resolve redirection if short links used)
      # then set options url/token/auth
      def resolve_pub_link(a_auth,a_opt)
        public_link_url = a_opt[:link]
        return if public_link_url.nil?
        raise 'do not use both link and url options' unless a_opt[:url].nil?
        redirect_count = 0
        while redirect_count <= MAX_REDIRECT
          uri = URI.parse(public_link_url)
          # detect if it's an expected format
          if PUBLIC_LINK_PATHS.include?(uri.path)
            url_param_token_pair = URI.decode_www_form(uri.query).find{|e|e.first.eql?('token')}
            raise ArgumentError,'link option must be URL with "token" parameter' if url_param_token_pair.nil?
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
          Log.log.debug("no expected format: #{public_link_url}")
          r = Net::HTTP.get_response(uri)
          # not a redirection
          raise ArgumentError,'link option must be redirect or have token parameter' unless r.code.start_with?('3')
          public_link_url = r['location']
          raise 'no location in redirection' if public_link_url.nil?
          Log.log.debug("redirect to: #{public_link_url}")
        end # loop
        raise "exceeded max redirection: #{MAX_REDIRECT}"
      end

      # additional transfer spec (tags) for package information
      def package_tags(package_info,operation)
        return {'tags' => {'aspera' => {'files' => {
          'package_id'        => package_info['id'],
          'package_name'      => package_info['name'],
          'package_operation' => operation
        }}}}
      end

      # add details to show in analytics
      def analytics_ts(app,direction,ws_id,ws_name)
        # translate transfer to operation
        operation =
          case direction
          when Fasp::TransferSpec::DIRECTION_SEND then    'upload'
          when Fasp::TransferSpec::DIRECTION_RECEIVE then 'download'
          else raise "ERROR: unexpected value: #{direction}"
          end

        return {
          'tags' => {
            'aspera' => {
              'usage_id' => "aspera.files.workspace.#{ws_id}", # activity tracking
              'files'    => {
                'files_transfer_action' => "#{operation}_#{app.gsub(/s$/,'')}",
                'workspace_name'        => ws_name, # activity tracking
                'workspace_id'          => ws_id
              }
            }
          }
        }
      end
    end # static methods

    # @param :link,:url,:auth,:client_id,:client_secret,:scope,:redirect_uri,:private_key,:username,:subpath,:password (for pub link)
    def initialize(opt)
      raise ArgumentError,'Missing mandatory option: scope' if opt[:scope].nil?

      # access key secrets are provided out of band to get node api access
      # key: access key
      # value: associated secret
      @key_chain = nil
      @user_info = nil

      # init rest params
      aoc_rest_p = {auth: {type: :oauth2}}
      # shortcut to auth section
      aoc_auth_p = aoc_rest_p[:auth]

      # sets opt[:url], aoc_rest_p[:auth][:crtype], [:auth][:aoc_pub_link] if there is a link
      self.class.resolve_pub_link(aoc_auth_p,opt)

      # test here because link may set url
      raise ArgumentError,'Missing mandatory option: url' if opt[:url].nil?

      # get org name and domain from url
      organization,instance_domain = self.class.parse_url(opt[:url])
      # this is the base API url
      api_url_base = self.class.api_base_url(instance_domain)
      # API URL, including subpath (version ...)
      aoc_rest_p[:base_url] = "#{api_url_base}/#{opt[:subpath]}"
      # base auth URL
      aoc_auth_p[:base_url] = "#{api_url_base}/#{OAUTH_API_SUBPATH}/#{organization}"
      aoc_auth_p[:client_id] = opt[:client_id]
      aoc_auth_p[:client_secret] = opt[:client_secret]
      aoc_auth_p[:scope] = opt[:scope]

      # filled if pub link
      if !aoc_auth_p.has_key?(:crtype)
        raise ArgumentError,'Missing mandatory option: auth' if opt[:auth].nil?
        aoc_auth_p[:crtype] = opt[:auth]
      end

      if aoc_auth_p[:client_id].nil?
        aoc_auth_p[:client_id],aoc_auth_p[:client_secret] = self.class.get_client_info
      end

      # fill other auth parameters based on Oauth method
      case aoc_auth_p[:crtype]
      when :web
        raise ArgumentError,'Missing mandatory option: redirect_uri' if opt[:redirect_uri].nil?
        aoc_auth_p[:web] = {redirect_uri: opt[:redirect_uri]}
      when :jwt
        raise ArgumentError,'Missing mandatory option: private_key' if opt[:private_key].nil?
        raise ArgumentError,'Missing mandatory option: username' if opt[:username].nil?
        aoc_auth_p[:jwt] = {
          private_key_obj: OpenSSL::PKey::RSA.new(opt[:private_key]),
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
        aoc_auth_p[:auth] = {type: :basic, username: aoc_auth_p[:client_id],password: aoc_auth_p[:client_secret]}
      else raise "ERROR: unsupported auth method: #{aoc_auth_p[:crtype]}"
      end
      super(aoc_rest_p)
    end

    def url_token_data
      return nil unless params[:auth][:crtype].eql?(:aoc_pub_link)
      # TODO: can there be several in list ?
      return read('url_tokens')[:data].first
    end

    def key_chain=(keychain)
      raise 'keychain already set' unless @key_chain.nil?
      raise 'keychain must have get_secret' unless keychain.respond_to?(:get_secret)
      @key_chain = keychain
    end

    # cached user information
    def user_info
      if @user_info.nil?
        # get our user's default information
        @user_info =
          begin
            read('self')[:data]
          rescue StandardError => e
            Log.log.debug("ignoring error: #{e}")
            {}
          end
        USER_INFO_FIELDS_MIN.each{|f|@user_info[f] = 'unknown' if @user_info[f].nil?}
      end
      return @user_info
    end

    # build ts addon for IBM Aspera Console (cookie)
    def console_ts(app)
      # we are sure that fields are not nil
      elements = [app,user_info['name'],user_info['email']].map{|e|Base64.strict_encode64(e)}
      elements.unshift(COOKIE_PREFIX)
      return {'cookie' => elements.join(':')}
    end

    # build "transfer info", 2 elements array with:
    # - transfer spec for aspera on cloud, based on node information and file id
    # - source and token regeneration method
    def tr_spec(app,direction,node_file,ts_add)
      # get node api
      node_api = get_node_api(node_file[:node_info])
      # this lambda returns the bearer token for node, if
      token_generation_lambda = lambda{|do_refresh|node_api.oauth_token(force_refresh: do_refresh)}
      # prepare transfer specification
      # note xfer_id and xfer_retry are set by the transfer agent itself
      transfer_spec = {
        'direction' => direction,
        'token'     => token_generation_lambda.call(false), # first time, use cache
        'tags'      => {
          'aspera' => {
            'app'   => app,
            'files' => {
              'node_id' => node_file[:node_info]['id']
            }, # files
            'node'  => {
              'access_key' => node_file[:node_info]['access_key'],
              #'file_id'           => ts_add['source_root_id']
              'file_id'    => node_file[:file_id]
            } # node
          } # aspera
        } # tags
      }
      # add remote host info
      if self.class.use_standard_ports
        # get default TCP/UDP ports and transfer user
        transfer_spec.merge!(Fasp::TransferSpec::AK_TSPEC_BASE)
        # by default: same address as node API
        transfer_spec['remote_host'] = node_file[:node_info]['host']
        # 30 it's necessarily https scheme: webui does not allow anything else
        if node_file[:node_info]['transfer_url'].is_a?(String) && !node_file[:node_info]['transfer_url'].empty?
          transfer_spec['remote_host'] = URI.parse(node_file[:node_info]['transfer_url']).host
        end
      else
        # retrieve values from API
        std_t_spec = node_api.create('files/download_setup',
          {transfer_requests: [{ transfer_request: {paths: [{'source' => '/'}] } }] }
        )[:data]['transfer_specs'].first['transfer_spec']
        %w[remote_host remote_user ssh_port fasp_port].each {|i| transfer_spec[i] = std_t_spec[i]}
      end
      # add caller provided transfer spec
      transfer_spec.deep_merge!(ts_add)
      # additional information for transfer agent
      source_and_token_generator = {
        src:              :node_gen4,
        regenerate_token: token_generation_lambda
      }
      return transfer_spec,source_and_token_generator
    end

    # returns a node API for access key
    # @param node_info [Hash] with 'url' and 'access_key'
    # @param scope e.g. SCOPE_NODE_USER
    # no scope: requires secret
    # if secret provided beforehand: use it
    def get_node_api(node_info, scope: SCOPE_NODE_USER, use_secret: true)
      raise 'internal error' unless node_info.is_a?(Hash) && node_info.has_key?('url') && node_info.has_key?('access_key')
      # get optional secret unless :use_secret is false
      ak_secret = @key_chain.get_secret(url: node_info['url'], username: node_info['access_key'], mandatory: false) if use_secret && !@key_chain.nil?
      raise "There must be at least one of: 'secret' or 'scope' for access key #{node_info['access_key']}" if ak_secret.nil? && scope.nil?
      node_rest_params = {base_url: node_info['url']}
      # if secret is available
      if !ak_secret.nil?
        node_rest_params[:auth] = {
          type:     :basic,
          username: node_info['access_key'],
          password: ak_secret
        }
      else
        # X-Aspera-AccessKey required for bearer token only
        node_rest_params[:headers] = {'X-Aspera-AccessKey' => node_info['access_key']}
        node_rest_params[:auth] = params[:auth].clone
        node_rest_params[:auth][:scope] = self.class.node_scope(node_info['access_key'],scope)
      end
      return Node.new(node_rest_params)
    end

    # check that parameter has necessary types
    # @return split values
    def check_get_node_file(node_file)
      raise "node_file must be Hash (got #{node_file.class})" unless node_file.is_a?(Hash)
      raise 'node_file must have 2 keys: :file_id and :node_info' unless node_file.keys.sort.eql?(%i[file_id node_info])
      node_info = node_file[:node_info]
      file_id = node_file[:file_id]
      raise "node_info must be Hash  (got #{node_info.class}: #{node_info})" unless node_info.is_a?(Hash)
      raise 'node_info must have id' unless node_info.has_key?('id')
      raise 'file_id is empty' if file_id.to_s.empty?
      return node_info,file_id
    end

    # add entry to list if test block is success
    def process_find_files(entry,path)
      begin
        # add to result if match filter
        @find_state[:found].push(entry.merge({'path' => path})) if @find_state[:test_block].call(entry)
        # process link
        if entry[:type].eql?('link')
          sub_node_info = read("nodes/#{entry['target_node_id']}")[:data]
          sub_opt = {method: process_find_files, top_file_id: entry['target_id'], top_file_path: path}
          get_node_api(sub_node_info).crawl(self,sub_opt)
        end
      rescue StandardError => e
        Log.log.error("#{path}: #{e.message}")
      end
      # process all folders
      return true
    end

    def find_files(top_node_file, test_block)
      top_node_info,top_file_id = check_get_node_file(top_node_file)
      Log.log.debug("find_files: node_info=#{top_node_info}, fileid=#{top_file_id}")
      @find_state = {found: [], test_block: test_block}
      get_node_api(top_node_info).crawl(self,{method: :process_find_files, top_file_id: top_file_id})
      result = @find_state[:found]
      @find_state = nil
      return result
    end

    def process_resolve_node_file(entry,_path)
      # stop digging here if not in right path
      return false unless entry['name'].eql?(@resolve_state[:path].first)
      # ok it matches, so we remove the match
      @resolve_state[:path].shift
      case entry['type']
      when 'file'
        # file must be terminal
        raise "#{entry['name']} is a file, expecting folder to find: #{@resolve_state[:path]}" unless @resolve_state[:path].empty?
        @resolve_state[:result][:file_id] = entry['id']
      when 'link'
        @resolve_state[:result][:node_info] = read("nodes/#{entry['target_node_id']}")[:data]
        if @resolve_state[:path].empty?
          @resolve_state[:result][:file_id] = entry['target_id']
        else
          get_node_api(@resolve_state[:result][:node_info]).crawl(self,{method: :process_resolve_node_file, top_file_id: entry['target_id']})
        end
      when 'folder'
        if @resolve_state[:path].empty?
          # found: store
          @resolve_state[:result][:file_id] = entry['id']
          return false
        end
      else
        Log.log.warn("unknown element type: #{entry['type']}")
      end
      # continue to dig folder
      return true
    end

    # @return Array(node_info,file_id)   for the given path
    # @param top_node_file       Array    [root node,file id]
    # @param element_path_string String   path of element
    # supports links to secondary nodes
    def resolve_node_file(top_node_file, element_path_string)
      top_node_info,top_file_id = check_get_node_file(top_node_file)
      path_elements = element_path_string.split(PATH_SEPARATOR).reject(&:empty?)
      result = {node_info: top_node_info, file_id: nil}
      if path_elements.empty?
        result[:file_id] = top_file_id
      else
        @resolve_state = {path: path_elements, result: result}
        get_node_api(top_node_info).crawl(self,{method: :process_resolve_node_file, top_file_id: top_file_id})
        not_found = @resolve_state[:path]
        @resolve_state = nil
        raise "entry not found: #{not_found}" if result[:file_id].nil?
      end
      return result
    end

    # @param entity_type path of entuty in API
    # @param entity_name name of searched entity
    # @param options additional search options
    def lookup_entity_by_name(entity_type,entity_name,options={})
      # returns entities whose name contains value (case insensitive)
      matching_items = read(entity_type,options.merge({'q' => entity_name}))[:data]
      case matching_items.length
      when 1 then return matching_items.first
      when 0 then raise 'not found'
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
  end # AoC
end # Aspera
