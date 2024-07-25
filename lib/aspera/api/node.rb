# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/transfer/spec'
require 'aspera/rest'
require 'aspera/oauth'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'zlib'
require 'base64'

module Aspera
  module Api
    # Provides additional functions using node API with gen4 extensions (access keys)
    class Node < Aspera::Rest
      # node api permissions
      ACCESS_LEVELS = %w[delete list mkdir preview read rename write].freeze
      HEADER_X_ASPERA_ACCESS_KEY = 'X-Aspera-AccessKey'
      SCOPE_SEPARATOR = ':'
      SCOPE_USER = 'user:all'
      SCOPE_ADMIN = 'admin:all'
      SCOPE_NODE_PREFIX = 'node.'
      # prefix for ruby code for filter (deprecated)
      MATCH_EXEC_PREFIX = 'exec:'
      MATCH_TYPES = [String, Proc, Regexp, NilClass].freeze
      PATH_SEPARATOR = '/'
      SIGNATURE_DELIMITER = '==SIGNATURE=='
      BEARER_TOKEN_VALIDITY_DEFAULT = 86400
      BEARER_TOKEN_SCOPE_DEFAULT = SCOPE_USER
      private_constant :MATCH_EXEC_PREFIX, :MATCH_TYPES,
        :SIGNATURE_DELIMITER, :BEARER_TOKEN_VALIDITY_DEFAULT, :BEARER_TOKEN_SCOPE_DEFAULT,
        :SCOPE_SEPARATOR, :SCOPE_NODE_PREFIX

      # register node special token decoder
      OAuth::Factory.instance.register_decoder(lambda{|token|Node.decode_bearer_token(token)})

      # class instance variable, access with accessors on class
      @use_standard_ports = true

      class << self
        attr_accessor :use_standard_ports

        # For access keys: provide expression to match entry in folder
        def file_matcher(match_expression)
          case match_expression
          when Proc then return match_expression
          when Regexp then return ->(f){f['name'].match?(match_expression)}
          when String
            if match_expression.start_with?(MATCH_EXEC_PREFIX)
              code = "->(f){#{match_expression[MATCH_EXEC_PREFIX.length..-1]}}"
              Log.log.warn{"Use of prefix #{MATCH_EXEC_PREFIX} is deprecated (4.15), instead use: @ruby:'#{code}'"}
              return Environment.secure_eval(code, __FILE__, __LINE__)
            end
            return lambda{|f|File.fnmatch(match_expression, f['name'], File::FNM_DOTMATCH)}
          when NilClass then return ->(_){true}
          else Aspera.error_unexpected_value(match_expression.class.name, exception_class: Cli::BadArgument)
          end
        end

        def file_matcher_from_argument(options)
          return file_matcher(options.get_next_argument('filter', validation: MATCH_TYPES, mandatory: false))
        end

        # node API scopes
        def token_scope(access_key, scope)
          return [SCOPE_NODE_PREFIX, access_key, SCOPE_SEPARATOR, scope].join('')
        end

        def decode_scope(scope)
          items = scope.split(SCOPE_SEPARATOR, 2)
          Aspera.assert(items.length.eql?(2)){"invalid scope: #{scope}"}
          Aspera.assert(items[0].start_with?(SCOPE_NODE_PREFIX)){"invalid scope: #{scope}"}
          return {access_key: items[0][SCOPE_NODE_PREFIX.length..-1], scope: items[1]}
        end

        # Create an Aspera Node bearer token
        # @param payload [String] JSON payload to be included in the token
        # @param private_key [OpenSSL::PKey::RSA] Private key to sign the token
        def bearer_token(access_key:, payload:, private_key:)
          Aspera.assert_type(payload, Hash)
          Aspera.assert(payload.key?('user_id'))
          Aspera.assert_type(payload['user_id'], String)
          Aspera.assert(!payload['user_id'].empty?)
          Aspera.assert_type(private_key, OpenSSL::PKey::RSA)
          # manage convenience parameters
          expiration_sec = payload['_validity'] || BEARER_TOKEN_VALIDITY_DEFAULT
          payload.delete('_validity')
          scope = payload['_scope'] || BEARER_TOKEN_SCOPE_DEFAULT
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

        def decode_bearer_token(token)
          return JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition(SIGNATURE_DELIMITER).first)
        end

        def bearer_headers(bearer_auth, access_key: nil)
          # if username is not provided, use the access key from the token
          if access_key.nil?
            access_key = Node.decode_scope(Node.decode_bearer_token(OAuth::Factory.bearer_extract(bearer_auth))['scope'])[:access_key]
            Aspera.assert(!access_key.nil?)
          end
          return {
            Node::HEADER_X_ASPERA_ACCESS_KEY => access_key,
            'Authorization'                  => bearer_auth
          }
        end
      end

      # fields in @app_info
      REQUIRED_APP_INFO_FIELDS = %i[api app node_info workspace_id workspace_name].freeze
      # methods of @app_info[:api]
      REQUIRED_APP_API_METHODS = %i[node_api_from add_ts_tags].freeze
      private_constant :REQUIRED_APP_INFO_FIELDS, :REQUIRED_APP_API_METHODS

      attr_reader :app_info

      # @param base_url  [String]          Rest parameters
      # @param auth      [String,NilClass] Rest parameters
      # @param headers   [String,NilClass] Rest parameters
      # @param app_info  [Hash,NilClass]   Special processing for AoC
      # @param add_tspec [Hash,NilClass]   Additional transfer spec
      def initialize(app_info: nil, add_tspec: nil, **rest_args)
        # init Rest
        super(**rest_args)
        @app_info = app_info
        # this is added to transfer spec, for instance to add tags (COS)
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

      # update transfer spec with special additional tags
      def add_tspec_info(tspec)
        tspec.deep_merge!(@add_tspec) unless @add_tspec.nil?
        return tspec
      end

      # @returns [Node] a Node or nil
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
        Aspera.assert(!top_file_path.nil?){'top_file_path not set'}
        Aspera.assert(block){'Missing block'}
        # start at top folder
        folders_to_explore = [{id: top_file_id, path: top_file_path}]
        Log.log.debug{Log.dump(:folders_to_explore, folders_to_explore)}
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
          Log.log.debug{Log.dump(:folder_contents, folder_contents)}
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
      end

      # Navigate the path from given file id
      # @param top_file_id [String] id initial file id
      # @param path [String]  file path
      # @return [Hash] {.api,.file_id}
      def resolve_api_fid(top_file_id, path)
        Aspera.assert_type(top_file_id, String)
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
        return oauth.token(refresh: true)
      end

      # @return part of transfer spec with transport parameters only
      def transport_params
        if @std_t_spec_cache.nil?
          # retrieve values from API (and keep a copy/cache)
          full_spec = create(
            'files/download_setup',
            {transfer_requests: [{transfer_request: {paths: [{source: '/'}]}}]}
          )[:data]['transfer_specs'].first['transfer_spec']
          # set available fields
          @std_t_spec_cache = Transfer::Spec::TRANSPORT_FIELDS.each_with_object({}) do |i, h|
            h[i] = full_spec[i] if full_spec.key?(i)
          end
        end
        return @std_t_spec_cache
      end

      # Create transfer spec for gen4
      def transfer_spec_gen4(file_id, direction, ts_merge=nil)
        ak_name = nil
        ak_token = nil
        case auth_params[:type]
        when :basic
          ak_name = auth_params[:username]
          Aspera.assert(auth_params[:password]){'no secret in node object'}
          ak_token = Rest.basic_token(auth_params[:username], auth_params[:password])
        when :oauth2
          ak_name = params[:headers][HEADER_X_ASPERA_ACCESS_KEY]
          # TODO: token_generation_lambda = lambda{|do_refresh|oauth.token(refresh: do_refresh)}
          # get bearer token, possibly use cache
          ak_token = oauth.token(refresh: false)
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
          transfer_spec.merge!(Transfer::Spec::AK_TSPEC_BASE)
          # by default: same address as node API
          transfer_spec['remote_host'] = URI.parse(base_url).host
          # AoC allows specification of other url
          if !@app_info.nil? && !@app_info[:node_info]['transfer_url'].nil? && !@app_info[:node_info]['transfer_url'].empty?
            transfer_spec['remote_host'] = @app_info[:node_info]['transfer_url']
          end
          info = read('info')[:data]
          # get the transfer user from info on access key
          transfer_spec['remote_user'] = info['transfer_user'] if info['transfer_user']
          # get settings from name.value array to hash key.value
          settings = info['settings']&.each_with_object({}){|i, h|h[i['name']] = i['value']}
          # check WSS ports
          %w[wss_enabled wss_port].each do |i|
            transfer_spec[i] = settings[i] if settings.key?(i)
          end if settings.is_a?(Hash)
        else
          transfer_spec.merge!(transport_params)
        end
        Log.log.warn{"Expected transfer user: #{Transfer::Spec::ACCESS_KEY_TRANSFER_USER}, but have #{transfer_spec['remote_user']}"} \
          unless transfer_spec['remote_user'].eql?(Transfer::Spec::ACCESS_KEY_TRANSFER_USER)
        return transfer_spec
      end
    end
  end
end
