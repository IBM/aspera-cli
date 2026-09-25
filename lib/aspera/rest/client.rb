# frozen_string_literal: true

require 'aspera/mime'
require 'aspera/rest/parameters'
require 'aspera/rest/util'
require 'aspera/rest/call_error'
require 'aspera/rest/error_analyzer'
require 'aspera/rest/aspera_errors'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/oauth'
require 'aspera/hash_ext'
require 'aspera/timer_limiter'
require 'net/http'
require 'net/https'
require 'json'
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
  module Rest
    # Make HTTP calls, equivalent to rest-client
    # rest call errors are raised as exception CallError
    # and error are analyzed in ErrorAnalyzer
    class Client
      private

      # Create and start keep alive connection on demand
      # @return [Net::HTTP] Started HTTP session
      def http_session = @http_session ||= Rest.start_http_session(@base_url)

      public

      # All original constructor parameters
      attr_reader :auth_params

      # The root URL for the API
      attr_reader :base_url

      # Base common headers of API
      attr_reader :headers

      # Parameters to create a copy of this object, e.g. `Rest::Client.new(**api.params)`
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
      # HTTP sessions parameters can be modified using global parameters in Parameters
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
        Log.log.debug { "Client.new(#{@base_url})" }
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
        @headers['User-Agent'] ||= Parameters.instance.user_agent
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
      # @raise [CallError] on error if `exception` is true
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
        error_tries = 1 + Parameters.instance.retry_max
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
            result_mime = Rest.parse_header(result_http['Content-Type'] || Mime::TEXT)[:type]
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
          ErrorAnalyzer.instance.raise_on_error(req, result_data, result_http)
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
        rescue CallError => e
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

      # Decide if an error is retried, according to Parameters
      # @param error [Exception] Network error or CallError
      # @return [Boolean] `true` if the request shall be retried
      def retry_error?(error)
        settings = Parameters.instance
        # the request was not sent (connection) or its result is unknown (other)
        return error.is_a?(Net::OpenTimeout) ? settings.retry_on_timeout : settings.retry_on_error unless error.is_a?(CallError)
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

      # Wait before retry, according to Parameters
      # @return [void]
      def retry_sleep
        sleep(Parameters.instance.retry_sleep) unless Parameters.instance.retry_sleep.eql?(0)
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
        Client.new(**rest_params).call(subpath: new_url.end_with?('/') ? '/' : nil, query: query, headers: headers, **call_args)
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
        uri = Rest.build_uri("#{@base_url}#{separator}#{subpath}", query)
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
          disposition = Rest.parse_header(response['Content-Disposition'])
          if disposition[:parameters].key?(:filename) && !disposition[:parameters][:filename].eql?('.')
            # Use only the basename to prevent path traversal via a server-controlled Content-Disposition header
            safe_filename = File.basename(disposition[:parameters][:filename])
            target_file = File.join(File.dirname(target_file), safe_filename) unless safe_filename.empty?
          end
        end
        Log.log.debug { "saving to: #{target_file}" }
        written_size = 0
        session_id = SecureRandom.uuid.freeze
        Parameters.instance.progress_bar&.event(:session_start, session_id: session_id)
        Parameters.instance.progress_bar&.event(:session_size, session_id: session_id, info: total_size) if total_size
        limiter = TimerLimiter.new(0.5)
        if target_file.respond_to?(:write)
          # IO object: stream directly into it
          response.read_body do |fragment|
            target_file.write(fragment)
            written_size += fragment.length
            Parameters.instance.progress_bar&.event(:transfer, session_id: session_id, info: written_size) if limiter.trigger?
          end
        else
          # file path: download to partial name first, then rename atomically
          target_file_tmp = "#{target_file}#{Parameters.instance.download_partial_suffix}"
          FileUtils.mkdir_p(File.dirname(target_file_tmp))
          File.open(target_file_tmp, 'wb') do |file|
            response.read_body do |fragment|
              file.write(fragment)
              written_size += fragment.length
              Parameters.instance.progress_bar&.event(:transfer, session_id: session_id, info: written_size) if limiter.trigger?
            end
          end
          File.rename(target_file_tmp, target_file)
        end
        Parameters.instance.progress_bar&.event(:session_end, session_id: session_id)
        Parameters.instance.progress_bar&.event(:end)
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
end
