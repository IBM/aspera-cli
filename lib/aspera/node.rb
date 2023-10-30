# frozen_string_literal: true

require 'aspera/fasp/transfer_spec'
require 'aspera/rest'
require 'aspera/oauth'
require 'aspera/log'
require 'aspera/environment'
require 'zlib'
require 'base64'

module Aspera
  # Provides additional functions using node API with gen4 extensions (access keys)
  class Node < Aspera::Rest
    # permissions
    ACCESS_LEVELS = %w[delete list mkdir preview read rename write].freeze
    # prefix for ruby code for filter
    MATCH_EXEC_PREFIX = 'exec:'
    MATCH_TYPES = [String, Proc, NilClass].freeze
    HEADER_X_ASPERA_ACCESS_KEY = 'X-Aspera-AccessKey'
    PATH_SEPARATOR = '/'
    TS_FIELDS_TO_COPY = %w[remote_host remote_user ssh_port fasp_port wss_enabled wss_port].freeze
    SCOPE_USER = 'user:all'
    SCOPE_ADMIN = 'admin:all'
    SCOPE_PREFIX = 'node.'
    SCOPE_SEPARATOR = ':'
    SIGNATURE_DELIMITER = '==SIGNATURE=='

    # register node special token decoder
    Oauth.register_decoder(lambda{|token|Node.decode_bearer_token(token)})

    # class instance variable, access with accessors on class
    @use_standard_ports = true

    class << self
      attr_accessor :use_standard_ports

      # For access keys: provide expression to match entry in folder
      def file_matcher(match_expression)
        case match_expression
        when Proc then return match_expression
        when String
          if match_expression.start_with?(MATCH_EXEC_PREFIX)
            code = "->(f){#{match_expression[MATCH_EXEC_PREFIX.length..-1]}}"
            Log.log.warn{"Use of prefix #{MATCH_EXEC_PREFIX} is deprecated (4.15), instead use: @ruby:'#{code}'"}
            return Environment.secure_eval(code)
          end
          return lambda{|f|File.fnmatch(match_expression, f['name'], File::FNM_DOTMATCH)}
        when NilClass then return ->(_){true}
        else raise Cli::CliBadArgument, "Invalid match expression type: #{match_expression.class}"
        end
      end

      def file_matcher_from_argument(options)
        return file_matcher(options.get_next_argument('filter', type: MATCH_TYPES, mandatory: false))
      end

      # node API scopes
      def token_scope(access_key, scope)
        return [SCOPE_PREFIX, access_key, SCOPE_SEPARATOR, scope].join('')
      end

      def decode_scope(scope)
        items = scope.split(SCOPE_SEPARATOR, 2)
        raise "invalid scope: #{scope}" unless items.length.eql?(2)
        raise "invalid scope: #{scope}" unless items[0].start_with?(SCOPE_PREFIX)
        return {access_key: items[0][SCOPE_PREFIX.length..-1], scope: items[1]}
      end

      # Create an Aspera Node bearer token
      # @param payload [String] JSON payload to be included in the token
      # @param private_key [OpenSSL::PKey::RSA] Private key to sign the token
      def bearer_token(access_key:, scope: SCOPE_USER, payload:, private_key:, expiration_sec: 3600)
        raise 'payload shall be Hash' unless payload.is_a?(Hash)
        raise 'missing user_id' unless payload.key?('user_id')
        raise 'user_id must be a String' unless payload['user_id'].is_a?(String)
        raise 'user_id must not be empty' if payload['user_id'].empty?
        raise 'private_key shall be OpenSSL::PKey::RSA' unless private_key.is_a?(OpenSSL::PKey::RSA)
        payload['scope'] ||= token_scope(access_key, scope)
        payload['auth_type'] ||= 'access_key'
        payload['expires_at'] ||= (Time.now + expiration_sec).utc.strftime('%FT%TZ')
        payload_json = JSON.generate(payload)
        return Base64.strict_encode64(Zlib::Deflate.deflate([
          payload_json,
          SIGNATURE_DELIMITER,
          Base64.strict_encode64(private_key.sign(OpenSSL::Digest.new('sha512'), payload_json)).scan(/.{1,60}/).join("\n"),
          ''
        ].join("\n")))
      end

      def decode_bearer_token(token)
        return JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition(SIGNATURE_DELIMITER).first)
      end

      def bearer_headers(bearer_auth, access_key: nil)
        # if username is not provided, use the access key from the token
        if access_key.nil?
          access_key = Aspera::Node.decode_scope(Aspera::Node.decode_bearer_token(Oauth.bearer_extract(bearer_auth))['scope'])[:access_key]
          raise "internal error #{access_key}" if access_key.nil?
        end
        return {
          Aspera::Node::HEADER_X_ASPERA_ACCESS_KEY => access_key,
          'Authorization'                          => bearer_auth
        }
      end
    end

    # fields in @app_info
    REQUIRED_APP_INFO_FIELDS = %i[api app node_info workspace_id workspace_name].freeze
    # methods of @app_info[:api]
    REQUIRED_APP_API_METHODS = %i[node_api_from add_ts_tags].freeze
    private_constant :REQUIRED_APP_INFO_FIELDS, :REQUIRED_APP_API_METHODS

    attr_reader :app_info

    # @param params [Hash] Rest parameters
    # @param app_info [Hash,NilClass] special processing for AoC
    def initialize(params:, app_info: nil, add_tspec: nil)
      super(params)
      @app_info = app_info
      # this is added to transfer spec, for instance to add tags (COS)
      @add_tspec = add_tspec
      if !@app_info.nil?
        REQUIRED_APP_INFO_FIELDS.each do |field|
          raise "INTERNAL ERROR: app_info lacks field #{field}" unless @app_info.key?(field)
        end
        REQUIRED_APP_API_METHODS.each do |method|
          raise "INTERNAL ERROR: #{@app_info[:api].class} lacks method #{method}" unless @app_info[:api].respond_to?(method)
        end
      end
    end

    # update transfer spec with special additional tags
    def add_tspec_info(tspec)
      tspec.deep_merge!(@add_tspec) unless @add_tspec.nil?
      return tspec
    end

    # @returns [Aspera::Node] a Node or nil
    def node_id_to_node(node_id)
      if !@app_info.nil?
        return self if node_id.eql?(@app_info[:node_info]['id'])
        return @app_info[:api].node_api_from(
          node_id: node_id,
          workspace_id: @app_info[:workspace_id],
          workspace_name: @app_info[:workspace_name])
      end
      Log.log.warn{"cannot resolve link with node id #{node_id}"}
      return nil
    end

    # Recursively browse in a folder (with non-recursive method)
    # sub folders are processed if the processing method returns true
    # @param state [Object] state object sent to processing method
    # @param top_file_id [String] file id to start at (default = access key root file id)
    # @param top_file_path [String] path of top folder (default = /)
    # @param block [Proc] processing method, arguments: entry, path, state
    def process_folder_tree(state:, top_file_id:, top_file_path: '/', &block)
      raise 'INTERNAL ERROR: top_file_path not set' if top_file_path.nil?
      raise 'INTERNAL ERROR: Missing block' unless block
      # start at top folder
      folders_to_explore = [{id: top_file_id, path: top_file_path}]
      Log.dump(:folders_to_explore, folders_to_explore)
      until folders_to_explore.empty?
        current_item = folders_to_explore.shift
        Log.log.debug{"searching #{current_item[:path]}".bg_green}
        # get folder content
        folder_contents =
          begin
            read("files/#{current_item[:id]}/files")[:data]
          rescue StandardError => e
            Log.log.warn{"#{current_item[:path]}: #{e.class} #{e.message}"}
            []
          end
        Log.dump(:folder_contents, folder_contents)
        folder_contents.each do |entry|
          relative_path = File.join(current_item[:path], entry['name'])
          Log.log.debug{"process_folder_tree checking #{relative_path}"}
          # continue only if method returns true
          next unless yield(entry, relative_path, state)
          # entry type is file, folder or link
          case entry['type']
          when 'folder'
            folders_to_explore.push({id: entry['id'], path: relative_path})
          when 'link'
            node_id_to_node(entry['target_node_id'])&.process_folder_tree(
              state:         state,
              top_file_id:   entry['target_id'],
              top_file_path: relative_path,
              &block)
          end
        end
      end
    end # process_folder_tree

    # Navigate the path from given file id
    # @param top_file_id [String] id initial file id
    # @param path [String]  file path
    # @return [Hash] {.api,.file_id}
    def resolve_api_fid(top_file_id, path)
      raise 'file id shall be String' unless top_file_id.is_a?(String)
      process_last_link = path.end_with?(PATH_SEPARATOR)
      path_elements = path.split(PATH_SEPARATOR).reject(&:empty?)
      return {api: self, file_id: top_file_id} if path_elements.empty?
      resolve_state = {path: path_elements, result: nil}
      process_folder_tree(state: resolve_state, top_file_id: top_file_id) do |entry, _path, state|
        # this block is called recursively for each entry in folder
        # stop digging here if not in right path
        next false unless entry['name'].eql?(state[:path].first)
        # ok it matches, so we remove the match
        state[:path].shift
        case entry['type']
        when 'file'
          # file must be terminal
          raise "#{entry['name']} is a file, expecting folder to find: #{state[:path]}" unless state[:path].empty?
          # it's terminal, we found it
          state[:result] = {api: self, file_id: entry['id']}
          next false
        when 'folder'
          if state[:path].empty?
            # we found it
            state[:result] = {api: self, file_id: entry['id']}
            next false
          end
        when 'link'
          if state[:path].empty?
            if process_last_link
              # we found it
              other_node = node_id_to_node(entry['target_node_id'])
              raise 'cannot resolve link' if other_node.nil?
              state[:result] = {api: other_node, file_id: entry['target_id']}
            else
              # we found it but we do not process the link
              state[:result] = {api: self, file_id: entry['id']}
            end
            next false
          end
        else
          Log.log.warn{"Unknown element type: #{entry['type']}"}
        end
        # continue to dig folder
        next true
      end
      raise "entry not found: #{resolve_state[:path]}" if resolve_state[:result].nil?
      return resolve_state[:result]
    end

    def find_files(top_file_id, test_block)
      Log.log.debug{"find_files: file id=#{top_file_id}"}
      find_state = {found: [], test_block: test_block}
      process_folder_tree(state: find_state, top_file_id: top_file_id) do |entry, path, state|
        state[:found].push(entry.merge({'path' => path})) if state[:test_block].call(entry)
        # test all files deeply
        true
      end
      return find_state[:found]
    end

    def refreshed_transfer_token
      return oauth_token(force_refresh: true)
    end

    # Create transfer spec for gen4
    def transfer_spec_gen4(file_id, direction, ts_merge=nil)
      ak_name = nil
      ak_token = nil
      case params[:auth][:type]
      when :basic
        ak_name = params[:auth][:username]
        raise 'ERROR: no secret in node object' unless params[:auth][:password]
        ak_token = Rest.basic_creds(params[:auth][:username], params[:auth][:password])
      when :oauth2
        ak_name = params[:headers][HEADER_X_ASPERA_ACCESS_KEY]
        # TODO: token_generation_lambda = lambda{|do_refresh|oauth_token(force_refresh: do_refresh)}
        # get bearer token, possibly use cache
        ak_token = oauth_token(force_refresh: false)
      else raise "Unsupported auth method for node gen4: #{params[:auth][:type]}"
      end
      transfer_spec = {
        'direction' => direction,
        'token'     => ak_token,
        'tags'      => {
          Fasp::TransferSpec::TAG_RESERVED => {
            'node' => {
              'access_key' => ak_name,
              'file_id'    => file_id
            } # node
          } # aspera
        } # tags
      }
      # add specials tags (cos)
      add_tspec_info(transfer_spec)
      transfer_spec.deep_merge!(ts_merge) unless ts_merge.nil?
      # add application specific tags (AoC)
      app_info[:api].add_ts_tags(transfer_spec: transfer_spec, app_info: app_info) unless app_info.nil?
      # add remote host info
      if self.class.use_standard_ports
        # get default TCP/UDP ports and transfer user
        transfer_spec.merge!(Fasp::TransferSpec::AK_TSPEC_BASE)
        # by default: same address as node API
        transfer_spec['remote_host'] = URI.parse(params[:base_url]).host
        if !@app_info.nil? && !@app_info[:node_info]['transfer_url'].nil? && !@app_info[:node_info]['transfer_url'].empty?
          transfer_spec['remote_host'] = @app_info[:node_info]['transfer_url']
        end
      else
        # retrieve values from API (and keep a copy/cache)
        @std_t_spec_cache ||= create(
          'files/download_setup',
          {transfer_requests: [{ transfer_request: {paths: [{'source' => '/'}] } }] }
        )[:data]['transfer_specs'].first['transfer_spec']
        # copy some parts
        TS_FIELDS_TO_COPY.each {|i| transfer_spec[i] = @std_t_spec_cache[i] if @std_t_spec_cache.key?(i)}
      end
      Log.log.warn{"Expected transfer user: #{Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER}, but have #{transfer_spec['remote_user']}"} \
        unless transfer_spec['remote_user'].eql?(Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER)
      return transfer_spec
    end
  end
end
