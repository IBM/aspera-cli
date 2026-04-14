# frozen_string_literal: true

require 'uri'
require 'base64'
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
      # @return [Boolean] true if the URL is a file:// URL
      def file?(url)
        url.start_with?(SCHEME_FILE_PFX2)
      end

      # @return [String] a file:// URL for the given path
      def file_url(path)
        return "#{SCHEME_FILE_PFX2}#{path}"
      end

      # @return [String] the path of a file:// URL
      def file_path(url)
        Aspera.assert(file?(url)){"use format: #{file_url('<path>')}"}
        File.expand_path(url[SCHEME_FILE_PFX2.length..-1])
      end

      # Read some content from some URI, support file: , http: and https: schemes
      def read(uri_to_read)
        uri = URI.parse(uri_to_read)
        case uri.scheme
        when 'http', 'https'
          return Rest.new(base_url: uri_to_read, redirect_max: 5).read(nil, headers: {'Accept' => '*/*'})
        when 'data'
          metadata, encoded_data = uri.opaque.split(',', 2)
          if metadata.end_with?(';base64')
            Base64.decode64(encoded_data)
          else
            URI.decode_www_form_component(encoded_data)
          end
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
          return file_path(url)
        elsif url.start_with?('data:')
          # download to temp file
          # auto-delete on exit
          temp_file = TempFileManager.instance.new_file_path_global('uri_reader')
          File.write(temp_file, read(url), binmode: true)
          return temp_file
        else
          # download to temp file
          # auto-delete on exit
          temp_file = TempFileManager.instance.new_file_path_global(suffix: File.basename(url))
          Aspera::Rest.new(base_url: url, redirect_max: 3).call(operation: 'GET', save_to_file: temp_file)
          return temp_file
        end
      end
    end
  end
end
