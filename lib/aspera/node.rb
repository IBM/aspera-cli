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
  class Node < Rest
    # permissions
    ACCESS_LEVELS = %w[delete list mkdir preview read rename write].freeze
    # prefix for ruby code for filter
    MATCH_EXEC_PREFIX = 'exec:'

    # register node special token decoder
    Oauth.register_decoder(lambda{|token|JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition('==SIGNATURE==').first)})

    class << self
      def set_ak_basic_token(ts, ak, secret)
        Log.log.warn("Expected transfer user: #{Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER}, "\
          "but have #{ts['remote_user']}") unless ts['remote_user'].eql?(Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER)
        ts['token'] = Rest.basic_creds(ak, secret)
      end

      # for access keys: provide expression to match entry in folder
      # if no prefix: regex
      # if prefix: ruby code
      # if filder is nil, then always match
      def file_matcher(match_expression)
        match_expression ||= "#{MATCH_EXEC_PREFIX}true"
        if match_expression.start_with?(MATCH_EXEC_PREFIX)
          return Environment.secure_eval("lambda{|f|#{match_expression[MATCH_EXEC_PREFIX.length..-1]}}")
        end
        return lambda{|f|f['name'].match(/#{match_expression}/)}
      end
    end

    REQUIRED_APP_INFO_FIELDS=%i[node_info app api plugin].freeze
    REQUIRED_APP_API_METHODS=%i[node_id_to_api add_ts_tags].freeze
    private_constant :REQUIRED_APP_INFO_FIELDS, :REQUIRED_APP_API_METHODS

    attr_reader :app_info

    # @param params [Hash] Rest parameters
    # @param app_info [Hash,NilClass] special processing for AoC
    def initialize(params:, app_info: nil)
      super(params)
      @app_info=app_info
      if !@app_info.nil?
        REQUIRED_APP_INFO_FIELDS.each do |field|
          raise "INTERNAL ERROR: app_info lacks field #{field}" unless @app_info.has_key?(field)
        end
        REQUIRED_APP_API_METHODS.each do |method|
          raise "INTERNAL ERROR: #{@app_info[:api].class} lacks method #{method}" unless @app_info[:api].respond_to?(method)
        end
      end
    end

    # @returns [Aspera::Node] a Node or nil
    def node_id_to_node(node_id)
      return self if !@app_info.nil? && @app_info[:node_info]['id'].eql?(node_id)
      return @app_info[:api].node_id_to_api(node_id) unless @app_info.nil?
      Log.log.warn("cannot resolve link with node id #{node_id}")
      return nil
    end

    # recursively crawl in a folder.
    # subfolders a processed if the processing method returns true
    # @param processor must provide a method to process each entry
    # @param opt options
    # - top_file_id file id to start at (default = access key root file id)
    # - top_file_path path of top folder (default = /)
    # - method processing method (default= process_entry)
    def crawl(state:, method:, top_file_id:, processor: nil, top_file_path: '/')
      raise 'INTERNAL ERROR: top_file_path not set' if top_file_path.nil?
      processor ||= self
      raise "processor #{processor.class} must have #{method}" unless processor.respond_to?(method)
      #top_info=read("files/#{top_file_id}")[:data]
      folders_to_explore = [{id: top_file_id, relpath: top_file_path}]
      Log.dump(:folders_to_explore, folders_to_explore)
      while !folders_to_explore.empty?
        current_item = folders_to_explore.shift
        Log.log.debug("searching #{current_item[:relpath]}".bg_green)
        # get folder content
        folder_contents =
          begin
            read("files/#{current_item[:id]}/files")[:data]
          rescue StandardError => e
            Log.log.warn("#{current_item[:relpath]}: #{e.class} #{e.message}")
            []
          end
        Log.dump(:folder_contents, folder_contents)
        folder_contents.each do |entry|
          relative_path = File.join(current_item[:relpath], entry['name'])
          Log.log.debug("looking #{relative_path}".bg_green)
          # continue only if processor tells so
          next unless processor.send(method, entry, relative_path, state)
          # entry type is file, folder or link
          case entry['type']
          when 'folder'
            folders_to_explore.push({id: entry['id'], relpath: relative_path})
          when 'link'
            node_id_to_node(entry['target_node_id'])&.crawl(
              state:         state,
              method:        method,
              top_file_id:   entry['target_id'],
              processor:     processor.eql?(self) ? nil : processor,
              top_file_path: relative_path)
          end
        end
      end
    end # crawl

    # @returns true if processing need to continue
    def process_resolve_node_path(entry, path, state)
      # stop digging here if not in right path
      return false unless entry['name'].eql?(state[:path].first)
      # ok it matches, so we remove the match
      state[:path].shift
      case entry['type']
      when 'file'
        # file must be terminal
        raise "#{entry['name']} is a file, expecting folder to find: #{state[:path]}" unless state[:path].empty?
        # it's terminal, we found it
        state[:result] = {api: self, file_id: entry['id']}
        return false
      when 'folder'
        if state[:path].empty?
          # we found it
          state[:result] = {api: self, file_id: entry['id']}
          return false
        end
      when 'link'
        if state[:path].empty?
          # we found it
          other_node = node_id_to_node(entry['target_node_id'])
          raise 'cannot resolve link' if other_node.nil?
          state[:result] = {api: other_node, file_id: entry['target_id']}
          return false
        end
      else
        Log.log.warn("Unknown element type: #{entry['type']}")
      end
      # continue to dig folder
      return true
    end

    # navigate the path from given file id
    # @param id initial file id
    # @param path file path
    # @return {.api,.file_id}
    def resolve_api_fid(top_file_id, path)
      path_elements = path.split(AoC::PATH_SEPARATOR).reject(&:empty?)
      return {api: self, file_id: top_file_id} if path_elements.empty?
      resolve_state = {path: path_elements, result: nil}
      crawl(state: resolve_state, method: :process_resolve_node_path, top_file_id: top_file_id)
      raise "entry not found: #{resolve_state[:path]}" if resolve_state[:result].nil?
      return resolve_state[:result]
    end

    def find_files(top_file_id, test_block)
      Log.log.debug("find_files: fileid=#{top_file_id}")
      find_state = {found: [], test_block: test_block}
      crawl(state: find_state, method: :process_find_files, top_file_id: top_file_id)
      return find_state[:found]
    end

    #private

    # add entry to list if test block is success
    def process_find_files(entry, path, state)
      begin
        # add to result if match filter
        state[:found].push(entry.merge({'path' => path})) if state[:test_block].call(entry)
        # process link
        if entry[:type].eql?('link')
          other_node = node_id_to_node(entry['target_node_id'])
          other_node.crawl(state: state, method: process_find_files, top_file_id: entry['target_id'], top_file_path: path)
        end
      rescue StandardError => e
        Log.log.error("#{path}: #{e.message}")
      end
      # process all folders
      return true
    end
  end
end
