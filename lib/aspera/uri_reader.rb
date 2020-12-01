require 'uri'
require 'net/http'
require 'net/https'

module Aspera
  module UriReader
    # read some content from some URI, support file: , http: and https: schemes
    def self.read(proxy_pac_uri)
      proxy_uri=URI.parse(proxy_pac_uri)
      if proxy_uri.scheme.eql?('http')
        return Net::HTTP.start(proxy_uri.host, proxy_uri.port){|http|http.get(proxy_uri.path)}.body
      elsif proxy_uri.scheme.eql?('https')
        return Net::HTTPS.start(proxy_uri.host, proxy_uri.port){|http|http.get(proxy_uri.path)}.body
      elsif proxy_uri.scheme.eql?('file')
        local_file_path=proxy_uri.path
        raise "URL shall have a path, check syntax" if local_file_path.nil?
        local_file_path=File.expand_path(local_file_path.gsub(/^\//,'')) if local_file_path.match(/^\/(~|.|..)\//)
        return File.read(local_file_path)
      elsif proxy_uri.scheme.eql?('')
        return File.read(proxy_uri)
      end
      raise "no scheme: [#{proxy_uri.scheme}] for [#{proxy_pac_uri}]"
    end
  end
end
