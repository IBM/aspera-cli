# frozen_string_literal: true

require 'uri'
require 'base64'
require 'aspera/assert'
require 'aspera/rest'
require 'aspera/temp_file_manager'

module Aspera
  # Read content from a URI; supported schemes: file:, http:, https:, data:
  #
  # == file: URL convention
  # The prefix is always +file:///+ (three slashes, no host part).
  # The characters after the prefix are interpreted as a file path:
  #   file:///relative/path    -> relative path "relative/path"
  #   file:////absolute/path   -> absolute path "/absolute/path"
  #
  # This mirrors shell behaviour: a bare filename needs no leading slash,
  # while an absolute path carries its own leading slash after the prefix.
  module UriReader
    SCHEME_FILE = 'file'
    SCHEME_FILE_PFX1 = "#{SCHEME_FILE}:"
    # Fixed prefix for file: URLs (no host, three slashes).
    # What follows is the literal path: relative or absolute (starting with a second slash).
    SCHEME_FILE_PFX2 = "#{SCHEME_FILE_PFX1}///"
    private_constant :SCHEME_FILE, :SCHEME_FILE_PFX1, :SCHEME_FILE_PFX2
    class << self
      # @return [Boolean] true if +url+ uses the file: scheme recognised by this module
      def file?(url)
        url.start_with?(SCHEME_FILE_PFX2)
      end

      # Build a file: URL from +path+.
      # A relative path yields +file:///path+; an absolute path yields +file:////path+.
      # @param path [String] relative or absolute file-system path
      # @return [String] corresponding file: URL
      def file_url(path)
        return "#{SCHEME_FILE_PFX2}#{path}"
      end

      # Extract the file-system path from a file: URL.
      # Reverses {file_url}: strips the +file:///+ prefix and returns the literal path
      # (relative or absolute) without any working-directory expansion.
      # @param url [String] a file: URL produced by {file_url}
      # @return [String] the literal path encoded in the URL
      def file_path(url)
        Aspera.assert(file?(url)){"use format: #{file_url('<path>')}"}
        return url.delete_prefix(SCHEME_FILE_PFX2)
      end

      # Read content from a URI and return it as a String.
      # Supported schemes: +http+, +https+, +data+, +file+, and bare paths (no scheme).
      # For file: URLs the path is extracted via {file_path} to respect the module convention
      # (see module-level documentation).  Ruby's URI parser is not used for file: URLs because
      # it interprets the three-slash prefix differently (it always produces an absolute path).
      # Bare paths (no scheme) are passed to File.read directly; leading +/~/+, +/./+, +/../+
      # are expanded via +File.expand_path+ after stripping the synthetic leading slash added by
      # URI.
      def read(uri_to_read)
        # Handle file: URLs directly to honour the file:///relative vs file:////absolute convention.
        return File.read(file_path(uri_to_read)) if file?(uri_to_read)
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
        when NilClass
          local_file_path = uri.path
          Aspera.assert(!local_file_path.nil?, type: Error){'URL shall have a path, check syntax'}
          local_file_path = File.expand_path(local_file_path.gsub(%r{^/}, '')) if %r{^/(~|.|..)/}.match?(local_file_path)
          return File.read(local_file_path)
        else Aspera.error_unexpected_value(uri.scheme){"scheme for [#{uri_to_read}]"}
        end
      end

      # Return the local file-system path for the content at +url+, downloading to a temp file if needed.
      # For file: URLs the path is extracted directly (no download).
      # For data: and http(s): URLs the content is written to a temporary file and its path is returned.
      # @return [String] local path to a file containing the URL content
      def read_as_file(url)
        if url.start_with?(SCHEME_FILE_PFX1)
          # file: scheme: extract the literal path encoded in the URL (relative or absolute).
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
          Aspera::Rest.new(base_url: url, redirect_max: 3).call(operation: 'GET', save_to: temp_file)
          return temp_file
        end
      end
    end
  end
end
