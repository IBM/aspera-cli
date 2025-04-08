# frozen_string_literal: true

require 'uri'
require 'aspera/rest'
require 'aspera/temp_file_manager'

module Aspera
  # read some content from some URI, support file: , http: and https: schemes
  module UriReader
    FILE_SCHEME_PREFIX = 'file:///'
    private_constant :FILE_SCHEME_PREFIX
    class << self
      # read some content from some URI, support file: , http: and https: schemes
      def read(uri_to_read)
        uri = URI.parse(uri_to_read)
        case uri.scheme
        when 'http', 'https'
          return Rest.new(base_url: uri_to_read, redirect_max: 5).call(operation: 'GET', headers: {'Accept' => '*/*'})[:data]
        when 'file', NilClass
          local_file_path = uri.path
          raise 'URL shall have a path, check syntax' if local_file_path.nil?
          local_file_path = File.expand_path(local_file_path.gsub(%r{^/}, '')) if %r{^/(~|.|..)/}.match?(local_file_path)
          return File.read(local_file_path)
        else
          raise "unknown scheme: [#{uri.scheme}] for [#{uri_to_read}]"
        end
      end

      # @return path to file with content at URL
      def read_as_file(url)
        if url.start_with?('file:')
          # require specific file scheme: the path part is "relative", or absolute if there are 4 slash
          raise "use format: #{FILE_SCHEME_PREFIX}<path>" unless url.start_with?(FILE_SCHEME_PREFIX)
          return File.expand_path(url[FILE_SCHEME_PREFIX.length..-1])
        else
          # autodelete on exit
          sdk_archive_path = TempFileManager.instance.new_file_path_global(suffix: File.basename(url))
          Aspera::Rest.new(base_url: url, redirect_max: 3).call(operation: 'GET', save_to_file: sdk_archive_path)
          return sdk_archive_path
        end
      end
    end
  end
end
