# frozen_string_literal: true

require 'aspera/assert'
require 'singleton'
require 'openssl'
require 'zlib'
require 'base64'

module Aspera
  # a simple binary data repository
  #
  # @!method self.instance
  #   Returns the singleton instance of DataRepository
  #   @return [DataRepository] the singleton instance
  class DataRepository
    include Singleton

    # name of data item => name of its file in data folder
    FILES = {
      dsa:                        '1',
      rsa:                        '2',
      uuid:                       '3',
      'aspera.global-cli-client': '4',
      'aspera.drive':             '5',
      license:                    '6'
    }.freeze
    # names of data items
    ELEMENTS = FILES.keys.freeze
    DATA_FOLDER_NAME = 'data'

    # Get a data item, decoded to its usable form
    # @param name [Symbol] name of the data item, one of ELEMENTS
    # @return [String] PEM private key (dsa, rsa), UUID (uuid), base64url secret (client apps), or text (license)
    def item(name)
      Aspera.assert_values(name, ELEMENTS, type: ParameterError) { 'data item' }
      raw_data = data(name)
      value =
        case name
        when :dsa, :rsa
          # generate PEM from DER
          OpenSSL::PKey.read(raw_data).to_pem
        when :license
          Zlib::Inflate.inflate(raw_data)
        when :uuid
          format('%08x-%04x-%04x-%04x-%04x%08x', *raw_data.unpack('NnnnnN'))
        when :'aspera.global-cli-client', :'aspera.drive'
          Base64.urlsafe_encode64(raw_data)
        else Aspera.error_unexpected_value(name)
        end
      # all items are text
      return value.force_encoding(Encoding::UTF_8)
    end

    private

    private_constant :FILES, :DATA_FOLDER_NAME

    # get binary value from data repository
    # @param name [Symbol] name of the data item
    # @return [String] raw binary data
    def data(name)
      File.binread(File.join(__dir__, DATA_FOLDER_NAME, FILES[name]))
    end
  end
end
