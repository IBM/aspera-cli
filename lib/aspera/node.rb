require 'aspera/rest'
require 'aspera/log'
require 'zlib'
require 'base64'

module Aspera
  # Provides additional functions using node API.
  class Node < Rest
    # permissions
    ACCESS_LEVELS=['delete','list','mkdir','preview','read','rename','write']

    # for information only
    def self.decode_bearer_token(token)
      return JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition('==SIGNATURE==').first)
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
    def crawl(processor,opt={})
      Log.log.debug("crawl1 #{opt}")
      # not possible with bearer token
      opt[:top_file_id] ||= read('access_keys/self')[:data]['root_file_id']
      opt[:top_file_path] ||= '/'
      opt[:method] ||= :process_entry
      raise "processor must have #{opt[:method]}" unless processor.respond_to?(opt[:method])
      Log.log.debug("crawl #{opt}")
      #top_info=read("files/#{opt[:top_file_id]}")[:data]
      folders_to_explore=[{id: opt[:top_file_id], relpath: opt[:top_file_path]}]
      Log.dump(:folders_to_explore,folders_to_explore)
      while !folders_to_explore.empty? do
        current_item = folders_to_explore.shift
        Log.log.debug("searching #{current_item[:relpath]}".bg_green)
        # get folder content
        folder_contents = begin
          read("files/#{current_item[:id]}/files")[:data]
        rescue => e
          Log.log.warn("#{current_item[:relpath]}: #{e.class} #{e.message}")
          []
        end
        Log.dump(:folder_contents,folder_contents)
        folder_contents.each do |entry|
          relative_path=File.join(current_item[:relpath],entry['name'])
          Log.log.debug("looking #{relative_path}".bg_green)
          # entry type is file, folder or link
          if processor.send(opt[:method],entry,relative_path) and entry['type'].eql?('folder')
            folders_to_explore.push({:id=>entry['id'],:relpath=>relative_path})
          end
        end
      end
    end
  end
end
