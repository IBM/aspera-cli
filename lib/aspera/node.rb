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

    def initialize(rest_params)
      super(rest_params)
    end

    # recursively crawl in a folder.
    # subfolders a processed if the processing method returns true
    # @param processor must provide a method to process each entry
    # @param opt options
    # - top_file_id file id to start at (default = access key root file id)
    # - top_file_path path of top folder (default = /)
    # - method processing method (default= process_entry)
    def crawl(processor:, method: :process_entry, top_file_id: nil, top_file_path: '/')
      # not possible with bearer token
      top_file_id ||= read('access_keys/self')[:data]['root_file_id']
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
          # entry type is file, folder or link
          if processor.send(method, entry, relative_path) && entry['type'].eql?('folder')
            folders_to_explore.push({id: entry['id'], relpath: relative_path})
          end
        end
      end
    end # crawl

    def process_folder_entry(entry, path)
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
        raise "cannot process link in pure node out of AoC for: #{path}"
      when 'folder'
        if @resolve_state[:path].empty?
          # found: store
          @resolve_state[:result][:file_id] = entry['id']
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
      result = {api: self, file_id: nil}
      # init result state
      @resolve_state = {path: path_elements, result: result}
      crawl(processor: self, method: :process_folder_entry, top_file_id: top_file_id)
      not_found = @resolve_state[:path]
      @resolve_state = nil
      raise "entry not found: #{not_found}" if result[:file_id].nil?
      return result
    end

    def find_files(top_file_id, test_block)
      Log.log.debug("find_files: fileid=#{top_file_id}")
      @find_state = {found: [], test_block: test_block}
      crawl(processor: self, method: :process_find_files, top_file_id: top_file_id)
      result = @find_state[:found]
      @find_state = nil
      return result
    end

    #private

    # add entry to list if test block is success
    def process_find_files(entry, path)
      begin
        # add to result if match filter
        @find_state[:found].push(entry.merge({'path' => path})) if @find_state[:test_block].call(entry)
        # process link
        if entry[:type].eql?('link')
          #sub_node_info = read("nodes/#{entry['target_node_id']}")[:data]
          #sub_opt = {method: process_find_files, top_file_id: entry['target_id'], top_file_path: path}
          #node_info_to_api(sub_node_info).crawl(self,sub_opt)
          raise "cannot follow cross node link: #{path}"
        end
      rescue StandardError => e
        Log.log.error("#{path}: #{e.message}")
      end
      # process all folders
      return true
    end
  end
end
