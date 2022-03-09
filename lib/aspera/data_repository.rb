# frozen_string_literal: true
require 'aspera/log'
require 'singleton'

module Aspera
  # a simple binary data repository
  class DataRepository
    include Singleton
    # get binary value from data repository
    def get_bin(id)
      File.read(File.join(File.expand_path(File.dirname(__FILE__)),'data',id.to_s),mode: 'rb')
    end
  end
end
