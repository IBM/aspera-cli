# frozen_string_literal: true

require 'uri'
require 'aspera/rest'

module Aspera
  module UriReader
    class << self
      # read some content from some URI, support file: , http: and https: schemes
      def read(uri_to_read)
        uri = URI.parse(uri_to_read)
        case uri.scheme
        when 'http', 'https'
          return Rest.new(base_url: uri_to_read, redirect_max: 5).call(operation: 'GET', subpath: '', headers: {'Accept' => 'text/plain'})[:data]
        when 'file', NilClass
          local_file_path = uri.path
          raise 'URL shall have a path, check syntax' if local_file_path.nil?
          local_file_path = File.expand_path(local_file_path.gsub(%r{^/}, '')) if %r{^/(~|.|..)/}.match?(local_file_path)
          return File.read(local_file_path)
        else
          raise "unknown scheme: [#{uri.scheme}] for [#{uri_to_read}]"
        end
      end
    end
  end
end
