# frozen_string_literal: true

require 'aspera/oauth/base'
require 'aspera/assert'
require 'securerandom'
require 'openssl'
module Aspera
  module OAuth
    # remove 5 minutes to account for time offset between client and server (TODO: configurable?)
    Factory.instance.parameters[:jwt_accepted_offset_sec] = 300
    # one hour validity (TODO: configurable?)
    Factory.instance.parameters[:jwt_expiry_offset_sec] = 3600
    # Authentication using private key
    # https://tools.ietf.org/html/rfc7523
    # https://tools.ietf.org/html/rfc7519
    class Jwt < Base
      class << self
        def generate_rsa_private_key(path:, length: DEFAULT_PRIV_KEY_LENGTH)
          priv_key = OpenSSL::PKey::RSA.new(length)
          File.write(path, priv_key.to_s)
          File.write("#{path}.pub", priv_key.public_key.to_s)
          Environment.restrict_file_access(path)
          Environment.restrict_file_access("#{path}.pub")
          nil
        end
      end
      DEFAULT_PRIV_KEY_LENGTH = 4096
      GRANT_TYPE = 'urn:ietf:params:oauth:grant-type:jwt-bearer'
      # @param private_key_obj private key object
      # @param payload payload to be included in the JWT
      # @param headers headers to be included in the JWT
      def initialize(
        private_key_obj:,
        payload:,
        headers: {},
        cache_ids: [],
        **base_params
      )
        Aspera.assert_type(private_key_obj, OpenSSL::PKey::RSA){'private_key_obj'}
        Aspera.assert_type(payload, Hash){'payload'}
        Aspera.assert_type(headers, Hash){'headers'}
        Aspera.assert_type(cache_ids, Array){'cache ids'}
        new_cache_ids = cache_ids.clone.push(payload[:sub])
        super(**base_params, cache_ids: new_cache_ids)
        @private_key_obj = private_key_obj
        @additional_payload = payload
        @headers = headers
      end

      def create_token
        require 'jwt'
        seconds_since_epoch = Time.new.to_i
        Log.log.debug{"seconds_since_epoch=#{seconds_since_epoch}"}
        jwt_payload = {
          exp: seconds_since_epoch + OAuth::Factory.instance.parameters[:jwt_expiry_offset_sec], # expiration time
          nbf: seconds_since_epoch - OAuth::Factory.instance.parameters[:jwt_accepted_offset_sec], # not before
          iat: seconds_since_epoch - OAuth::Factory.instance.parameters[:jwt_accepted_offset_sec] + 1, # issued at
          jti: SecureRandom.uuid # JWT id
        }.merge(@additional_payload)
        Log.dump(:jwt_payload, jwt_payload)
        Log.log.debug{"private=[#{@private_key_obj}]"}
        assertion = JWT.encode(jwt_payload, @private_key_obj, 'RS256', @headers)
        Log.log.debug{"assertion=[#{assertion}]"}
        return create_token_call(base_params.merge(grant_type: GRANT_TYPE, assertion: assertion))
      end
    end
    Factory.instance.register_token_creator(Jwt)
  end
end
