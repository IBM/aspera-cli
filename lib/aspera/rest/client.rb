# frozen_string_literal: true

require 'aspera/mime'
require 'aspera/rest_errors_aspera'
require 'aspera/rest_error_analyzer'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/oauth'
require 'aspera/hash_ext'
require 'aspera/timer_limiter'
require 'net/http'
require 'net/https'
require 'json'
require 'base64'
require 'singleton'
require 'securerandom'
require 'fileutils'
require 'pathname'
require 'aspera/rainbow'
using Rainbow

# Cancel method for HTTP
class Net::HTTP::Cancel < Net::HTTPRequest # rubocop:disable Style/ClassAndModuleChildren
  # HTTP method name
  METHOD = 'CANCEL'
  # No request body
  REQUEST_HAS_BODY  = false
  # No response body
  RESPONSE_HAS_BODY = false
end

module Aspera
  # Global settings for Rest object
  # For example to remove certificate verification globally:
  # `RestParameters.instance.session_cb = lambda{|http|http.verify_mode=OpenSSL::SSL::VERIFY_NONE}`
  #
  # @!method self.instance
  #   Returns the singleton instance of RestParameters
  #   @return [RestParameters] the singleton instance
  class RestParameters
    include Singleton

    # @return [String] HTTP request header: `User-Agent`
    attr_accessor :user_agent
    # @return [String] Suffix of file being downloaded, removed when download is complete
    attr_accessor :download_partial_suffix
    # @return [Boolean] Retry on any error (network or HTTP)
    attr_accessor :retry_on_error
    # @return [Boolean] Retry on connection timeout
    attr_accessor :retry_on_timeout
    # @return [Boolean] Retry on HTTP code 503 (service unavailable)
    attr_accessor :retry_on_unavailable
    # @return [Integer] Maximum number of retries on error (first call not included)
    attr_accessor :retry_max
    # @return [Integer] Seconds to wait before retry
    attr_accessor :retry_sleep
    # @return [Proc, nil] Called on new HTTP session, with the `Net::HTTP` as argument, e.g. to set timeouts or certificate verification
    attr_accessor :session_cb
    # @return [Object, nil] Progress bar, receives `event` calls during download
    attr_accessor :progress_bar
    # @return [Proc, nil] Called with `(title = nil, action: :spin)` to display progress of long operations
    attr_accessor :spinner_cb

    private

    # Set default values
    def initialize
      @user_agent = 'RubyAsperaRest'
      @download_partial_suffix = '.http_partial'
      @retry_on_error = false
      @retry_on_timeout = true
      @retry_on_unavailable = true
      @retry_max = 1
      @retry_sleep = 4
      @session_cb = nil
      @progress_bar = nil
      @spinner_cb = nil
    end
  end

  # Raised when a looked up entity is not found
  class EntityNotFound < Error
  end

  # Make HTTP calls, equivalent to rest-client
  # rest call errors are raised as exception RestCallError
  # and error are analyzed in RestErrorAnalyzer
  class Rest
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
        RestParameters.instance.session_cb&.call(http_session)
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

    private

    # Create and start keep alive connection on demand
    # @return [Net::HTTP] Started HTTP session
    def http_session = @http_session ||= self.class.start_http_session(@base_url)

    public

    # All original constructor parameters
    attr_reader :auth_params

    # The root URL for the API
    attr_reader :base_url

    # Base common headers of API
    attr_reader :headers

    # Parameters to create a copy of this object, e.g. `Rest.new(**api.params)`
    # @return [Hash] Creation parameters (copy)
    def params
      return {
        base_url:       @base_url,           # String
        auth:           @auth_params.dup,    # Hash
        not_auth_codes: @not_auth_codes.dup, # Array
        redirect_max:   @redirect_max,       # Integer
        headers:        @headers.dup         # Hash
      }
    end

    # Create a REST object for API calls
    # HTTP sessions parameters can be modified using global parameters in RestParameters
    # For example, TLS verification can be skipped.
    # @param base_url [String] base URL of REST API
    # @param auth [Hash] authentication parameters:
    #     :type (:none, :basic, :url, :oauth2)
    #     :username   [:basic]
    #     :password   [:basic]
    #     :url_query  [:url]    a hash
    #     :*          [:oauth2] see OAuth::Factory class
    # @param not_auth_codes [Array]   codes that trigger a refresh/regeneration of bearer token
    # @param redirect_max   [Integer] max redirection allowed
    # @param headers        [Hash]    default headers to include in all calls
    def initialize(
      base_url:,
      auth: {type: :none},
      not_auth_codes: ['401'],
      redirect_max: 0,
      headers: {}
    )
      Aspera.assert_type(base_url, String)
      # base url with no trailing slashes (note: string may be frozen)
      @base_url = base_url.chomp('/')
      # remove trailing port if it is 443 and scheme is https
      @base_url = @base_url.gsub(/:443$/, '') if @base_url.start_with?('https://')
      @base_url = @base_url.gsub(/:80$/, '') if @base_url.start_with?('http://')
      Log.log.debug { "Rest.new(#{@base_url})" }
      # default is no auth
      @auth_params = auth
      Aspera.assert_type(@auth_params, Hash)
      Aspera.assert(@auth_params.key?(:type), 'no auth type defined')
      @not_auth_codes = not_auth_codes
      Aspera.assert_type(@not_auth_codes, Array)
      # persistent session
      @http_session = nil
      @redirect_max = redirect_max
      Aspera.assert_type(@redirect_max, Integer)
      @headers = headers.clone
      Aspera.assert_type(@headers, Hash)
      @headers['User-Agent'] ||= RestParameters.instance.user_agent
      # OAuth object (created on demand)
      @oauth = nil
    end

    # OAuth object used for authorization, when auth type is `:oauth2`
    # @return [OAuth::Base] the OAuth object (create, or cached if already created)
    def oauth
      if @oauth.nil?
        Aspera.assert(@auth_params[:type].eql?(:oauth2), 'no OAuth defined')
        oauth_parameters = @auth_params.reject { |k, _v| k.eql?(:type) }
        Log.dump(:oauth_parameters, oauth_parameters)
        @oauth = OAuth::Factory.instance.create(**oauth_parameters)
      end
      return @oauth
    end

    # HTTP/S REST call
    # @param operation    [String] HTTP operation (GET, POST, PUT, DELETE)
    # @param subpath      [String] subpath of REST API
    # @param query        [Hash{String,Symbol => Object}] URL parameters
    # @param content_type [String, nil] Type of body parameters (one of MIME_*) and serialization, else use headers
    # @param body         [Hash, String, nil] Body parameters
    # @param headers      [Hash{String => String}] Additional headers (override Content-Type)
    # @param save_to      [String, Pathname, IO, nil] File path or IO object to save response body; progress bar is used when set
    # @param exception    [Boolean] Whether to raise an exception on HTTP error
    # @param ret          [Symbol] One of :data, :resp, :both - controls return value
    # @return [Array(Hash, Net::HTTPResponse)] When `ret` is :both
    # @return [Net::HTTPResponse] When `ret` is :resp
    # @return [Hash] When `ret` is :data
    # @raise [RestCallError] on error if `exception` is true
    def call(
      operation:,
      subpath: nil,
      query: nil,
      content_type: nil,
      body: nil,
      headers: nil,
      save_to: nil,
      exception: true,
      ret: :data
    )
      subpath = subpath.to_s if subpath.is_a?(Symbol)
      subpath = '' if subpath.nil?
      # File path (String or Pathname) or stream (responds to `write`)
      # Pathname also responds to `write` (overwrites file), so it must not be taken as a stream
      save_to = save_to.to_s if save_to.is_a?(Pathname)
      Aspera.assert(save_to.nil? || save_to.is_a?(String) || save_to.respond_to?(:write)) { "save_to: unsupported type #{save_to.class}" }
      Log.log.debug { "call #{operation} [#{subpath}]".red.bold.bg(:green) }
      Log.dump(:body, body, level: :trace1)
      Log.dump(:query, query, level: :trace1)
      Log.dump(:headers, headers, level: :trace1)
      Aspera.assert_type(subpath, String)
      # We must have a way to check return code
      Aspera.assert(exception || !ret.eql?(:data), 'ret: :data requires exception handler')
      req_headers, req_query = prepare_call(headers, query)
      result_http = nil
      result_data = nil
      # number of tries on error (first call included)
      error_tries = 1 + RestParameters.instance.retry_max
      # OAuth token is renewed only once, independently of error retries
      token_renewed = false
      # start a block to be able to retry the actual HTTP request in case of OAuth token expiration
      begin
        Log.log.debug("send request (redirects=#{@redirect_max})")
        req = build_request(operation, subpath, req_query, content_type, body, req_headers)
        result_mime = nil
        file_saved = false
        # make http request (pipelined)
        http_session.request(req) do |response|
          result_http = response
          result_mime = self.class.parse_header(result_http['Content-Type'] || Mime::TEXT)[:type]
          Log.log.debug { "response: code=#{result_http.code}, mime=#{result_mime}, content-type=#{response['Content-Type']}" }
          # JSON data needs to be parsed, in case it contains an error code
          file_saved = save_response(response, result_mime, save_to)
        end
        Log.log.debug { "result: code=#{result_http.code} mime=#{result_mime}" }
        # sometimes there is a UTF8 char (e.g. (c) )
        # TODO : related to mime type encoding ?
        # result_http.body.force_encoding('UTF-8') if result_http.body.is_a?(String)
        # Log.log.debug{"result: body=#{result_http.body}"}
        result_data = parse_response(result_http, result_mime)
        RestErrorAnalyzer.instance.raise_on_error(req, result_data, result_http)
        unless file_saved || save_to.nil?
          raise 'save_to: IO object requires a streaming response' if save_to.respond_to?(:write)
          FileUtils.mkdir_p(File.dirname(save_to))
          File.write(save_to, result_http.body, binmode: true)
        end
      rescue *NETWORK_ERRORS => e
        raise unless retry_error?(e) && (error_tries -= 1).positive?
        Log.log.warn { "#{e.class}: #{e.message}: retrying" }
        retry_sleep
        retry
      rescue RestCallError => e
        # not authorized: OAuth token expired
        if !token_renewed && @not_auth_codes.include?(result_http.code.to_s) && @auth_params[:type].eql?(:oauth2)
          token_renewed = true
          new_authorization = renew_oauth_authorization
          unless new_authorization.nil?
            Log.log.debug('using new token')
            req_headers['Authorization'] = new_authorization
            retry
          end
        end
        if retry_error?(e) && (error_tries -= 1).positive?
          retry_sleep
          retry
        end
        # redirect ? (any code beginning with 3)
        if e.response.is_a?(Net::HTTPRedirection) && @redirect_max.positive?
          return redirect_call(
            req.uri,
            e.response['Location'],
            operation:    operation,
            body:         body,
            content_type: content_type,
            save_to:      save_to,
            exception:    exception,
            headers:      headers,
            ret:          ret
          )
        end
        # raise exception if could not retry and not return error in result
        raise e if exception
      end
      Log.log.debug { "result=http:#{result_http}, data:#{result_data.class}" }
      return case ret
             when :data then result_data
             when :resp then result_http
             when :both then [result_data, result_http]
             else Aspera.error_unexpected_value(ret) { 'Type of result for REST' }
             end
    end

    private

    # Decide if an error is retried, according to RestParameters
    # @param error [Exception] Network error or RestCallError
    # @return [Boolean] `true` if the request shall be retried
    def retry_error?(error)
      settings = RestParameters.instance
      # the request was not sent (connection) or its result is unknown (other)
      return error.is_a?(Net::OpenTimeout) ? settings.retry_on_timeout : settings.retry_on_error unless error.is_a?(RestCallError)
      response = error.response
      # a redirect is followed, not retried
      return false if response.is_a?(Net::HTTPRedirection)
      # AoC have some timeout , like Connect to platform.bss.asperasoft.com:443 ...
      (settings.retry_on_timeout && response.body&.include?('failed: connect timed out')) ||
        # AoC sometimes not available
        (settings.retry_on_unavailable && UNAVAILABLE_CODES.include?(response.code.to_s)) ||
        # possibility to retry anything if it fails
        settings.retry_on_error
    end

    # Wait before retry, according to RestParameters
    # @return [void]
    def retry_sleep
      sleep(RestParameters.instance.retry_sleep) unless RestParameters.instance.retry_sleep.eql?(0)
    end

    # Renew OAuth token: use refresh token, or generate a new one
    # @return [String, nil] New value for header `Authorization`, or `nil` if no new token could be obtained
    def renew_oauth_authorization
      oauth.authorization(refresh: true)
    rescue StandardError => e
      Log.log.error("refresh failed: #{e.message}".bg(:red))
      begin
        oauth.authorization(cache: false)
      rescue StandardError => e
        Log.log.error("new token failed: #{e.message}".bg(:red))
        nil
      end
    end

    # Forward the call to the location of a redirect response.
    # Same server: same API parameters (auth, headers). Other server: credentials are not forwarded.
    # @param request_uri [URI]       URI of the redirected request
    # @param location    [String]    Header `Location` of redirect response (absolute or relative)
    # @param headers     [Hash, nil] Headers of the call
    # @param call_args   [Hash]      Other arguments of `call`
    # @return [Object] Result of `call` on new location
    def redirect_call(request_uri, location, headers:, **call_args)
      Aspera.assert(!location.nil?) { 'redirect response without Location' }
      new_uri = URI.join(request_uri.to_s, location)
      # query of `Location` is used as call query, so that auth query is added
      query = new_uri.query
      new_uri.query = nil
      new_uri.fragment = nil
      new_url = new_uri.to_s
      Log.log.debug { "redirect to #{new_url}" }
      rest_params = params.merge(base_url: new_url, redirect_max: @redirect_max - 1)
      unless [new_uri.scheme, new_uri.host, new_uri.port].eql?([request_uri.scheme, request_uri.host, request_uri.port])
        Log.log.debug { "redirect to other server: #{new_uri.host}, credentials not forwarded" }
        rest_params[:auth] = {type: :none}
        rest_params[:headers] = without_credentials(@headers)
        headers = without_credentials(headers) unless headers.nil?
      end
      Rest.new(**rest_params).call(subpath: new_url.end_with?('/') ? '/' : nil, query: query, headers: headers, **call_args)
    end

    # @param headers [Hash] HTTP headers
    # @return [Hash] Headers without credentials
    def without_credentials(headers) = headers.reject { |k, _| CREDENTIAL_HEADERS.include?(k.to_s.downcase) }

    # Add base headers and authentication to call parameters
    # @param headers [Hash, nil]              Headers of call
    # @param query   [Hash, String, Array, nil] Query of call
    # @return [Array(Hash, Object)] Headers and query for the request
    def prepare_call(headers, query)
      headers = @headers.merge(headers || {})
      case @auth_params[:type]
      when :none
        # no auth
      when :basic
        Log.log.debug('using Basic auth')
        # done in build_req
      when :oauth2
        headers['Authorization'] = oauth.authorization unless headers.key?('Authorization')
      when :url
        query =
          case query
          when nil then @auth_params[:url_query].dup
          when Hash then query.merge(@auth_params[:url_query])
          when String then [query, URI.encode_www_form(@auth_params[:url_query])].join('&')
          else Aspera.error_unexpected_value(query.class) { 'query type with url auth' }
          end
      else Aspera.error_unexpected_value(@auth_params[:type])
      end
      [headers, query]
    end

    # Build HTTP request, including body and basic authentication
    # @param operation    [String]                  HTTP operation (GET, POST, ...)
    # @param subpath      [String]                  Subpath of REST API
    # @param query        [Hash, String, Array, nil] Query of request
    # @param content_type [String, nil]             One of Mime::JSON, Mime::WWW, Mime::TEXT, or `nil` for no body
    # @param body         [Hash, String, nil]       Body of request, serialized according to `content_type`
    # @param headers      [Hash]                    Headers of request
    # @return [Net::HTTPRequest] The request
    def build_request(operation, subpath, query, content_type, body, headers)
      # TODO: shall we percent encode subpath (spaces) test with access key delete with space in id
      # URI.escape()
      separator = ['', '/'].include?(subpath) ? '' : '/'
      uri = self.class.build_uri("#{@base_url}#{separator}#{subpath}", query)
      Log.log.debug { "URI=#{uri}" }
      begin
        # instantiate request object based on string name
        req = Net::HTTP.const_get(operation.capitalize).new(uri)
      rescue NameError
        raise "unsupported operation : #{operation}"
      end
      case content_type
      when nil # ignore
      when Mime::JSON
        req.body = JSON.generate(body) # , ascii_only: true
        req['Content-Type'] = Mime::JSON
      when Mime::WWW
        req.body = URI.encode_www_form(body)
        req['Content-Type'] = Mime::WWW
      when Mime::TEXT
        req.body = body
        req['Content-Type'] = Mime::TEXT
      else Aspera.error_unexpected_value(content_type) { 'body type' }
      end
      # set headers
      headers.each do |key, value|
        req[key] = value
      end
      # :type = :basic
      req.basic_auth(@auth_params[:username], @auth_params[:password]) if @auth_params[:type].eql?(:basic)
      Log.dump(:req_body, req.body, level: :trace1)
      req
    end

    # Save response body to file or stream, if successful and not JSON (streamed download with progress)
    # @param response    [Net::HTTPResponse]   Response, body not read yet
    # @param result_mime [String]              Media type of response
    # @param save_to     [String, IO, nil]     File path or IO object
    # @return [Boolean] `true` if body was saved
    def save_response(response, result_mime, save_to)
      return false unless !save_to.nil? && response.code.to_s.start_with?('2') && !Mime.json?(result_mime)

      total_size = response['Content-Length']&.to_i
      Log.log.debug('before write file')
      target_file = save_to
      # override user's path to path in header (only for file path, not for stream)
      if target_file.is_a?(String) && !response['Content-Disposition'].nil?
        disposition = self.class.parse_header(response['Content-Disposition'])
        if disposition[:parameters].key?(:filename) && !disposition[:parameters][:filename].eql?('.')
          # Use only the basename to prevent path traversal via a server-controlled Content-Disposition header
          safe_filename = File.basename(disposition[:parameters][:filename])
          target_file = File.join(File.dirname(target_file), safe_filename) unless safe_filename.empty?
        end
      end
      Log.log.debug { "saving to: #{target_file}" }
      written_size = 0
      session_id = SecureRandom.uuid.freeze
      RestParameters.instance.progress_bar&.event(:session_start, session_id: session_id)
      RestParameters.instance.progress_bar&.event(:session_size, session_id: session_id, info: total_size) if total_size
      limiter = TimerLimiter.new(0.5)
      if target_file.respond_to?(:write)
        # IO object: stream directly into it
        response.read_body do |fragment|
          target_file.write(fragment)
          written_size += fragment.length
          RestParameters.instance.progress_bar&.event(:transfer, session_id: session_id, info: written_size) if limiter.trigger?
        end
      else
        # file path: download to partial name first, then rename atomically
        target_file_tmp = "#{target_file}#{RestParameters.instance.download_partial_suffix}"
        FileUtils.mkdir_p(File.dirname(target_file_tmp))
        File.open(target_file_tmp, 'wb') do |file|
          response.read_body do |fragment|
            file.write(fragment)
            written_size += fragment.length
            RestParameters.instance.progress_bar&.event(:transfer, session_id: session_id, info: written_size) if limiter.trigger?
          end
        end
        File.rename(target_file_tmp, target_file)
      end
      RestParameters.instance.progress_bar&.event(:session_end, session_id: session_id)
      RestParameters.instance.progress_bar&.event(:end)
      true
    end

    # Parse response body, according to media type
    # @param result_http [Net::HTTPResponse] Response
    # @param result_mime [String]            Media type of response
    # @return [Hash, Array, String, nil] Parsed JSON, or raw body
    def parse_response(result_http, result_mime)
      result_data = result_http.body
      Log.dump(:result_data_raw, result_data, level: :trace1)
      # TODO: Remove next 2 lines when bug in async node api is fixed. (Aspera/core/issues/4490)
      node_api_bug = result_data&.index('}HTTP/1.1 400 Bad Request') if result_data.is_a?(String)
      result_data = result_data[0..node_api_bug] if node_api_bug
      result_data = JSON.parse(result_data) if Mime.json?(result_mime) && !result_data.nil? && !result_data.empty?
      Log.dump(:result_data, result_data)
      result_data
    end

    public

    # @!group CRUD
    # Simplified methods accepting JSON, and sending JSON body.
    # If specific elements are needed, then use the full `call` method.

    # `POST` JSON body
    # @param subpath [String]  Subpath of REST API
    # @param params  [Hash]    Body
    # @param kwargs  [Hash]    Other arguments of `call`
    # @return [Object] Result of `call`
    def create(subpath, params, **kwargs) = call(operation: 'POST', subpath: subpath, body: params, **json_call_args(kwargs, body: true))

    # `GET`
    # @param subpath [String]    Subpath of REST API
    # @param query   [Hash, nil] Query
    # @param kwargs  [Hash]      Other arguments of `call`
    # @return [Object] Result of `call`
    def read(subpath, query = nil, **kwargs) = call(operation: 'GET', subpath: subpath, query: query, **json_call_args(kwargs))

    # `PUT` JSON body
    # @param subpath [String] Subpath of REST API
    # @param params  [Hash]   Body
    # @param kwargs  [Hash]   Other arguments of `call`
    # @return [Object] Result of `call`
    def update(subpath, params, **kwargs) = call(operation: 'PUT', subpath: subpath, body: params, **json_call_args(kwargs, body: true))

    # `DELETE`
    # @param subpath [String]    Subpath of REST API
    # @param params  [Hash, nil] Query
    # @param kwargs  [Hash]      Other arguments of `call`
    # @return [Object] Result of `call`
    def delete(subpath, params = nil, **kwargs) = call(operation: 'DELETE', subpath: subpath, query: params, **json_call_args(kwargs))

    # `CANCEL`
    # @param subpath [String] Subpath of REST API
    # @param kwargs  [Hash]   Other arguments of `call`
    # @return [Object] Result of `call`
    def cancel(subpath, **kwargs) = call(operation: 'CANCEL', subpath: subpath, **json_call_args(kwargs))

    # @!endgroup

    private

    # Defaults of CRUD methods: accept JSON, and send JSON body. Caller's arguments are not modified.
    # @param kwargs [Hash]    Arguments of `call`
    # @param body   [Boolean] `true` if a body is sent
    # @return [Hash] Arguments of `call`
    def json_call_args(kwargs, body: false)
      args = kwargs.merge(headers: {'Accept' => Mime::JSON}.merge(kwargs[:headers] || {}))
      args[:content_type] = Mime::JSON if body && !kwargs.key?(:content_type)
      args
    end

    # HTTP codes of service unavailable
    UNAVAILABLE_CODES = ['503']
    # Network errors that can be retried
    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE, EOFError, OpenSSL::SSL::SSLError
    ].freeze
    # Headers not forwarded on redirect to another server (lower case)
    CREDENTIAL_HEADERS = %w[authorization cookie].freeze

    private_constant :UNAVAILABLE_CODES, :NETWORK_ERRORS, :CREDENTIAL_HEADERS
  end
end
