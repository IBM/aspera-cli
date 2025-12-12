# frozen_string_literal: true

require 'aspera/transfer/spec'
require 'aspera/rest'
require 'aspera/oauth'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'zlib'
require 'base64'
require 'openssl'
require 'pathname'
require 'net/ssh/buffer'

module Aspera
  module Api
    # Provides additional functions using node API with gen4 extensions (access keys)
    class Node < Aspera::Rest
      # Separator between node.AK and user:all
      SCOPE_SEPARATOR = ':'
      SCOPE_NODE_PREFIX = 'node.'
      # Accepted types in `file_matcher`
      MATCH_TYPES = [String, Proc, Regexp, NilClass].freeze
      # Delimiter in decoded node token
      SIGNATURE_DELIMITER = '==SIGNATURE=='
      # Default validity when generating a bearer token "manually"
      BEARER_TOKEN_VALIDITY_DEFAULT = 86400
      # Fields in @app_info
      REQUIRED_APP_INFO_FIELDS = %i[api app node_info workspace_id workspace_name].freeze
      # Methods of @app_info[:api]
      REQUIRED_APP_API_METHODS = %i[node_api_from add_ts_tags].freeze
      private_constant :SCOPE_SEPARATOR, :SCOPE_NODE_PREFIX, :MATCH_TYPES,
        :SIGNATURE_DELIMITER, :BEARER_TOKEN_VALIDITY_DEFAULT,
        :REQUIRED_APP_INFO_FIELDS, :REQUIRED_APP_API_METHODS

      # Node API permissions
      ACCESS_LEVELS = %w[delete list mkdir preview read rename write].freeze
      # Special HTTP Headers
      HEADER_X_ASPERA_ACCESS_KEY = 'X-Aspera-AccessKey'
      HEADER_X_TOTAL_COUNT = 'X-Total-Count'
      HEADER_X_CACHE_CONTROL = 'X-Aspera-Cache-Control'
      HEADER_X_NEXT_ITER_TOKEN = 'X-Aspera-Next-Iteration-Token'
      # Node sub-scopes
      SCOPE_USER = 'user:all'
      SCOPE_ADMIN = 'admin:all'
      # / in cloud
      PATH_SEPARATOR = '/'

      # Register node special token decoder
      OAuth::Factory.instance.register_decoder(lambda{ |token| Node.decode_bearer_token(token)})

      # Class instance variable, access with accessors on class
      @use_standard_ports = true
      @use_node_cache = true

      class << self
        # Set to false to read transfer parameters from download_setup
        attr_accessor :use_standard_ports
        # Set to false to bypass cache in redis
        attr_accessor :use_node_cache
        attr_reader :use_dynamic_key

        # Adds cache control header, as globally specified to read request
        # Use like this: read(...,**cache_control)
        def cache_control
          headers = {'Accept' => Rest::MIME_JSON}
          headers[HEADER_X_CACHE_CONTROL] = 'no-cache' unless use_node_cache
          {headers: headers}
        end

        # Set private key to be used
        # @param pem_content [String] PEM encoded private key
        def use_dynamic_key=(pem_content)
          Aspera.assert_type(pem_content, String)
          @dynamic_key = OpenSSL::PKey.read(pem_content)
        end

        # Adds fields `public_keys` in provided Hash, if dynamic key is set.
        # @param h [Hash] Hash to add public key to
        def add_public_key(h)
          if @dynamic_key
            ssh_key = Net::SSH::Buffer.from(:key, @dynamic_key)
            # Get pub key in OpenSSH public key format (authorized_keys)
            h['public_keys'] = [
              ssh_key.read_string,
              Base64.strict_encode64(ssh_key.to_s)
            ].join(' ')
          end
          return h
        end

        # Adds fields `ssh_private_key` in provided Hash, if dynamic key is set.
        # @param h [Hash] Hash to add private key to
        def add_private_key(h)
          h['ssh_private_key'] = @dynamic_key.to_pem if @dynamic_key
          return h
        end

        # For access keys: provide expression to match entry in folder
        # @param match_expression one of supported types
        # @return lambda function
        def file_matcher(match_expression)
          case match_expression
          when Proc then return match_expression
          when Regexp then return ->(f){f['name'].match?(match_expression)}
          when String
            return ->(f){File.fnmatch(match_expression, f['name'], File::FNM_DOTMATCH)}
          when NilClass then return ->(_){true}
          else Aspera.error_unexpected_value(match_expression.class.name, type: ParameterError)
          end
        end

        # @return [Proc] lambda from provided CLI options
        def file_matcher_from_argument(options)
          return file_matcher(options.get_next_argument('filter', validation: MATCH_TYPES, mandatory: false))
        end

        # Split path into folder + filename
        # @return [Array] containing folder + inside folder/file
        def split_folder(path)
          folder = path.split(PATH_SEPARATOR)
          inside = folder.pop
          [folder.join(PATH_SEPARATOR), inside]
        end

        # Node API scopes
        # @return [String] node scope
        def token_scope(access_key, scope)
          return [SCOPE_NODE_PREFIX, access_key, SCOPE_SEPARATOR, scope].join('')
        end

        # Decode node scope into access key and scope
        # @return [Hash]
        def decode_scope(scope)
          items = scope.split(SCOPE_SEPARATOR, 2)
          Aspera.assert(items.length.eql?(2)){"invalid scope: #{scope}"}
          Aspera.assert(items[0].start_with?(SCOPE_NODE_PREFIX)){"invalid scope: #{scope}"}
          return {access_key: items[0][SCOPE_NODE_PREFIX.length..-1], scope: items[1]}
        end

        # Create an Aspera Node bearer token
        # @param access_key [String] Access key identifier
        # @param payload [String] JSON payload to be included in the token
        # @param private_key [OpenSSL::PKey::RSA] Private key to sign the token
        def bearer_token(access_key:, payload:, private_key:)
          Aspera.assert_type(payload, Hash)
          Aspera.assert(payload.key?('user_id'))
          Aspera.assert_type(payload['user_id'], String)
          Aspera.assert(!payload['user_id'].empty?)
          Aspera.assert_type(private_key, OpenSSL::PKey::RSA)
          # Manage convenience parameters
          expiration_sec = payload['_validity'] || BEARER_TOKEN_VALIDITY_DEFAULT
          payload.delete('_validity')
          scope = payload['_scope'] || SCOPE_USER
          payload.delete('_scope')
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

        # Decode an Aspera Node bearer token
        def decode_bearer_token(token)
          return JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition(SIGNATURE_DELIMITER).first)
        end

        # @return [Hash] Headers to call node API with access key and auth
        def bearer_headers(bearer_auth, access_key: nil)
          # If username is not provided, use the access key from the token
          if access_key.nil?
            access_key = Node.decode_scope(Node.decode_bearer_token(OAuth::Factory.bearer_token(bearer_auth))['scope'])[:access_key]
            Aspera.assert(!access_key.nil?)
          end
          return {
            Node::HEADER_X_ASPERA_ACCESS_KEY => access_key,
            'Authorization'                  => bearer_auth
          }
        end
      end

      attr_reader :app_info

      # @param app_info  [Hash,NilClass]   App information, typically AoC
      # @param add_tspec [Hash,NilClass]   Additional transfer spec
      # @param base_url  [String]          Rest parameters
      # @param auth      [String,NilClass] Rest parameters
      # @param headers   [String,NilClass] Rest parameters
      def initialize(app_info: nil, add_tspec: nil, **rest_args)
        # Init Rest
        super(**rest_args)
        @dynamic_key = nil
        @app_info = app_info
        # This is added to transfer spec, for instance to add tags (COS)
        @add_tspec = add_tspec
        @std_t_spec_cache = nil
        if !@app_info.nil?
          REQUIRED_APP_INFO_FIELDS.each do |field|
            Aspera.assert(@app_info.key?(field)){"app_info lacks field #{field}"}
          end
          REQUIRED_APP_API_METHODS.each do |method|
            Aspera.assert(@app_info[:api].respond_to?(method)){"#{@app_info[:api].class} lacks method #{method}"}
          end
        end
      end

      # Update transfer spec with special additional tags
      # @param tspec [Hash] Transfer spec to be modified
      # @return [Hash] initial modified tspec
      def add_tspec_info(tspec)
        tspec.deep_merge!(@add_tspec) unless @add_tspec.nil?
        return tspec
      end

      # @returns [Node] a Node Api object or nil if no App defined
      def node_id_to_node(node_id)
        if !@app_info.nil?
          return self if node_id.eql?(@app_info[:node_info]['id'])
          return @app_info[:api].node_api_from(
            node_id: node_id,
            workspace_id: @app_info[:workspace_id],
            workspace_name: @app_info[:workspace_name]
          )
        end
        Log.log.warn{"Cannot resolve link with node id #{node_id}, no resolver"}
        return
      end

      # Check if a link entry in folder has target information
      # @param entry [Hash] entry in folder
      # @return [Boolean] true if target information is available
      def entry_has_link_information(entry)
        # If target information is missing in folder, try to get it on entry
        if entry['target_node_id'].nil? || entry['target_id'].nil?
          link_entry = read("files/#{entry['id']}")
          entry['target_node_id'] = link_entry['target_node_id']
          entry['target_id'] = link_entry['target_id']
        end
        return true unless entry['target_node_id'].nil? || entry['target_id'].nil?
        Log.log.warn{"Missing target information for link: #{entry['name']}"}
        return false
      end

      # Recursively browse in a folder (with non-recursive method)
      # Entries of folders are processed if the processing method returns true
      # Links are processed on the respective node
      # @param method_sym [Symbol] processing method, arguments: entry, path, state
      # @param state [Object] state object sent to processing method
      # @param top_file_id [String] file id to start at (default = access key root file id)
      # @param top_file_path [String] path of top folder (default = /)
      # @para query [Hash, nil] optional query for `read`
      def process_folder_tree(method_sym:, state:, top_file_id:, top_file_path: '/', query: nil)
        Aspera.assert(!top_file_path.nil?){'top_file_path not set'}
        Log.log.debug{"process_folder_tree: node=#{@app_info ? @app_info[:node_info]['id'] : 'nil'}, file id=#{top_file_id},  path=#{top_file_path}"}
        # Start at top folder
        folders_to_explore = [{id: top_file_id, path: top_file_path}]
        Log.dump(:folders_to_explore, folders_to_explore)
        until folders_to_explore.empty?
          # Consume first in job list
          current_item = folders_to_explore.shift
          Log.log.debug{"Exploring #{current_item[:path]}".bg_green}
          # Get folder content
          folder_contents =
            begin
              # TODO: use header
              read("files/#{current_item[:id]}/files", query, **self.class.cache_control)
            rescue StandardError => e
              Log.log.warn{"#{current_item[:path]}: #{e.class} #{e.message}"}
              []
            end
          Log.dump(:folder_contents, folder_contents)
          folder_contents.each do |entry|
            if entry.key?('error')
              Log.log.error(entry['error']['user_message']) if entry['error'].is_a?(Hash) && entry['error'].key?('user_message')
              next
            end
            current_path = File.join(current_item[:path], entry['name'])
            Log.log.debug{"process_folder_tree: checking #{current_path}"}
            # Call block, continue only if method returns true
            next unless send(method_sym, entry, current_path, state)
            # Entry type is file, folder or link
            case entry['type']
            when 'folder'
              folders_to_explore.push({id: entry['id'], path: current_path})
            when 'link'
              if entry_has_link_information(entry)
                node_id_to_node(entry['target_node_id'])&.process_folder_tree(
                  method_sym:    method_sym,
                  state:         state,
                  top_file_id:   entry['target_id'],
                  top_file_path: current_path
                )
              end
            end
          end
        end
      end

      # Navigate the path from given file id on current node, and return the node and file id of target.
      # If the path ends with a "/" or process_last_link is true then if the last item in path is a link, it is followed.
      # @param top_file_id [String] id initial file id
      # @param path [String] file or folder path (end with "/" is like setting process_last_link)
      # @param process_last_link [Boolean] if true, follow the last link
      # @return [Hash] {.api,.file_id}
      def resolve_api_fid(top_file_id, path, process_last_link = false)
        Aspera.assert_type(top_file_id, String)
        Aspera.assert_type(path, String)
        process_last_link ||= path.end_with?(PATH_SEPARATOR)
        path_elements = path.split(PATH_SEPARATOR).reject(&:empty?)
        return {api: self, file_id: top_file_id} if path_elements.empty?
        resolve_state = {path: path_elements, consumed: [], result: nil, process_last_link: process_last_link}
        process_folder_tree(method_sym: :process_api_fid, state: resolve_state, top_file_id: top_file_id)
        raise ParameterError, "Entry not found: #{resolve_state[:path].first} in /#{resolve_state[:consumed].join(PATH_SEPARATOR)}" if resolve_state[:result].nil?
        Log.log.debug{"resolve_api_fid: #{path} -> #{resolve_state[:result][:api].base_url} #{resolve_state[:result][:file_id]}"}
        return resolve_state[:result]
      end

      # Given a list of paths, finds a common root and list of sub-paths
      # @param top_file_id [String] Root file id
      # @param paths [Array(Hash)] List of paths
      # @return [Array] size=2: apfid, paths (Array(Hash))
      def resolve_api_fid_paths(top_file_id, paths)
        Aspera.assert_type(paths, Array)
        Aspera.assert(paths.size.positive?)
        split_sources = paths.map{ |p| Pathname(p['source']).each_filename.to_a}
        root = []
        split_sources.map(&:size).min.times do |i|
          parts = split_sources.map{ |s| s[i]}
          break unless parts.uniq.size == 1
          root << parts.first
        end
        source_folder = File.join(root)
        source_paths = paths.each_with_index.map do |p, i|
          m = {'source' => File.join(split_sources[i][root.size..])}
          m['destination'] = p['destination'] if p.key?('destination')
          m
        end
        apifid = resolve_api_fid(top_file_id, source_folder, true)
        # If a single item
        if source_paths.size.eql?(1)
          # Get precise info in this element
          file_info = apifid[:api].read("files/#{apifid[:file_id]}")
          source_paths =
            case file_info['type']
            when 'file'
              # If the single source is a file, we need to split into folder path and filename
              src_dir_elements = source_folder.split(Api::Node::PATH_SEPARATOR)
              filename = src_dir_elements.pop
              apifid = resolve_api_fid(top_file_id, src_dir_elements.join(Api::Node::PATH_SEPARATOR), true)
              # Filename is the last one, source folder is what remains
              [{'source' => filename}]
            when 'link', 'folder'
              # Single source is 'folder' or 'link'
              # TODO: add this ? , 'destination'=>file_info['name']
              [{'source' => '.'}]
            else Aspera.error_unexpected_value(file_info['type']){'source type'}
            end
        end
        [apifid, source_paths]
      end

      # Recursively find files matching lambda
      # @param top_file_id [String] Search root
      # @param test_lambda [Proc] Test function
      def find_files(top_file_id, test_lambda)
        Log.log.debug{"find_files: file id=#{top_file_id}"}
        find_state = {found: [], test_lambda: test_lambda}
        process_folder_tree(method_sym: :process_find_files, state: find_state, top_file_id: top_file_id)
        return find_state[:found]
      end

      # Recursively list all files and folders
      def list_files(top_file_id, query: nil)
        find_state = {found: []}
        process_folder_tree(method_sym: :process_list_files, state: find_state, top_file_id: top_file_id, query: query)
        return find_state[:found]
      end

      # Generate a refreshed auth token
      def refreshed_transfer_token
        return oauth.authorization(refresh: true)
      end

      # Get a base download transfer spec (gen3)
      # @return [Hash] Base transfer spec
      def base_spec
        create(
          'files/download_setup',
          {transfer_requests: [{transfer_request: {paths: [{source: '/'}]}}]}
        )['transfer_specs'].first['transfer_spec']
      end

      # Get generic part of transfer spec with transport parameters only
      # @return [Hash] Base transfer spec
      def transport_params
        @std_t_spec_cache ||= base_spec.slice(*Transfer::Spec::TRANSPORT_FIELDS).freeze
      end

      # Create transfer spec for gen4
      # @param file_id   [String]   Destination or source folder (id)
      # @param direction [Symbol]   One of Transfer::Spec::DIRECTION_SEND, Transfer::Spec::DIRECTION_RECEIVE
      # @param ts_merge  [Hash,nil] Additional transfer spec to merge
      def transfer_spec_gen4(file_id, direction, ts_merge = nil)
        ak_name = nil
        ak_token = nil
        case auth_params[:type]
        when :basic
          ak_name = auth_params[:username]
          Aspera.assert(auth_params[:password]){'no secret in node object'}
          ak_token = Rest.basic_authorization(auth_params[:username], auth_params[:password])
        when :oauth2
          ak_name = params[:headers][HEADER_X_ASPERA_ACCESS_KEY]
          # TODO: token_generation_lambda = lambda{|do_refresh|oauth.authorization(refresh: do_refresh)}
          # Get bearer token, possibly use cache
          ak_token = oauth.authorization
        when :none
          ak_name = params[:headers][HEADER_X_ASPERA_ACCESS_KEY]
          ak_token = params[:headers]['Authorization']
        else Aspera.error_unexpected_value(auth_params[:type])
        end
        transfer_spec = {
          'direction' => direction,
          'token'     => ak_token,
          'tags'      => {
            Transfer::Spec::TAG_RESERVED => {
              'node' => {
                'access_key' => ak_name,
                'file_id'    => file_id
              }
            }
          }
        }
        # Add specials tags (cos)
        add_tspec_info(transfer_spec)
        transfer_spec.deep_merge!(ts_merge) unless ts_merge.nil?
        # Add application specific tags (AoC)
        @app_info[:api].add_ts_tags(transfer_spec: transfer_spec, app_info: @app_info) unless @app_info.nil?
        # Add remote host info
        if self.class.use_standard_ports
          # Get default TCP/UDP ports and transfer user
          transfer_spec.merge!(Transfer::Spec::AK_TSPEC_BASE)
          # By default: same address as node API
          transfer_spec['remote_host'] = URI.parse(base_url).host
          # AoC allows specification of other url
          transfer_spec['remote_host'] = @app_info[:node_info]['transfer_url'] if !@app_info.nil? && !@app_info[:node_info]['transfer_url'].nil? && !@app_info[:node_info]['transfer_url'].empty?
          info = read('info')
          # Get the transfer user from info on access key
          transfer_spec['remote_user'] = info['transfer_user'] if info['transfer_user']
          # Get settings from name.value array to hash key.value
          settings = info['settings']&.each_with_object({}){ |i, h| h[i['name']] = i['value']}
          # Check WSS ports
          Transfer::Spec::WSS_FIELDS.each do |i|
            transfer_spec[i] = settings[i] if settings.key?(i)
          end if settings.is_a?(Hash)
        else
          transfer_spec.merge!(transport_params)
        end
        Aspera.assert_values(transfer_spec['remote_user'], Transfer::Spec::ACCESS_KEY_TRANSFER_USER, type: :warn){'transfer user'}
        return transfer_spec
      end

      private

      # Method called in loop for each entry for `resolve_api_fid`
      # @return `true` to continue digging, `false` to stop processing: set state[:result] if found
      def process_api_fid(entry, path, state)
        # Stop digging here if not in right path
        return false unless entry['name'].eql?(state[:path].first)
        # Ok it matches, so we remove the match, and continue digging
        state[:consumed].push(state[:path].shift)
        path_fully_consumed = state[:path].empty?
        case entry['type']
        when 'file'
          # File must be terminal
          raise "#{entry['name']} is a file, expecting folder to find: #{state[:path]}" unless path_fully_consumed
          # It's terminal, we found it
          Log.log.debug{"process_api_fid: found #{path} -> #{entry['id']}"}
          state[:result] = {api: self, file_id: entry['id']}
          return false
        when 'folder'
          if path_fully_consumed
            # We found it
            state[:result] = {api: self, file_id: entry['id']}
            return false
          end
        when 'link'
          if path_fully_consumed
            if state[:process_last_link]
              # We found it
              other_node = nil
              other_node = node_id_to_node(entry['target_node_id']) if entry_has_link_information(entry)
              raise Error, 'Cannot resolve link' if other_node.nil?
              state[:result] = {api: other_node, file_id: entry['target_id']}
            else
              # We found it but we do not process the link
              state[:result] = {api: self, file_id: entry['id']}
            end
            return false
          end
        else Aspera.error_unexpected_value(entry['type'], type: :warn){'folder entry type'}
        end
        # Continue to dig folder
        return true
      end

      # Method called in loop for each entry for `find_files`
      def process_find_files(entry, path, state)
        state[:found].push(entry.merge({'path' => path})) if state[:test_lambda].call(entry)
        # Test all files deeply
        return true
      end

      # Method called in loop for each entry for `list_files`
      def process_list_files(entry, path, state)
        state[:found].push(entry.merge({'path' => path}))
        return false
      end
    end
  end
end
