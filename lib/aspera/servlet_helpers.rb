# frozen_string_literal: true

require 'json'
require 'openssl'
require 'uri'
require 'webrick'
require 'aspera/mime'
require 'aspera/web_server_simple'

module Aspera
  # Mixin for WEBrick servlets of local web servers: JSON responses, and check of requests that a web page could send.
  #
  # A web page open in the browser of the user can send requests to a server that the browser reaches, also on localhost:
  # - Cross-site request forgery: a form, or a `fetch` with a CORS-safelisted `Content-Type` (`text/plain`, form), is sent cross-origin without preflight.
  # - DNS rebinding: a host name of the attacker that resolves to `127.0.0.1` makes the page same-origin with the server, so it also reads responses.
  module ServletHelpers
    class << self
      # @param url [String] URL
      # @return [String] Origin of the URL, as in header `Origin`, e.g. `https://example.com:8443`
      def origin(url)
        uri = URI.parse(url)
        port = ":#{uri.port}" unless uri.port.eql?(uri.default_port)
        "#{uri.scheme}://#{uri.host}#{port}".downcase
      end

      # @param host [String] Value of header `Host`, e.g. `[::1]:8080`
      # @return [String] Host name, without port and IPv6 brackets
      def host_name(host)
        return host[/\A\[([^\]]*)\]/, 1].to_s if host.start_with?('[')
        host.split(':').first.to_s
      end

      # Scheme is not compared: header `Host` has none
      # @param origin [String] Value of header `Origin`, e.g. `http://localhost:8080`
      # @param host   [String] Value of header `Host`, e.g. `localhost:8080`
      # @return [Boolean] `true` if the origin is the one of the requested server
      def same_origin?(origin, host)
        default_port = origin.start_with?('https://') ? ':443' : ':80'
        origin.sub(%r{\Ahttps?://}, '').delete_suffix(default_port).eql?(host.delete_suffix(default_port))
      end
    end

    # Set a JSON response
    # @param response [WEBrick::HTTPResponse]
    # @param status   [Integer]     HTTP status code
    # @param body     [Hash, Array] Body of the response
    # @param headers  [Hash{String => String}] Other headers of the response, e.g. `Cache-Control`
    # @return [nil]
    def json_response(response, status, body, headers: {})
      response.status = status
      response['Content-Type'] = Mime::JSON
      headers.each { |name, value| response[name] = value }
      response.body = JSON.generate(body)
      nil
    end

    # Set a JSON error response, in the format of OAuth 2.0 (RFC 6749 §5.2)
    # @param response    [WEBrick::HTTPResponse]
    # @param status      [Integer]     HTTP status code
    # @param error       [String]      Error code or message
    # @param description [String, nil] Details
    # @param headers     [Hash{String => String}] Other headers of the response, e.g. `WWW-Authenticate`
    # @return [nil]
    def json_error(response, status, error, description = nil, headers: {})
      body = {error: error}
      body[:error_description] = description unless description.nil?
      json_response(response, status, body, headers: headers)
    end

    # @param request [WEBrick::HTTPRequest]
    # @param scheme  [String] Authentication scheme, e.g. `Basic` or `Bearer`
    # @return [String, nil] Credentials of header `Authorization` if it has this scheme, else `nil`
    def authorization(request, scheme)
      request_scheme, credentials = request['Authorization'].to_s.split(' ', 2)
      credentials.to_s if request_scheme.to_s.casecmp?(scheme)
    end

    # Check the credentials of HTTP Basic authentication, in constant time
    # @param request  [WEBrick::HTTPRequest]
    # @param expected [String] Expected `username:password`
    # @return [Boolean] `true` if the request has the expected credentials
    def basic_authorized?(request, expected)
      OpenSSL.secure_compare(authorization(request, 'Basic').to_s.unpack1('m').to_s, expected)
    end

    # Refuse a request that a web page in a browser could send. Clients that are not browsers send no `Origin`, and the `Host` of the URL they call.
    # - `Host`: when the server listens on loopback, a loopback name or address, or one of `allowed_hosts` (DNS rebinding)
    # - `Origin`: when present, the origin of the server, or one of `allowed_origins` (cross-site request)
    # - `Content-Type`: with `json`, a JSON type, which a browser sends cross-origin only after a preflight request `OPTIONS`, not answered (cross-site request)
    # @param request         [WEBrick::HTTPRequest]
    # @param json            [Boolean]       `true` if the body, if any, is parsed as JSON
    # @param allowed_hosts   [Array<String>] Other values accepted in `Host`: host name, or `host:port`
    # @param allowed_origins [Array<String>] Other values accepted in `Origin`, e.g. `https://example.com`
    # @raise [WEBrick::HTTPStatus::Forbidden]            if `Host` or `Origin` is refused
    # @raise [WEBrick::HTTPStatus::UnsupportedMediaType] if the body is not JSON
    def check_request(request, json: false, allowed_hosts: [], allowed_origins: [])
      host = request['Host']&.downcase
      if host && WebServerSimple.loopback?(@server[:BindAddress].to_s)
        name = ServletHelpers.host_name(host)
        host_allowed = WebServerSimple.loopback?(name) || allowed_hosts.any? { |allowed_host| [name, host].include?(allowed_host.downcase) }
        raise WEBrick::HTTPStatus::Forbidden, "Host is not a loopback address: #{host}" unless host_allowed
      end
      origin = request['Origin']&.downcase
      origin_allowed = origin.nil? || (host && ServletHelpers.same_origin?(origin, host)) || allowed_origins.any? { |allowed_origin| allowed_origin.downcase.eql?(origin) }
      raise WEBrick::HTTPStatus::Forbidden, "Origin is not the one of the server: #{origin}" unless origin_allowed
      return unless json && !request.body.to_s.empty?
      media_type = request['Content-Type'].to_s.split(';').first.to_s.strip.downcase
      raise WEBrick::HTTPStatus::UnsupportedMediaType, "Content-Type shall be #{Mime::JSON}: #{media_type}" unless Mime.json?(media_type)
    end
  end
end
