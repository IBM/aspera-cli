require 'asperalm/log'
require 'asperalm/rest'
require 'asperalm/hash_ext'
require 'base64'

module Asperalm
  class OnCloud < Rest
    private
    PRODUCT_NAME='Aspera on Cloud'
    # Production domain of AoC
    PROD_DOMAIN='ibmaspera.com'
    # to avoid infinite loop in pub link redirection
    MAX_REDIRECT=10
    DEFAULT_CLIENT='aspera.global-cli-client'
    # Random generator seed
    # strings /Applications/Aspera\ Drive.app/Contents/MacOS/AsperaDrive|grep -E '.{100}==$'|base64 --decode
    CLIENT_RANDOM={
      'aspera.drive' => '1FwelGbL9xsv3M8H-VXPs5k69OdbaMgfB66qfBqlELFPk6r9ANztmGMOSLqaXEWXEPwk-6JnMZ7-RaXAYLd5thLbcL3QzgeU',
      'aspera.global-cli-client' => 'bK_qpqFpP-OPEuRJ9mnmdw_ebLtpSqCnqhuAKfKdoLXC6OF2yLMgsfAMBmXg7XI_zplV4gBqNOvlJdgCxlP0Zjm4GsRsmprf'
    }
    # path in URL of public links
    PATHS_PUBLIC_LINK=['/packages/public/receive','/packages/public/send','/files/public']
    private_constant :PRODUCT_NAME,:PROD_DOMAIN,:MAX_REDIRECT,:DEFAULT_CLIENT,:CLIENT_RANDOM,:PATHS_PUBLIC_LINK

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

    def self.metering_api(entitlement_id,customer_id,api_domain=PROD_DOMAIN)
      return Rest.new({
        :base_url => "https://api.#{api_domain}/metering/v1",
        :headers  => {'X-Aspera-Entitlement-Authorization' => Rest.basic_creds(entitlement_id,customer_id)}
      })
    end

    # node API scopes
    def self.node_scope(access_key,scope)
      return 'node.'+access_key+':'+scope
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

    # @param :link,:url,:auth,:client_id,:client_secret,:scope,:redirect_uri,:private_key,:username,:subpath
    def initialize(opt)
      # access key secrets are provided out of band to get node api access
      # key: access key
      # value: associated secret
      @secrets={}

      # init rest params
      aoc_rest_p={:auth=>{:type =>:oauth2}}
      # shortcut to auth section
      aoc_auth_p=aoc_rest_p[:auth]

      # sets [:org_url], [:auth][:grant], [:auth][:url_token]
      self.class.resolve_pub_link(aoc_rest_p,opt[:link])

      # get org url from pub link or options
      if aoc_rest_p.has_key?(:org_url)
        opt[:url] = aoc_rest_p[:org_url]
        aoc_rest_p.delete(:org_url)
      else
        raise ArgumentError,"Missing mandatory option: url" if opt[:url].nil?
      end

      # set API and OAuth URLs
      organization,instance_domain=self.class.parse_url(opt[:url])
      aoc_rest_p[:base_url]="https://api.#{instance_domain}/#{opt[:subpath]}"
      aoc_auth_p[:base_url] = "#{aoc_rest_p[:base_url]}/oauth2/#{organization}"

      if !aoc_auth_p.has_key?(:grant)
        raise ArgumentError,"Missing mandatory option: auth" if opt[:auth].nil?
        aoc_auth_p[:grant] = opt[:auth]
      end

      aoc_auth_p[:client_id]     = opt[:client_id] || DEFAULT_CLIENT
      aoc_auth_p[:client_secret] = opt[:client_secret] || CLIENT_RANDOM[DEFAULT_CLIENT].reverse
      aoc_auth_p[:scope]         = opt[:scope]

      # fill other auth parameters based on Oauth method
      case aoc_auth_p[:grant]
      when :web
        raise ArgumentError,"Missing mandatory option: redirect_uri" if opt[:redirect_uri].nil?
        aoc_auth_p[:redirect_uri] = opt[:redirect_uri]
      when :jwt
        # add jwt payload for global ids
        if CLIENT_RANDOM.keys.include?(aoc_auth_p[:client_id])
          aoc_auth_p.merge!({:jwt_add=>{org: organization}})
        end
        raise ArgumentError,"Missing mandatory option: private_key" if opt[:private_key].nil?
        raise ArgumentError,"Missing mandatory option: username" if opt[:username].nil?
        private_key_PEM_string=opt[:private_key]
        aoc_auth_p[:jwt_audience]        = 'https://api.asperafiles.com/api/v1/oauth2/token'
        aoc_auth_p[:jwt_subject]         = opt[:username]
        aoc_auth_p[:jwt_private_key_obj] = OpenSSL::PKey::RSA.new(private_key_PEM_string)
      when :url_token
        # nothing more
      else raise "ERROR: unsupported auth method: #{aoc_auth_p[:grant]}"
      end
      super(aoc_rest_p)
    end

    def add_secrets(secrets)
      @secrets.merge!(secrets)
      Log.log.debug("now secrets:#{secrets}")
      nil
    end

    def has_secret(ak)
      Log.log.debug("has key:#{ak} -> #{@secrets.has_key?(ak)}")
      return @secrets.has_key?(ak)
    end

    # additional transfer spec (tags) for package information
    def self.package_tags(package_info,operation)
      return {'tags'=>{'aspera'=>{'files'=>{
        'package_id'        => package_info['id'],
        'package_name'      => package_info['name'],
        'package_operation' => operation
        }}}}
    end

    # get transfer connection parameters
    def self.tr_spec_remote_info(node_info)
      #TODO: add option to request those parameters by calling /upload_setup on node api
      return {
        'remote_user' => 'xfer',
        'remote_host' => node_info['host'],
        'fasp_port'   => 33001, # TODO: always the case ? or use upload_setup get get info ?
        'ssh_port'    => 33001, # TODO: always the case ?
      }
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
      transfer_spec.merge!(self.class.tr_spec_remote_info(node_file[:node_info]))
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
    # no scope: requires secret
    # if secret provided beforehand: use it
    def get_node_api(node_info,node_scope=nil)
      node_rest_params={
        :base_url => node_info['url'],
        :headers  => {'X-Aspera-AccessKey'=>node_info['access_key']},
      }
      ak_secret=@secrets[node_info['access_key']]
      if ak_secret.nil? and node_scope.nil?
        raise 'There must be at least one of: secret, node scope'
      end
      # if secret provided on command line or if there is no scope
      if !ak_secret.nil? or node_scope.nil?
        node_rest_params[:auth]={
          :type     => :basic,
          :username => node_info['access_key'],
          :password => ak_secret
        }
      else
        node_rest_params[:auth]=self.params[:auth].clone
        node_rest_params[:auth][:scope]=self.class.node_scope(node_info['access_key'],node_scope)
      end
      return Rest.new(node_rest_params)
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

    # returns node api and folder_id from soft link
    def read_asplnk(current_file_info)
      new_node_api=get_node_api(self.read("nodes/#{current_file_info['target_node_id']}")[:data],SCOPE_NODE_USER)
      return {:node_api=>new_node_api,:folder_id=>current_file_info['target_id']}
    end

    # @returns list of file paths that match given regex
    def find_files( top_node_file, test_block )
      top_node_info,top_file_id=check_get_node_file(top_node_file)
      Log.log.debug("find_files: node_info=#{top_node_info}, fileid=#{top_file_id}")
      result=[]
      top_node_api=get_node_api(top_node_info,SCOPE_NODE_USER)
      # initialize loop elements : list of folders to scan
      # Note: top file id is necessarily a folder
      items_to_explore=[{:node_api=>top_node_api,:folder_id=>top_file_id,:path=>''}]

      while !items_to_explore.empty? do
        current_item = items_to_explore.shift
        Log.log.debug("searching #{current_item[:path]}".bg_green)
        # get folder content
        begin
          folder_contents = current_item[:node_api].read("files/#{current_item[:folder_id]}/files")[:data]
        rescue => e
          Log.log.warn("#{current_item[:path]}: #{e.message}")
          folder_contents=[]
        end
        # TODO: check if this is a folder or file ?
        Log.dump(:folder_contents,folder_contents)
        folder_contents.each do |current_file_info|
          item_path=File.join(current_item[:path],current_file_info['name'])
          Log.log.debug("looking #{item_path}".bg_green)
          begin
            # does item match ?
            result.push(current_file_info.merge({'path'=>item_path})) if test_block.call(current_file_info)
            # does it need further processing ?
            case current_file_info['type']
            when 'file'
              Log.log.debug("testing : #{current_file_info['name']}")
            when 'folder'
              items_to_explore.push({:node_api=>current_item[:node_api],:folder_id=>current_file_info['id'],:path=>item_path})
            when 'link' # .*.asp-lnk
              items_to_explore.push(read_asplnk(current_file_info).merge({:path=>item_path}))
            else
              Log.log.error("unknown folder item type: #{current_file_info['type']}")
            end
          rescue => e
            Log.log.error("#{item_path}: #{e.message}")
          end
        end
      end
      return result
    end

    # @return node information (returned by API) and file id, from a "/" based path
    # supports links to secondary nodes
    # input: Array(root node,file id), String path
    # output: Array(node_info,file_id)   for the given path
    def resolve_node_file( top_node_file, element_path_string='' )
      Log.log.debug("resolve_node_file: top_node_file=#{top_node_file}, path=#{element_path_string}")
      # initialize loop invariants
      current_node_info,current_file_id=check_get_node_file(top_node_file)
      items_to_explore=element_path_string.split(PATH_SEPARATOR).select{|i| !i.empty?}

      while !items_to_explore.empty? do
        current_item = items_to_explore.shift
        Log.log.debug "searching #{current_item}".bg_green
        # get API if changed
        current_node_api=get_node_api(current_node_info,SCOPE_NODE_USER) if current_node_api.nil?
        # get folder content
        folder_contents = current_node_api.read("files/#{current_file_id}/files")
        Log.dump(:folder_contents,folder_contents)
        matching_folders = folder_contents[:data].select { |i| i['name'].eql?(current_item)}
        #Log.log.debug "matching_folders: #{matching_folders}"
        raise "no such folder: #{current_item} in #{folder_contents[:data].map { |i| i['name']}}" if matching_folders.empty?
        current_file_info = matching_folders.first
        # process type of file
        case current_file_info['type']
        when 'file'
          current_file_id=current_file_info['id']
          # a file shall be terminal
          if !items_to_explore.empty? then
            raise "#{current_item} is a file, expecting folder to find: #{items_to_explore}"
          end
        when 'link'
          current_node_info=self.read("nodes/#{current_file_info['target_node_id']}")[:data]
          current_file_id=current_file_info['target_id']
          # need to switch node
          current_node_api=nil
        when 'folder'
          current_file_id=current_file_info['id']
        else
          Log.log.warn("unknown element type: #{current_file_info['type']}")
        end
      end
      Log.log.info("resolve_node_file(#{element_path_string}): file_id=#{current_file_id},node_info=#{current_node_info}")
      return {node_info: current_node_info, file_id: current_file_id}
    end

  end # OnCloud
end # Asperalm
