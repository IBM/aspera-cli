require 'asperalm/log'
require 'asperalm/rest'
require 'asperalm/hash_ext'
require 'base64'

module Asperalm
  class FilesApi < Rest

    public
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
        :base_url => base_url,
        :auth     => {
        :type         => :oauth2,
        :base_url     => "#{base_url}/oauth2/#{organization}",
        :jwt_audience => 'https://api.asperafiles.com/api/v1/oauth2/token'
        }}
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

    def direction_to_operation(direction)
      case direction
      when 'send';    return 'upload'
      when 'receive'; return 'download'
      else raise "ERROR: unexpected value: #{direction}"
      end
    end

    # build "transfer info"
    # contains:
    # - transfer spec for aspera on cloud, based on node information and file id
    # - source and token regeneration method
    def tr_spec(app,direction,node_info,file_id,ws_id,ts_add)
      # the rest end point is used to generate the bearer token
      token_generation_method=lambda {|do_refresh|self.oauth_token(scope: FilesApi.node_scope(node_info['access_key'],FilesApi::SCOPE_NODE_USER), refresh: do_refresh)}
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
        'usage_id'        => "aspera.files.workspace.#{ws_id}",
        'files'           => {
        'node_id'               => node_info['id'],
        'files_transfer_action' => "#{direction_to_operation(direction)}_#{app.gsub(/s$/,'')}",
        'workspace_id'          => ws_id,
        },
        'node'            => {
        'access_key'        => node_info['access_key'],
        'file_id'           => file_id }
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
          :base_url => node_info['url'],
          :auth     => {
          :type     => :basic,
          :username => node_info['access_key'],
          :password => ak_secret},
          :headers  => {'X-Aspera-AccessKey'=>node_info['access_key']
          }})
      end
      Log.log.warn("ignoring secret, using bearer token") if !ak_secret.nil?
      return Rest.new(self.params.deep_merge({
        :base_url => node_info['url'],
        :headers  => {'X-Aspera-AccessKey'=>node_info['access_key']},
        :auth     => {:scope=>FilesApi.node_scope(node_info['access_key'],node_scope)}}))
    end

    # check type, but returns split values
    def check_get_node_file(node_file)
      raise "node_file must be Hash (got #{node_file.class})" unless node_file.is_a?(Hash)
      raise "node_file must have 2 keys: :file_id and :node_info" unless node_file.keys.sort.eql?([:file_id,:node_info])
      node_info=node_file[:node_info]
      file_id=node_file[:file_id]
      raise "node_info must be Hash  (got #{node_info.class}: #{node_info})" unless node_info.is_a?(Hash)
      raise "node_info must have id" unless node_info.has_key?('id')
      raise "file_id is empty" if file_id.to_s.empty?
      return node_info,file_id
    end

    # @returns list of file paths that match given regex
    def find_files( top_node_file, element_regex )
      top_node_info,top_file_id=check_get_node_file(top_node_file)
      Log.log.debug("find_files: node_info=#{top_node_info}, fileid=#{top_file_id}, regex=#{element_regex}")
      result=[]
      top_node_api=get_files_node_api(top_node_info,FilesApi::SCOPE_NODE_USER)
      # initialize loop elements : list of folders to scan
      items_to_explore=[{:node_api=>top_node_api,:folder_id=>top_file_id,:path=>''}]
      # Note: top file id is necessarily a folder
      regex=/#{element_regex}/
      test_block=lambda{|filename|filename.match(regex)}

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
        # TODO: check iof this is a folder or file ?
        Log.dump(:folder_contents,folder_contents)
        folder_contents.each do |current_file_info|
          item_path=File.join(current_item[:path],current_file_info['name'])
          Log.log.debug("looking #{item_path}".bg_green)
          begin
            # process type of file
            case current_file_info['type']
            when 'file'
              Log.log.debug("testing : #{current_file_info['name']}")
              result.push(item_path) if test_block.call(current_file_info['name'])
            when 'link'
              new_node_api=get_files_node_api(self.read("nodes/#{current_file_info['target_node_id']}")[:data],FilesApi::SCOPE_NODE_USER)
              items_to_explore.push({:node_api=>new_node_api,:folder_id=>current_file_info["target_id"],:path=>item_path})
            when 'folder'
              items_to_explore.push({:node_api=>current_item[:node_api],:folder_id=>current_file_info["id"],:path=>item_path})
            else
              Log.log.warn("unknown element type: #{current_file_info['type']}")
            end
          rescue => e
            Log.log.warn("#{item_path}: #{e.message}")
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
        current_node_api=get_files_node_api(current_node_info,FilesApi::SCOPE_NODE_USER) if current_node_api.nil?
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
          current_file_id=current_file_info["id"]
          # a file shall be terminal
          if !items_to_explore.empty? then
            raise "#{current_item} is a file, expecting folder to find: #{items_to_explore}"
          end
        when 'link'
          current_node_info=self.read("nodes/#{current_file_info['target_node_id']}")[:data]
          current_file_id=current_file_info["target_id"]
          # need to switch node
          current_node_api=nil
        when 'folder'
          current_file_id=current_file_info["id"]
        else
          Log.log.warn("unknown element type: #{current_file_info['type']}")
        end
      end
      Log.log.info("resolve_node_file(#{element_path_string}): file_id=#{current_file_id},node_info=#{current_node_info}")
      return {node_info: current_node_info, file_id: current_file_id}
    end

  end # FilesApi
end # Asperalm
