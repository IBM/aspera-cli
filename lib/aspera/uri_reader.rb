# frozen_string_literal: true

require 'uri'
require 'aspera/assert'
require 'aspera/rest'
require 'aspera/temp_file_manager'

module Aspera
  # Read some content from some URI, support file: , http: and https: schemes
  module UriReader
    SCHEME_FILE = 'file'
    SCHEME_FILE_PFX1 = "#{SCHEME_FILE}:"
    SCHEME_FILE_PFX2 = "#{SCHEME_FILE_PFX1}///"
    private_constant :SCHEME_FILE, :SCHEME_FILE_PFX1, :SCHEME_FILE_PFX2
    class << self
      # Read some content from some URI, support file: , http: and https: schemes
      def read(uri_to_read)
        uri = URI.parse(uri_to_read)
        case uri.scheme
        when 'http', 'https'
          return Rest.new(base_url: uri_to_read, redirect_max: 5).call(operation: 'GET', headers: {'Accept' => '*/*'})[:data]
        when SCHEME_FILE, NilClass
          local_file_path = uri.path
          raise Error, 'URL shall have a path, check syntax' if local_file_path.nil?
          local_file_path = File.expand_path(local_file_path.gsub(%r{^/}, '')) if %r{^/(~|.|..)/}.match?(local_file_path)
          return File.read(local_file_path)
        else Aspera.error_unexpected_value(uri.scheme){"scheme for [#{uri_to_read}]"}
        end
      end

      # @return Path to file with content at URL
      def read_as_file(url)
        if url.start_with?(SCHEME_FILE_PFX1)
          # for file scheme, return directly the path
          # require specific file scheme: the path part is "relative", or absolute if there are 4 slash
          raise "use format: #{SCHEME_FILE_PFX2}<path>" unless url.start_with?(SCHEME_FILE_PFX2)
          return File.expand_path(url[SCHEME_FILE_PFX2.length..-1])
        else
          # download to temp file
          # autodelete on exit
          sdk_archive_path = TempFileManager.instance.new_file_path_global(suffix: File.basename(url))
          Aspera::Rest.new(base_url: url, redirect_max: 3).call(operation: 'GET', save_to_file: sdk_archive_path)
          return sdk_archive_path
        end
      end
    end
  end
end
