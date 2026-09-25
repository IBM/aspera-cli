# frozen_string_literal: true

module Aspera
  # MIME types used in `Content-Type` and `Accept`
  module Mime
    # JSON body
    JSON = 'application/json'
    # URL encoded form body
    WWW = 'application/x-www-form-urlencoded'
    # Plain text body
    TEXT = 'text/plain'
    # JSON:API body (https://jsonapi.org)
    JSON_API = 'application/vnd.api+json'
    # Check if a media type is JSON: `application/json` or structured syntax suffix `+json` (RFC 6839)
    # @param mime [String] Media type, without parameters (see `Rest.parse_header`)
    # @return [Boolean] `true` if JSON
    def json?(mime) = mime == JSON || mime.end_with?(JSON_SUFFIX) || mime == LEGACY_JSON
    module_function :json?
    # Structured syntax suffix for JSON
    JSON_SUFFIX = '+json'
    # Non standard type used by some servers for JSON
    LEGACY_JSON = 'application/x-javascript'
    private_constant :JSON_SUFFIX, :LEGACY_JSON
  end
end
