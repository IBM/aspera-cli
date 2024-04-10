# frozen_string_literal: true

require 'aspera/oauth/base'
require 'aspera/assert'
require 'securerandom'
module Aspera
  module OAuth
    # Authentication using private key
    class Jwt < Base
      # @param g_o:private_key_obj [M] for type :jwt
      # @param g_o:payload         [M] for type :jwt
      # @param g_o:headers         [0] for type :jwt
      def initialize(
        payload:,
        private_key_obj:,
        headers: {},
        **base_params
      )
        Aspera.assert_type(payload, Hash){'payload'}
        Aspera.assert_type(private_key_obj, OpenSSL::PKey::RSA){'private_key_obj'}
        Aspera.assert_type(headers, Hash){'headers'}
        super(**base_params)
        @private_key_obj = private_key_obj
        @payload = payload
        @headers = headers
        @identifiers.push(@payload[:sub])
      end

      def create_token
        # https://tools.ietf.org/html/rfc7523
        # https://tools.ietf.org/html/rfc7519
        require 'jwt'
        seconds_since_epoch = Time.new.to_i
        Log.log.info{"seconds=#{seconds_since_epoch}"}
        Aspera.assert(@payload.is_a?(Hash)){'missing JWT payload'}
        jwt_payload = {
          exp: seconds_since_epoch + OAuth::Factory.instance.globals[:jwt_expiry_offset_sec], # expiration time
          nbf: seconds_since_epoch - OAuth::Factory.instance.globals[:jwt_accepted_offset_sec], # not before
          iat: seconds_since_epoch - OAuth::Factory.instance.globals[:jwt_accepted_offset_sec] + 1, # issued at (we tell a little in the past so that server always accepts)
          jti: SecureRandom.uuid # JWT id
        }.merge(@payload)
        Log.log.debug{"JWT jwt_payload=[#{jwt_payload}]"}
        Log.log.debug{"private=[#{@private_key_obj}]"}
        assertion = JWT.encode(jwt_payload, @private_key_obj, 'RS256', @headers)
        Log.log.debug{"assertion=[#{assertion}]"}
        return create_token_call(optional_scope_client_id.merge(grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: assertion))
      end
    end
    Factory.instance.register_token_creator(Jwt)
  end
end
