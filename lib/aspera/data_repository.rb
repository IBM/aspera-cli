# frozen_string_literal: true

require 'aspera/assert'
require 'singleton'
require 'openssl'

module Aspera
  # a simple binary data repository
  class DataRepository
    include Singleton
    # in same order as elements in folder
    ELEMENTS = %i[dsa rsa uuid aspera.global-cli-client aspera.drive license]
    START_INDEX = 1
    DATA_FOLDER_NAME = 'data'

    # decode data as expected as string
    # @param name [Symbol] name of the data item
    # @return [String] decoded data
    def item(name)
      index = ELEMENTS.index(name)
      raise ArgumentError, "unknown data item #{name} (#{name.class})" unless index
      raw_data = data(START_INDEX + index)
      case name
      when :dsa, :rsa
        # generate PEM from DER
        return OpenSSL::PKey.const_get(name.to_s.upcase).new(raw_data).to_pem
      when :license
        return Zlib::Inflate.inflate(raw_data)
      when :uuid
        return format('%08x-%04x-%04x-%04x-%04x%08x', *raw_data.unpack('NnnnnN'))
      when :'aspera.global-cli-client', :'aspera.drive'
        return Base64.urlsafe_encode64(raw_data)
      else Aspera.error_unexpected_value(name)
      end
    end

    private

    private_constant :START_INDEX, :DATA_FOLDER_NAME

    # get binary value from data repository
    def data(id)
      File.read(File.join(__dir__, DATA_FOLDER_NAME, id.to_s), mode: 'rb')
    end
  end
end
