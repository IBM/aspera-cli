require 'zlib'
require 'base64'
module Aspera
  # Provides additional functions using node API.
  class Node < Rest
    def self.decode_bearer_token(token)
      return JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition('==SIGNATURE==').first)
    end
    def initialize(rest_params)
      super(rest_params)
      # specifics here
    end
  end
end
