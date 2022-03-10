# frozen_string_literal: true
require 'aspera/log'
require 'singleton'

module Aspera
  # a simple binary data repository
  class DataRepository
    include Singleton
    # get binary value from data repository
    def data(id)
      File.read(File.join(__dir__,'data',id.to_s),mode: 'rb')
    end
  end
end
