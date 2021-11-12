require 'aspera/log'
require 'aspera/rest'
require 'aspera/hash_ext'
require 'aspera/data_repository'
require 'aspera/node'
require 'base64'

module Aspera
  class AoC < Rest
    private
    @@use_standard_ports = true

    API_V1='api/v1'

    PRODUCT_NAME='Aspera on Cloud'
    # Production domain of AoC
    PROD_DOMAIN='ibmaspera.com'
    # to avoid infinite loop in pub link redirection
    MAX_REDIRECT=10
    CLIENT_APPS=['aspera.global-cli-client','aspera.drive']
    DATA_REPO_INDEX_START = 4

    # path in URL of public links
    PATHS_PUBLIC_LINK=['/packages/public/receive','/packages/public/send','/files/public']
    JWT_AUDIENCE='https://api.asperafiles.com/api/v1/oauth2/token'
    OAUTH_API_SUBPATH='api/v1/oauth2'
    DEFAULT_TSPEC_INFO={
      'remote_user' => Node::ACCESS_KEY_TRANSFER_USER,
      'ssh_port'    => Node::SSH_PORT_DEFAULT,
      'fasp_port'   => Node::UDP_PORT_DEFAULT
    }

    private_constant :PRODUCT_NAME,:PROD_DOMAIN,:MAX_REDIRECT,:CLIENT_APPS,:PATHS_PUBLIC_LINK,:JWT_AUDIENCE,:OAUTH_API_SUBPATH,:DEFAULT_TSPEC_INFO

    public
    # various API scopes supported
    SCOPE_FILES_SELF='self'
    SCOPE_FILES_USER='user:all'
    SCOPE_FILES_ADMIN='admin:all'
    SCOPE_FILES_ADMIN_USER='admin-user:all'
    SCOPE_FILES_ADMIN_USER_USER=SCOPE_FILES_ADMIN_USER+'+'+SCOPE_FILES_USER
    SCOPE_NODE_USER='user:all'
    SCOPE_NODE_ADMIN='admin:all'
    PATH_SEPARATOR='/'
    FILES_APP='files'
    PACKAGES_APP='packages'

    def self.get_client_info(client_name=CLIENT_APPS.first)
      client_index=CLIENT_APPS.index(client_name)
      raise "no such pre-defined client: #{client_name}" if client_index.nil?
      # strings /Applications/Aspera\ Drive.app/Contents/MacOS/AsperaDrive|grep -E '.{100}==$'|base64 --decode
      return client_name,Base64.urlsafe_encode64(DataRepository.instance.get_bin(DATA_REPO_INDEX_START+client_index))
    end

    # @param url of AoC instance
    # @return organization id in url and AoC domain: ibmaspera.com, asperafiles.com or qa.asperafiles.com, etc...
    def self.parse_url(aoc_org_url)
      uri=URI.parse(aoc_org_url.gsub(/\/+$/,''))
      instance_fqdn=uri.host
      Log.log.debug("instance_fqdn=#{instance_fqdn}")
      raise "No host found in URL.Please check URL format: https://myorg.#{PROD_DOMAIN}" if instance_fqdn.nil?
      organization,instance_domain=instance_fqdn.split('.',2)
      Log.log.debug("instance_domain=#{instance_domain}")
      Log.log.debug("organization=#{organization}")
      raise "expecting a public FQDN for #{PRODUCT_NAME}" if instance_domain.nil?
      return organization,instance_domain
    end

    # base API url depends on domain, which could be "qa.xxx"
    def self.api_base_url(api_domain=PROD_DOMAIN)
      return "https://api.#{api_domain}"
    end

    def self.metering_api(entitlement_id,customer_id,api_domain=PROD_DOMAIN)
      return Rest.new({
        :base_url => "#{api_base_url(api_domain)}/metering/v1",
        :headers  => {'X-Aspera-Entitlement-Authorization' => Rest.basic_creds(entitlement_id,customer_id)}
      })
    end

    # node API scopes
    def self.node_scope(access_key,scope)
      return 'node.'+access_key+':'+scope
    end

    def self.set_use_default_ports(val)
      @@use_standard_ports=val
    end

    # check option "link"
    # if present try to get token value (resolve redirection if short links used)
    # then set options url/token/auth
    def self.resolve_pub_link(rest_opts,public_link_url)
      return if public_link_url.nil?
      # set to token if available after redirection
      url_param_token_pair=nil
      redirect_count=0
      loop do
        uri=URI.parse(public_link_url)
        if PATHS_PUBLIC_LINK.include?(uri.path)
          url_param_token_pair=URI::decode_www_form(uri.query).select{|e|e.first.eql?('token')}.first
          if url_param_token_pair.nil?
            raise ArgumentError,"link option must be URL with 'token' parameter"
          end
          # ok we get it !
          rest_opts[:org_url]='https://'+uri.host
          rest_opts[:auth][:grant]=:url_token
          rest_opts[:auth][:url_token]=url_param_token_pair.last
          return
        end
        Log.log.debug("no expected format: #{public_link_url}")
        raise "exceeded max redirection: #{MAX_REDIRECT}" if redirect_count > MAX_REDIRECT
        r = Net::HTTP.get_response(uri)
        if r.code.start_with?("3")
          public_link_url = r['location']
          raise "no location in redirection" if public_link_url.nil?
          Log.log.debug("redirect to: #{public_link_url}")
        else
          # not a redirection
          raise ArgumentError,'link option must be redirect or have token parameter'
        end
      end # loop

      raise RuntimeError,'too many redirections'
    end

    # @param :link,:url,:auth,:client_id,:client_secret,:scope,:redirect_uri,:private_key,:username,:subpath,:password (for pub link)
    def initialize(opt)
      # access key secrets are provided out of band to get node api access
      # key: access key
      # value: associated secret
      @key_chain=nil

      # init rest params
      aoc_rest_p={:auth=>{:type =>:oauth2}}
      # shortcut to auth section
      aoc_auth_p=aoc_rest_p[:auth]

      # sets [:org_url], [:auth][:grant], [:auth][:url_token]
      self.class.resolve_pub_link(aoc_rest_p,opt[:link])

      if aoc_rest_p.has_key?(:org_url)
        # Pub Link only: get org url from pub link
        opt[:url] = aoc_rest_p[:org_url]
        aoc_rest_p.delete(:org_url)
      else
        # else url is mandatory
        raise ArgumentError,"Missing mandatory option: url" if opt[:url].nil?
      end

      # get org name and domain from url
      organization,instance_domain=self.class.parse_url(opt[:url])
      # this is the base API url
      api_url_base=self.class.api_base_url(instance_domain)
      # API URL, including subpath (version ...)
      aoc_rest_p[:base_url]="#{api_url_base}/#{opt[:subpath]}"
      # base auth URL
      aoc_auth_p[:base_url] = "#{api_url_base}/#{OAUTH_API_SUBPATH}/#{organization}"
      aoc_auth_p[:client_id]=opt[:client_id]
      aoc_auth_p[:client_secret] = opt[:client_secret]

      if !aoc_auth_p.has_key?(:grant)
        raise ArgumentError,"Missing mandatory option: auth" if opt[:auth].nil?
        aoc_auth_p[:grant] = opt[:auth]
      end

      if aoc_auth_p[:client_id].nil?
        aoc_auth_p[:client_id],aoc_auth_p[:client_secret] = self.class.get_client_info()
      end

      raise ArgumentError,"Missing mandatory option: scope" if opt[:scope].nil?
      aoc_auth_p[:scope] = opt[:scope]

      # fill other auth parameters based on Oauth method
      case aoc_auth_p[:grant]
      when :web
        raise ArgumentError,"Missing mandatory option: redirect_uri" if opt[:redirect_uri].nil?
        aoc_auth_p[:redirect_uri] = opt[:redirect_uri]
      when :jwt
        # add jwt payload for global ids
        if CLIENT_APPS.include?(aoc_auth_p[:client_id])
          aoc_auth_p.merge!({:jwt_add=>{org: organization}})
        end
        raise ArgumentError,"Missing mandatory option: private_key" if opt[:private_key].nil?
        raise ArgumentError,"Missing mandatory option: username" if opt[:username].nil?
        private_key_PEM_string=opt[:private_key]
        aoc_auth_p[:jwt_audience]        = JWT_AUDIENCE
        aoc_auth_p[:jwt_subject]         = opt[:username]
        aoc_auth_p[:jwt_private_key_obj] = OpenSSL::PKey::RSA.new(private_key_PEM_string)
      when :url_token
        aoc_auth_p[:password]=opt[:password] unless opt[:password].nil?
        # nothing more
      else raise "ERROR: unsupported auth method: #{aoc_auth_p[:grant]}"
      end
      super(aoc_rest_p)
    end

    def key_chain=(keychain)
      raise "keychain already set" unless @key_chain.nil?
      @key_chain=keychain
      nil
    end

    # additional transfer spec (tags) for package information
    def self.package_tags(package_info,operation)
      return {'tags'=>{'aspera'=>{'files'=>{
        'package_id'        => package_info['id'],
        'package_name'      => package_info['name'],
        'package_operation' => operation
        }}}}
    end

    # add details to show in analytics
    def self.analytics_ts(app,direction,ws_id,ws_name)
      # translate transfer to operation
      operation=case direction
      when 'send';    'upload'
      when 'receive'; 'download'
      else raise "ERROR: unexpected value: #{direction}"
      end

      return {
        'tags'        => {
        'aspera'        => {
        'usage_id'        => "aspera.files.workspace.#{ws_id}", # activity tracking
        'files'           => {
        'files_transfer_action' => "#{operation}_#{app.gsub(/s$/,'')}",
        'workspace_name'        => ws_name,  # activity tracking
        'workspace_id'          => ws_id,
        }
        }
        }
      }
    end

    # build ts addon for IBM Aspera Console (cookie)
    def self.console_ts(app,user_name,user_email)
      elements=[app,user_name,user_email].map{|e|Base64.strict_encode64(e)}
      elements.unshift('aspera.aoc')
      #Log.dump('elem1'.bg_red,elements[1])
      return {
        'cookie'=>elements.join(':')
      }
    end

    # build "transfer info", 2 elements array with:
    # - transfer spec for aspera on cloud, based on node information and file id
    # - source and token regeneration method
    def tr_spec(app,direction,node_file,ts_add)
      # prepare the rest end point is used to generate the bearer token
      token_generation_method=lambda {|do_refresh|self.oauth_token(scope: self.class.node_scope(node_file[:node_info]['access_key'],SCOPE_NODE_USER), refresh: do_refresh)}
      # prepare transfer specification
      # note xfer_id and xfer_retry are set by the transfer agent itself
      transfer_spec={
        'direction'   => direction,
        'token'       => token_generation_method.call(false), # first time, use cache
        'tags'        => {
        'aspera'        => {
        'app'             => app,
        'files'           => {
        'node_id'           => node_file[:node_info]['id'],
        }, # files
        'node'            => {
        'access_key'        => node_file[:node_info]['access_key'],
        #'file_id'           => ts_add['source_root_id']
        'file_id'           => node_file[:file_id]
        } # node
        } # aspera
        } # tags
      }
      # add remote host info
      if @@use_standard_ports
        transfer_spec.merge!(DEFAULT_TSPEC_INFO)
        transfer_spec['remote_host']=node_file[:node_info]['host']
      else
        # retrieve values from API
        std_t_spec=get_node_api(node_file[:node_info],scope: SCOPE_NODE_USER).create('files/download_setup',{:transfer_requests => [ { :transfer_request => {:paths => [ {"source"=>'/'} ] } } ] } )[:data]['transfer_specs'].first['transfer_spec']
        ['remote_host','remote_user','ssh_port','fasp_port'].each {|i| transfer_spec[i]=std_t_spec[i]}
      end
      # add caller provided transfer spec
      transfer_spec.deep_merge!(ts_add)
      # additional information for transfer agent
      source_and_token_generator={
        :src              => :node_gen4,
        :regenerate_token => token_generation_method
      }
      return transfer_spec,source_and_token_generator
    end

    # returns a node API for access key
    # @param scope e.g. SCOPE_NODE_USER
    # no scope: requires secret
    # if secret provided beforehand: use it
    def get_node_api(node_info,options={})
      raise "INTERNAL ERROR: method parameters: options must ne hash" unless options.is_a?(Hash)
      options.keys.each {|k| raise "INTERNAL ERROR: not valid option: #{k}" unless [:scope,:use_secret].include?(k)}
      # get optional secret unless :use_secret is false (default is true)
      ak_secret=@key_chain.get_secret(node_info['access_key'],false) if !options.has_key?(:use_secret) or options[:use_secret]
      if ak_secret.nil? and !options.has_key?(:scope)
        raise "There must be at least one of: 'secret' or 'scope' for access key #{node_info['access_key']}"
      end
      node_rest_params={base_url: node_info['url']}
      # if secret is available
      if !ak_secret.nil?
        node_rest_params[:auth]={
          type:     :basic,
          username: node_info['access_key'],
          password: ak_secret
        }
      else
        # X-Aspera-AccessKey required for bearer token only
        node_rest_params[:headers]= {'X-Aspera-AccessKey'=>node_info['access_key']}
        node_rest_params[:auth]=self.params[:auth].clone
        node_rest_params[:auth][:scope]=self.class.node_scope(node_info['access_key'],options[:scope])
      end
      return Node.new(node_rest_params)
    end

    # check that parameter has necessary types
    # @return split values
    def check_get_node_file(node_file)
      raise "node_file must be Hash (got #{node_file.class})" unless node_file.is_a?(Hash)
      raise "node_file must have 2 keys: :file_id and :node_info" unless node_file.keys.sort.eql?([:file_id,:node_info])
      node_info=node_file[:node_info]
      file_id=node_file[:file_id]
      raise "node_info must be Hash  (got #{node_info.class}: #{node_info})" unless node_info.is_a?(Hash)
      raise 'node_info must have id' unless node_info.has_key?('id')
      raise 'file_id is empty' if file_id.to_s.empty?
      return node_info,file_id
    end

    # add entry to list if test block is success
    def process_find_files(entry,path)
      begin
        # add to result if match filter
        @find_state[:found].push(entry.merge({'path'=>path})) if @find_state[:test_block].call(entry)
        # process link
        if entry[:type].eql?('link')
          sub_node_info=self.read("nodes/#{entry['target_node_id']}")[:data]
          sub_opt={method: process_find_files, top_file_id: entry['target_id'], top_file_path: path}
          get_node_api(sub_node_info,scope: SCOPE_NODE_USER).crawl(self,sub_opt)
        end
      rescue => e
        Log.log.error("#{path}: #{e.message}")
      end
      # process all folders
      return true
    end

    def find_files( top_node_file, test_block )
      top_node_info,top_file_id=check_get_node_file(top_node_file)
      Log.log.debug("find_files: node_info=#{top_node_info}, fileid=#{top_file_id}")
      @find_state={found: [], test_block: test_block}
      get_node_api(top_node_info,scope: SCOPE_NODE_USER).crawl(self,{method: :process_find_files, top_file_id: top_file_id})
      result=@find_state[:found]
      @find_state=nil
      return result
    end

    def process_resolve_node_file(entry,path)
      # stop digging here if not in right path
      return false unless entry['name'].eql?(@resolve_state[:path].first)
      # ok it matches, so we remove the match
      @resolve_state[:path].shift
      case entry['type']
      when 'file'
        # file must be terminal
        raise "#{entry['name']} is a file, expecting folder to find: #{@resolve_state[:path]}" unless @resolve_state[:path].empty?
        @resolve_state[:result][:file_id]=entry['id']
      when 'link'
        @resolve_state[:result][:node_info]=self.read("nodes/#{entry['target_node_id']}")[:data]
        if @resolve_state[:path].empty?
          @resolve_state[:result][:file_id]=entry['target_id']
        else
          get_node_api(@resolve_state[:result][:node_info],scope: SCOPE_NODE_USER).crawl(self,{method: :process_resolve_node_file, top_file_id: entry['target_id']})
        end
      when 'folder'
        if @resolve_state[:path].empty?
          # found: store
          @resolve_state[:result][:file_id]=entry['id']
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
    def resolve_node_file( top_node_file, element_path_string )
      top_node_info,top_file_id=check_get_node_file(top_node_file)
      path_elements=element_path_string.split(PATH_SEPARATOR).select{|i| !i.empty?}
      result={node_info: top_node_info, file_id: nil}
      if path_elements.empty?
        result[:file_id]=top_file_id
      else
        @resolve_state={path: path_elements, result: result}
        get_node_api(top_node_info,scope: SCOPE_NODE_USER).crawl(self,{method: :process_resolve_node_file, top_file_id: top_file_id})
        not_found=@resolve_state[:path]
        @resolve_state=nil
        raise "entry not found: #{not_found}" if result[:file_id].nil?
      end
      return result
    end

  end # AoC
end # Aspera
