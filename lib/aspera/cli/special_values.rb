# frozen_string_literal: true

module Aspera
  module Cli
    # base class for plugins modules
    module SpecialValues
      # special values
      # `INIT` to unitialize with all current IDs
      INIT = 'INIT'
      # `ALL` means "all ids"
      ALL = 'ALL'
      # `DEF` for the default list
      DEF = 'DEF'
      # `END` of arguments
      EOA = 'END'
      # `LATEST`
      LATEST = 'LATEST'
    end
  end
end
