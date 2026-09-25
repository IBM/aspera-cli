# frozen_string_literal: true

require 'aspera/rest/parameters'
require 'aspera/log'
require 'aspera/assert'
require 'net/http'
require 'net/https'
require 'uri'
require 'base64'

module Aspera
  # HTTP REST client and helpers
  module Rest
    class << self
      # Build a Basic authentication header value
      # @param user [String] Username
      # @param pass [String] Password
      # @return [String] Basic auth token
      def basic_authorization(user, pass) = "Basic #{Base64.strict_encode64("#{user}:#{pass}")}"

      # Indicate that the given Hash query uses php style for array parameters
      # @param query [Hash] A key can have Array value and result will use PHP format: a[]=1&a[]=2
      # @return [Hash] The query parameters.
      def php_style(query)
        Aspera.assert_type(query, Hash) { 'query' }
        query[:x_array_php_style] = true
        query
      end

      # Build URI from URL and parameters and check it is `http` or `https`.
      # Check if php style is specified.
      # `nil` values in query result in key without value, e.g. `?a`, while empty string values result in `?a=`.
      # @param url   [String]            The URL without query.
      # @param query [Hash,Array,String] The query parameters.
      # @return [URI] The built URI.
      def build_uri(url, query)
        uri = URI.parse(url)
        Aspera.assert_values(uri.scheme, %w[http https]) { 'URI scheme' }
        return uri if query.nil? || query.respond_to?(:empty?) && query.empty?
        Log.dump(:query, query)
        uri.query =
          case query
          when String
            query
          when Hash
            URI.encode_www_form(h_to_query_array(query))
          when Array
            Aspera.assert(query.all? { |i| i.is_a?(Array) && i.length.eql?(2) }, 'Query must be array of arrays of 2 elements')
            URI.encode_www_form(query) # remove nil values
          else Aspera.error_unexpected_value(query.class) { 'query type' }
          end.gsub('%5B%5D=', '[]=')
        # [] is allowed in url parameters
        uri
      end

      # Support array for query parameter, there is no standard.
      # Either p=1&p=2 (default)
      # or p[]=1&p[]=2 (if `:x_array_php_style` is set to true in query)
      # @param query [Hash] HTTP query as hash
      # @return [Array<Array>] Array of [key, value] pairs suitable for URI.encode_www_form
      def h_to_query_array(query)
        Aspera.assert_type(query, Hash)
        suffix = query[:x_array_php_style] ? '[]' : nil
        query.each_with_object([]) do |(k, v), query_array|
          next if k.eql?(:x_array_php_style)
          case v
          when Array
            v.each do |e|
              query_array.push(["#{k}#{suffix}", e])
            end
          else
            query_array.push([k, v])
          end
        end
      end

      # Decode query string as Hash
      # if parameter is only once, then it's a scalar
      # if a parameter is several, then it's array
      # if parameter has [] then it's an array, and [] is removed
      # Support arrays in query string, e.g. PHP's way is p[]=1&p[]=2
      # @param query [String] query string as in URI.query
      # @return [Hash] decoded query
      def query_to_h(query)
        URI.decode_www_form(query).each_with_object({}) do |(key, value), h|
          if key.end_with?('[]')
            key = key[..-3]
            h[key] = [] unless h.key?(key)
          end
          if h.key?(key)
            h[key] = [h[key]] if !h[key].is_a?(Array)
            h[key].push(value)
          else
            h[key] = value
          end
        end
      end

      # Start a HTTP/S session, also used for web sockets
      # @param base_url [String] Base url of HTTP/S session
      # @return [Net::HTTP] A started HTTP session
      def start_http_session(base_url)
        uri = URI.parse(base_url)
        Aspera.assert_values(uri.scheme, %w[http https]) { 'URI scheme' }
        # This honors http_proxy env var
        http_session = Net::HTTP.new(uri.host, uri.port)
        http_session.use_ssl = uri.scheme.eql?('https')
        # Set http options in callback, such as timeout and cert. verification
        Parameters.instance.session_cb&.call(http_session)
        # Manually start session for keep alive (if supported by server, else, session is closed every time)
        http_session.start
        return http_session
      end

      # get Net::HTTP underlying socket i/o
      # little hack, handy because HTTP debug, proxy, etc... will be available
      # used implement web sockets after `start_http_session`
      # @param http_session [Net::HTTP] the session object
      # @return [Net::BufferedIO] The underlying socket i/o
      def io_http_session(http_session)
        Aspera.assert_type(http_session, Net::HTTP)
        # Net::BufferedIO in net/protocol.rb
        result = http_session.instance_variable_get(:@socket)
        Aspera.assert(!result.nil?) { "no socket for #{http_session}" }
        return result
      end

      # Get certificate chain of remote server
      # @param url       [String]  URL of server
      # @param as_string [Boolean] `true` to return PEM string, `false` for certificate objects
      # @return [String, Array<OpenSSL::X509::Certificate>] Certificates of remote server
      def remote_certificate_chain(url, as_string: true)
        result = []
        # initiate a session to retrieve remote certificate
        http_session = Rest.start_http_session(url)
        begin
          # retrieve underlying openssl socket
          result = Rest.io_http_session(http_session).io.peer_cert_chain
        rescue
          result = http_session.peer_cert
        ensure
          http_session.finish
        end
        result = result.map(&:to_pem).join("\n") if as_string
        return result
      end

      # Parses an HTTP Content-Type header string into its media type and parameters
      # according to RFC 9110 and RFC 6838.
      # TODO: use gem: content_type
      #
      # @param header [String] The Content-Type header string, e.g., "application/json; charset=utf-8"
      # @return [Hash] A hash with :type and :parameters keys.
      #   Example:
      #     {
      #       type: "application/json",
      #       parameters: {
      #         charset: "utf-8",
      #         version: "1.0"
      #       }
      #     }
      def parse_header(header)
        parts = header.split(';').map(&:strip)
        media_type = parts.shift.downcase
        parameters = parts.filter_map do |param|
          key, value = param.split('=', 2)
          next unless key && value
          key = key.strip.downcase.to_sym
          value = value.strip.gsub(/\A"|"\z/, '')
          [key, value]
        end.to_h
        {type: media_type, parameters: parameters}
      end
    end
  end
end
