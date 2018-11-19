require 'asperalm/log'
require 'asperalm/rest'
require 'base64'

module Asperalm
  class FilesApi < Rest
    PRODUCT_NAME='Aspera on Cloud'
    PRODUCT_DOMAIN='ibmaspera.com'
    # various API scopes supported
    SCOPE_FILES_SELF='self'
    SCOPE_FILES_USER='user:all'
    SCOPE_FILES_ADMIN='admin:all'
    SCOPE_FILES_ADMIN_USER='admin-user:all'
    SCOPE_FILES_ADMIN_USER_USER=SCOPE_FILES_ADMIN_USER+'+'+SCOPE_FILES_USER
    SCOPE_NODE_USER='user:all'
    SCOPE_NODE_ADMIN='admin:all'

    PATH_PUBLIC_PACKAGE='/packages/public/receive'

    PATH_SEPARATOR='/'

    # some cool random string
    # strings /Applications/Aspera\ Drive.app/Contents/MacOS/AsperaDrive|grep -E '.{100}==$'|rev
    RANDOM_SEED='==QMGdXZsdkYMlDezZ3MNhDStYFWQNXNrZTOPRmYh10ZmJkN2EnZCFHbFxkRQtmNylTQOpHdtdUTPNFTxFGWFdFWFB1dr1iNK5WTadTLSFGWBlFTkVDdoxkYjx0MRp3ZlVlOlZXayRmLhJXZwNXY';
    def self.random
      Base64.strict_decode64(RANDOM_SEED.reverse).split(':')
    end

    def self.parse_url(aoc_org_url)
      uri=URI.parse(aoc_org_url.gsub(/\/+$/,''))
      instance_fqdn=uri.host
      Log.log.debug("instance_fqdn=#{instance_fqdn}")
      raise "No host found in URL.Please check URL format: https://myorg.#{PRODUCT_DOMAIN}" if instance_fqdn.nil?
      organization,instance_domain=instance_fqdn.split('.',2)
      Log.log.debug("instance_domain=#{instance_domain}")
      Log.log.debug("organization=#{organization}")
      raise "expecting a public FQDN for #{PRODUCT_NAME}" if instance_domain.nil?
      return organization,instance_domain
    end

    # get necessary fixed information to create JWT or call API
    # instance domain is: ibmaspera.com, asperafiles.com or qa.asperafiles.com, etc...
    def self.base_rest_params(aoc_org_url)
      organization,instance_domain=parse_url(aoc_org_url)
      base_url='https://api.'+instance_domain+'/api/v1'
      return {
        :base_url             => base_url,
        :auth_type            => :oauth2,
        :oauth_base_url       => "#{base_url}/oauth2/#{organization}",
        :oauth_jwt_audience   => 'https://api.asperafiles.com/api/v1/oauth2/token'
      }
    end

    # node API scopes
    def self.node_scope(access_key,scope)
      return 'node.'+access_key+':'+scope
    end

    def initialize(rest_params)
      super(rest_params)
      @secrets={}
    end

    attr_reader :secrets

    # build "transfer info"
    # contains:
    # - transfer spec for aspera on cloud, based on node information and file id
    # - source and token regeneration method
    def tr_spec(app,direction,node_info,file_id,ts_add)
      # the rest end point is used to generate the bearer token
      token_generation_method=lambda {|do_refresh|self.oauth_token(FilesApi.node_scope(node_info['access_key'],FilesApi::SCOPE_NODE_USER),do_refresh)}
      # note xfer_id and xfer_retry are set by the transfer agent itself
      return {
        'direction'   => direction,
        'remote_user' => 'xfer',
        'remote_host' => node_info['host'],
        'fasp_port'   => 33001, # TODO: always the case ?
        'ssh_port'    => 33001, # TODO: always the case ?
        'token'       => token_generation_method.call(false), # first time, use cache
        'tags'        => {
        'aspera'        => {
        'app'             => app,
        'files'           => { 'node_id' => node_info['id']},
        'node'            => { 'access_key' => node_info['access_key'], 'file_id' => file_id }
        }
        }}.deep_merge!(ts_add),{
        :src              => :node_gen4,
        :regenerate_token => token_generation_method
      }
    end

    # returns a node API for access key
    # no scope: requires secret
    # if secret present: use it
    def get_files_node_api(node_info,node_scope=nil)
      ak_secret=@secrets[node_info['id']]
      # if no scope, or secret provided on command line ...
      if node_scope.nil? or !ak_secret.nil?
        return Rest.new({
          :base_url       => node_info['url'],
          :auth_type      => :basic,
          :basic_username => node_info['access_key'],
          :basic_password => ak_secret,
          :headers        => {'X-Aspera-AccessKey'=>node_info['access_key']
          }})
      end
      Log.log.warn("ignoring secret, using bearer token") if !ak_secret.nil?
      return Rest.new(self.params.merge({
        :base_url    => node_info['url'],
        :oauth_scope => FilesApi.node_scope(node_info['access_key'],node_scope),
        :headers     => {'X-Aspera-AccessKey'=>node_info['access_key']}}))
    end

    # returns node information (returned by API) and file id, from a "/" based path
    # supports links to secondary nodes
    # input: Array(root node,file id), String path
    # output: Array(node_info,file_id)   for the given path
    def resolve_node_file( top_node_file, element_path_string='' )
      raise "top_node_file must be array" unless top_node_file.is_a?(Array)
      raise "top_node_file must have 2 elements" unless top_node_file.length.eql?(2)
      top_node_id=top_node_file.first
      top_file_id=top_node_file.last
      raise "top_node_id is nil" if top_node_id.to_s.empty?
      raise "top_file_id is nil" if top_file_id.to_s.empty?
      Log.log.debug("resolve_node_file: nodeid=#{top_node_id}, fileid=#{top_file_id}, path=#{element_path_string}")
      # initialize loop elements
      current_path_elements=element_path_string.split(PATH_SEPARATOR).select{|i| !i.empty?}
      current_node_info=self.read("nodes/#{top_node_id}")[:data]
      current_file_id = top_file_id
      current_file_info = nil

      while !current_path_elements.empty? do
        current_element_name = current_path_elements.shift
        Log.log.debug "searching #{current_element_name}".bg_green
        # get API if changed
        current_node_api=get_files_node_api(current_node_info,FilesApi::SCOPE_NODE_USER) if current_node_api.nil?
        # get folder content
        folder_contents = current_node_api.read("files/#{current_file_id}/files")
        Log.log.debug("folder_contents: #{folder_contents}")
        matching_folders = folder_contents[:data].select { |i| i['name'].eql?(current_element_name)}
        #Log.log.debug "matching_folders: #{matching_folders}"
        raise "no such folder: #{current_element_name} in #{folder_contents[:data].map { |i| i['name']}}" if matching_folders.empty?
        current_file_info = matching_folders.first
        # process type of file
        case current_file_info['type']
        when 'file'
          current_file_id=current_file_info["id"]
          # a file shall be terminal
          if !current_path_elements.empty? then
            raise "#{current_element_name} is a file, expecting folder to find: #{current_path_elements}"
          end
        when 'link'
          current_node_info=self.read("nodes/#{current_file_info['target_node_id']}")[:data]
          current_file_id=current_file_info["target_id"]
          current_node_api=nil
        when 'folder'
          current_file_id=current_file_info["id"]
        else
          Log.log.warn("unknown element type: #{current_file_info['type']}")
        end
      end
      Log.log.info("resolve_node_file(#{element_path_string}): file_id=#{current_file_id},node_info=#{current_node_info}")
      return current_node_info,current_file_id
    end

  end # FilesApi
end # Asperalm
